-- Keep the current games catalog convenient for scheduling while preserving
-- every (game_id, version) contract referenced by a schedule or attempt.
create table public.game_rule_versions (
  game_id text not null references public.games (id),
  version integer not null,
  display_name text not null,
  description text not null default '',
  duration_seconds smallint not null,
  minimum_app_build integer not null,
  created_at timestamptz not null default now(),
  primary key (game_id, version),
  constraint game_rule_versions_version_positive check (version > 0),
  constraint game_rule_versions_duration_range
    check (duration_seconds between 10 and 600),
  constraint game_rule_versions_minimum_build_positive
    check (minimum_app_build > 0)
);

comment on table public.game_rule_versions is
  'Immutable metadata for every game version referenced by a schedule or play attempt.';
comment on column public.game_rule_versions.minimum_app_build is
  'The minimum client build that originally introduced this game version.';

alter table public.game_rule_versions enable row level security;
revoke all on table public.game_rule_versions from public;

-- Preserve the current catalog and the historical versions whose metadata is
-- still present in the migration history. The fallback below covers any
-- older references whose original display text is no longer recoverable.
insert into public.game_rule_versions (
  game_id, version, display_name, description, duration_seconds,
  minimum_app_build
)
select
  game.id,
  game.version,
  game.display_name,
  game.description,
  game.duration_seconds,
  game.minimum_app_build
from public.games game;

insert into public.game_rule_versions (
  game_id, version, display_name, description, duration_seconds,
  minimum_app_build
) values
  (
    'midnight_snake', 1, '야식털이 뱀',
    '밤에 탈출한 애완뱀을 스와이프로 조종해 야식을 먹고 벽과 자기 몸을 피하세요.',
    150, 6
  ),
  (
    'beat_the_dealer', 1, '딜러를 이겨라',
    '100코인으로 시작해 딜러 숫자보다 높고 21 이하인 카드 합계를 만들며 8라운드 동안 코인을 불리세요.',
    180, 8
  ),
  (
    'beat_the_dealer', 2, '딜러를 이겨라',
    '딜러 공개 카드를 보고 배팅한 뒤 21에 가까운 패를 만들어 8라운드 동안 코인을 불리세요.',
    180, 8
  )
on conflict (game_id, version) do nothing;

-- This is only a recovery fallback for references made before version
-- snapshots existed. It keeps the foreign key valid; exact historical text
-- cannot be reconstructed when an old migration overwrote the catalog row.
with referenced_versions as (
  select game_id, game_version from public.daily_games
  union
  select game_id, game_version from public.attempts
  union
  select game_id, game_version from public.scores
)
insert into public.game_rule_versions (
  game_id, version, display_name, description, duration_seconds,
  minimum_app_build
)
select
  reference.game_id,
  reference.game_version,
  game.display_name,
  game.description,
  game.duration_seconds,
  game.minimum_app_build
from referenced_versions reference
join public.games game on game.id = reference.game_id
where not exists (
  select 1
  from public.game_rule_versions versioned
  where versioned.game_id = reference.game_id
    and versioned.version = reference.game_version
);

-- Correct the duration snapshot for all known historical versions. The prior
-- migration backfilled by game_id only, which was unsafe after a version roll.
update public.attempts attempt
set game_duration_seconds = versioned.duration_seconds
from public.game_rule_versions versioned
where versioned.game_id = attempt.game_id
  and versioned.version = attempt.game_version;

alter table public.daily_games
  add constraint daily_games_game_version_fk
  foreign key (game_id, game_version)
  references public.game_rule_versions (game_id, version);

alter table public.attempts
  add constraint attempts_game_version_fk
  foreign key (game_id, game_version)
  references public.game_rule_versions (game_id, version);

alter table public.scores
  add constraint scores_game_version_fk
  foreign key (game_id, game_version)
  references public.game_rule_versions (game_id, version);

create or replace function public.sync_game_rule_version()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  existing_version public.game_rule_versions;
begin
  select * into existing_version
  from public.game_rule_versions
  where game_id = new.id and version = new.version
  for update;

  if existing_version is not null and (
    existing_version.display_name is distinct from new.display_name
    or existing_version.description is distinct from new.description
    or existing_version.duration_seconds is distinct from new.duration_seconds
  ) then
    raise exception
      'game version metadata is immutable; increment version before changing rules';
  end if;

  if existing_version is null then
    insert into public.game_rule_versions (
      game_id, version, display_name, description, duration_seconds,
      minimum_app_build
    ) values (
      new.id, new.version, new.display_name, new.description,
      new.duration_seconds, new.minimum_app_build
    );
  else
    update public.game_rule_versions
    set minimum_app_build = new.minimum_app_build
    where game_id = new.id and version = new.version;
  end if;

  return new;
end;
$$;

create trigger game_rule_versions_after_games_write
after insert or update on public.games
for each row execute function public.sync_game_rule_version();

revoke all on function public.sync_game_rule_version() from public;

create or replace function public.snapshot_attempt_game_rules()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  select versioned.duration_seconds
  into new.game_duration_seconds
  from public.game_rule_versions versioned
  where versioned.game_id = new.game_id
    and versioned.version = new.game_version;

  if new.game_duration_seconds is null then
    raise exception 'game version not found';
  end if;
  return new;
end;
$$;

revoke all on function public.snapshot_attempt_game_rules() from public;

create or replace function public.claim_daily_attempt(expected_play_date date)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  device_key text;
  scheduled_game public.daily_games;
  selected_game_id text;
  selected_game_version integer;
  claimed_attempt public.attempts;
  existing_attempt public.attempts;
  is_test boolean := false;
  selected_test_game_id text;
  next_ordinal smallint := 1;
  inserted_claim_count integer := 0;
  request_build_header text :=
    coalesce(current_setting('request.headers', true)::jsonb ->> 'x-app-build', '');
  request_build integer := case
    when request_build_header ~ '^[0-9]+$' then request_build_header::integer
    else 0
  end;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  select p.is_test_account, p.test_game_id
  into is_test, selected_test_game_id
  from public.profiles p
  where p.id = current_user_id;

  scheduled_game := public.ensure_daily_game(play_day);

  if coalesce(is_test, false) and selected_test_game_id is not null then
    select game.id, game.version
    into selected_game_id, selected_game_version
    from public.games game
    where game.id = selected_test_game_id and game.is_active;
  end if;

  if selected_game_id is null then
    select versioned.game_id, versioned.version
    into selected_game_id, selected_game_version
    from public.game_rule_versions versioned
    where versioned.game_id = scheduled_game.game_id
      and versioned.version = scheduled_game.game_version;
  end if;

  if selected_game_id is null then
    raise exception 'game version not found';
  end if;

  if coalesce(is_test, false) then
    select coalesce(max(ordinal), 0) + 1 into next_ordinal
    from public.attempts
    where user_id = current_user_id and play_date = play_day;

    insert into public.attempts (
      user_id, play_date, game_id, game_version, ordinal, grant_type
    ) values (
      current_user_id, play_day, selected_game_id,
      selected_game_version, next_ordinal, 'daily'
    ) returning * into claimed_attempt;
  else
    device_key := public.current_device_hash();
    if device_key is null and request_build >= 7 then
      raise exception 'device registration required';
    end if;

    if device_key is not null then
      perform pg_advisory_xact_lock(
        hashtext(device_key),
        hashtext(play_day::text)
      );

      select * into existing_attempt
      from public.attempts
      where user_id = current_user_id
        and play_date = play_day
        and ordinal = 1;

      insert into public.device_daily_claims (device_hash, play_date)
      values (device_key, play_day)
      on conflict (device_hash, play_date) do nothing;
      get diagnostics inserted_claim_count = row_count;

      if inserted_claim_count = 0 and existing_attempt is null then
        raise exception 'daily attempt already claimed on this device';
      end if;
    end if;

    insert into public.attempts (
      user_id, play_date, game_id, game_version, ordinal, grant_type
    ) values (
      current_user_id, play_day, selected_game_id,
      selected_game_version, 1, 'daily'
    )
    on conflict (user_id, play_date, ordinal)
    do update set user_id = excluded.user_id
    returning * into claimed_attempt;
  end if;

  return claimed_attempt;
end;
$$;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  play_day date := public.current_play_date();
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  device_key text := public.current_device_hash();
  is_test boolean := false;
  selected_test_game_id text;
  ads_enabled boolean := public.rewarded_ads_enabled();
  device_claimed boolean := false;
begin
  scheduled_game := public.ensure_daily_game(play_day);

  select p.is_test_account, p.test_game_id
  into is_test, selected_test_game_id
  from public.profiles p
  where p.id = (select auth.uid());

  if not coalesce(is_test, false) then
    device_claimed := exists (
      select 1
      from public.device_daily_claims claim
      where claim.device_hash = device_key
        and claim.play_date = play_day
    );
  end if;

  if coalesce(is_test, false) and selected_test_game_id is not null then
    select versioned.* into selected_game
    from public.game_rule_versions versioned
    join public.games game
      on game.id = versioned.game_id and game.version = versioned.version
    where game.id = selected_test_game_id and game.is_active;
  end if;

  if selected_game is null then
    select versioned.* into selected_game
    from public.game_rule_versions versioned
    where versioned.game_id = scheduled_game.game_id
      and versioned.version = scheduled_game.game_version;
  end if;

  if selected_game is null then
    raise exception 'game version not found';
  end if;

  return (
    with my_attempts as (
      select *
      from public.attempts
      where user_id = (select auth.uid()) and play_date = play_day
    )
    select jsonb_build_object(
      'play_date', play_day,
      'game', jsonb_build_object(
        'id', selected_game.game_id,
        'version', selected_game.version,
        'display_name', selected_game.display_name,
        'description', selected_game.description,
        'duration_seconds', selected_game.duration_seconds
      ),
      'nickname', (
        select nickname
        from public.profiles
        where id = (select auth.uid())
      ),
      'attempts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'ordinal', ordinal,
        'status', status,
        'grant_type', grant_type,
        'game_id', game_id,
        'game_version', game_version,
        'game_duration_seconds', game_duration_seconds,
        'play_date', play_date
      ) order by ordinal) from my_attempts), '[]'::jsonb),
      'test_mode', coalesce(is_test, false),
      'daily_claimed', device_claimed or exists (select 1 from my_attempts),
      'ad_attempt_available', case
        when coalesce(is_test, false) or not ads_enabled then false
        else exists (
          select 1 from my_attempts where ordinal = 1 and status <> 'issued'
        ) and not exists (
          select 1 from my_attempts where ordinal = 2
        )
      end,
      'result', public.get_my_daily_result(play_day)
    )
  );
end;
$$;

create or replace function public.get_my_play_history(
  history_limit integer default 30
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  history jsonb;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  with real_best as (
    select distinct on (s.play_date, s.game_id, s.game_version, s.user_id)
      s.play_date,
      s.user_id,
      s.game_id,
      s.game_version,
      s.raw_score,
      s.submitted_at
    from public.scores s
    join public.profiles p on p.id = s.user_id
    where not p.is_test_account or s.user_id = current_user_id
    order by
      s.play_date,
      s.game_id,
      s.game_version,
      s.user_id,
      s.raw_score desc,
      s.submitted_at asc
  ), ranked as (
    select
      r.play_date,
      r.user_id,
      r.game_id,
      r.game_version,
      r.raw_score,
      row_number() over (
        partition by r.play_date, r.game_id, r.game_version
        order by r.raw_score desc, r.submitted_at asc, r.user_id
      ) as rank,
      count(*) over (
        partition by r.play_date, r.game_id, r.game_version
      ) as participants
    from real_best r
  ), mine as (
    select
      r.play_date,
      r.game_id,
      r.game_version,
      versioned.display_name,
      r.raw_score,
      r.rank,
      r.participants
    from ranked r
    join public.game_rule_versions versioned
      on versioned.game_id = r.game_id
      and versioned.version = r.game_version
    where r.user_id = current_user_id
    order by r.play_date desc, r.game_id, r.game_version
    limit least(greatest(history_limit, 1), 100)
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'play_date', play_date,
      'game_id', game_id,
      'game_version', game_version,
      'display_name', display_name,
      'score', raw_score,
      'rank', rank,
      'participants', participants
    ) order by play_date desc, game_id, game_version
  ), '[]'::jsonb) into history
  from mine;
  return history;
end;
$$;

create or replace function public.get_unseen_previous_daily_result()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  previous_date date := public.current_play_date() - 1;
  result_available_at timestamptz :=
    ((previous_date + 1) + time '06:10') at time zone 'Asia/Seoul';
  previous_game_id text;
  previous_game_version integer;
  previous_game_name text;
  result jsonb;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if now() < result_available_at then
    return null;
  end if;

  if exists (
    select 1
    from public.profiles p
    where p.id = current_user_id and p.is_test_account
  ) then
    return null;
  end if;

  select s.game_id, s.game_version, versioned.display_name
  into previous_game_id, previous_game_version, previous_game_name
  from public.scores s
  join public.game_rule_versions versioned
    on versioned.game_id = s.game_id
    and versioned.version = s.game_version
  where s.user_id = current_user_id
    and s.play_date = previous_date
  order by s.submitted_at desc
  limit 1;

  if previous_game_id is null or exists (
    select 1
    from public.daily_result_acknowledgements acknowledgement
    where acknowledgement.user_id = current_user_id
      and acknowledgement.play_date = previous_date
      and acknowledgement.game_id = previous_game_id
  ) then
    return null;
  end if;

  result := public.get_my_daily_result(previous_date);
  if result->'score' = 'null'::jsonb then
    return null;
  end if;

  return result || jsonb_build_object(
    'play_date', previous_date,
    'game_id', previous_game_id,
    'game_version', previous_game_version,
    'display_name', previous_game_name
  );
end;
$$;

revoke all on function public.get_today_state() from public;
revoke all on function public.get_my_play_history(integer) from public, anon;
revoke all on function public.get_unseen_previous_daily_result() from public, anon;
grant execute on function public.get_today_state() to authenticated;
grant execute on function public.get_my_play_history(integer) to authenticated;
grant execute on function public.get_unseen_previous_daily_result() to authenticated;

-- Anonymous auth user IDs can change after account deletion or app reinstall.
-- Keep only a one-way device hash and a per-day claim marker so those actions
-- cannot grant another daily attempt. Account-owned profile and game data still
-- cascade away when the auth user is deleted.
create table public.device_installations (
  device_hash text primary key,
  user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint device_installations_hash_format
    check (device_hash ~ '^[0-9a-f]{64}$')
);

create index device_installations_user_id_idx
  on public.device_installations (user_id)
  where user_id is not null;

create table public.device_daily_claims (
  device_hash text not null,
  play_date date not null,
  claimed_at timestamptz not null default now(),
  primary key (device_hash, play_date),
  constraint device_daily_claims_hash_format
    check (device_hash ~ '^[0-9a-f]{64}$')
);

alter table public.device_installations enable row level security;
alter table public.device_daily_claims enable row level security;

revoke all on table public.device_installations from public, anon, authenticated;
revoke all on table public.device_daily_claims from public, anon, authenticated;

create function public.register_device_installation(device_hash text)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  normalized_hash text := lower(btrim(device_hash));
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if normalized_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid device hash';
  end if;

  delete from public.device_daily_claims
  where play_date < public.current_play_date();

  -- An anonymous account belongs to one active installation. Detach any stale
  -- mapping while retaining its anonymous daily-claim ledger.
  update public.device_installations installation
  set user_id = null, last_seen_at = now()
  where installation.user_id = current_user_id
    and installation.device_hash <> normalized_hash;

  insert into public.device_installations (
    device_hash,
    user_id,
    last_seen_at
  ) values (
    normalized_hash,
    current_user_id,
    now()
  )
  on conflict on constraint device_installations_pkey do update
  set user_id = excluded.user_id,
      last_seen_at = excluded.last_seen_at;

  -- Deploying this protection must also cover attempts made earlier today
  -- before the app first registered its installation.
  insert into public.device_daily_claims (device_hash, play_date, claimed_at)
  select normalized_hash, attempt.play_date, min(attempt.issued_at)
  from public.attempts attempt
  where attempt.user_id = current_user_id
    and attempt.play_date = public.current_play_date()
  group by attempt.play_date
  on conflict on constraint device_daily_claims_pkey do nothing;
end;
$$;

create function public.current_device_hash()
returns text
language sql
stable
security definer set search_path = ''
as $$
  select installation.device_hash
  from public.device_installations installation
  where installation.user_id = (select auth.uid())
  order by installation.last_seen_at desc
  limit 1;
$$;

revoke all on function public.register_device_installation(text) from public;
revoke all on function public.current_device_hash() from public;
grant execute on function public.register_device_installation(text)
  to authenticated;

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
  selected_game public.games;
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
    select * into selected_game
    from public.games
    where id = selected_test_game_id and is_active;
  end if;

  if selected_game is null then
    select * into selected_game
    from public.games
    where id = scheduled_game.game_id
      and version = scheduled_game.game_version;
  end if;

  if coalesce(is_test, false) then
    select coalesce(max(ordinal), 0) + 1 into next_ordinal
    from public.attempts
    where user_id = current_user_id and play_date = play_day;

    insert into public.attempts (
      user_id, play_date, game_id, game_version, ordinal, grant_type
    ) values (
      current_user_id, play_day, selected_game.id,
      selected_game.version, next_ordinal, 'daily'
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
      current_user_id, play_day, selected_game.id,
      selected_game.version, 1, 'daily'
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
  selected_game public.games;
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
    select * into selected_game
    from public.games
    where id = selected_test_game_id and is_active;
  end if;

  if selected_game is null then
    select * into selected_game
    from public.games
    where id = scheduled_game.game_id
      and version = scheduled_game.game_version;
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
        'id', selected_game.id,
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
        'game_id', game_id
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

revoke all on function public.claim_daily_attempt(date) from public;
revoke all on function public.get_today_state() from public;
grant execute on function public.claim_daily_attempt(date) to authenticated;
grant execute on function public.get_today_state() to authenticated;

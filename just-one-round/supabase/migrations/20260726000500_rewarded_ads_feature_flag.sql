create table public.app_runtime_config (
  id boolean primary key default true,
  rewarded_ads_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint app_runtime_config_singleton check (id)
);

insert into public.app_runtime_config (id, rewarded_ads_enabled)
values (true, false);

alter table public.app_runtime_config enable row level security;
revoke all on table public.app_runtime_config from public;

create function public.rewarded_ads_enabled()
returns boolean
language sql
stable
security definer set search_path = ''
as $$
  select coalesce(
    (
      select config.rewarded_ads_enabled
      from public.app_runtime_config config
      where config.id
    ),
    false
  );
$$;

revoke all on function public.rewarded_ads_enabled() from public;

create or replace function public.prepare_rewarded_ad()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  first_attempt public.attempts;
  active_grant public.rewarded_ad_grants;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if not public.rewarded_ads_enabled() then
    raise exception 'rewarded ads disabled';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(seoul_date::text)
  );

  select * into first_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = seoul_date
    and ordinal = 1;

  if first_attempt is null or first_attempt.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;

  if exists (
    select 1 from public.attempts
    where user_id = current_user_id
      and play_date = seoul_date
      and ordinal = 2
  ) then
    raise exception 'rewarded attempt already claimed';
  end if;

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = seoul_date
    and status in ('prepared', 'verified')
    and expires_at <= now();

  select * into active_grant
  from public.rewarded_ad_grants
  where user_id = current_user_id
    and play_date = seoul_date
    and status in ('prepared', 'verified')
    and expires_at > now()
  order by prepared_at desc
  limit 1
  for update;

  if active_grant is null then
    insert into public.rewarded_ad_grants (
      user_id,
      play_date,
      expires_at
    ) values (
      current_user_id,
      seoul_date,
      (seoul_date + 1)::timestamp at time zone 'Asia/Seoul'
    )
    returning * into active_grant;
  end if;

  return jsonb_build_object(
    'id', active_grant.id,
    'user_id', active_grant.user_id,
    'status', active_grant.status,
    'expires_at', active_grant.expires_at
  );
end;
$$;

revoke all on function public.prepare_rewarded_ad() from public;
grant execute on function public.prepare_rewarded_ad() to authenticated;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  scheduled_game public.daily_games;
  selected_game public.games;
  is_test boolean := false;
  selected_test_game_id text;
  ads_enabled boolean := public.rewarded_ads_enabled();
begin
  scheduled_game := public.ensure_daily_game(seoul_date);

  select p.is_test_account, p.test_game_id
  into is_test, selected_test_game_id
  from public.profiles p
  where p.id = (select auth.uid());

  if coalesce(is_test, false) and selected_test_game_id is not null then
    select * into selected_game
    from public.games
    where id = selected_test_game_id and is_active;
  end if;

  if selected_game is null then
    select * into selected_game
    from public.games
    where id = scheduled_game.game_id and version = scheduled_game.game_version;
  end if;

  return (
    with my_attempts as (
      select *
      from public.attempts
      where user_id = (select auth.uid()) and play_date = seoul_date
    ), my_profile as (
      select nickname, birth_year, birth_month, gender
      from public.profiles
      where id = (select auth.uid())
    )
    select jsonb_build_object(
      'play_date', seoul_date,
      'game', jsonb_build_object(
        'id', selected_game.id,
        'version', selected_game.version,
        'display_name', selected_game.display_name,
        'description', selected_game.description,
        'duration_seconds', selected_game.duration_seconds
      ),
      'profile', (select jsonb_build_object(
        'nickname', nickname,
        'birth_year', birth_year,
        'birth_month', birth_month,
        'gender', gender
      ) from my_profile),
      'attempts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'ordinal', ordinal,
        'status', status,
        'grant_type', grant_type,
        'game_id', game_id
      ) order by ordinal) from my_attempts), '[]'::jsonb),
      'test_mode', coalesce(is_test, false),
      'ad_attempt_available', case
        when coalesce(is_test, false) or not ads_enabled then false
        else exists (
          select 1 from my_attempts where ordinal = 1 and status <> 'issued'
        ) and not exists (
          select 1 from my_attempts where ordinal = 2
        )
      end,
      'result', public.get_my_daily_result(seoul_date)
    )
  );
end;
$$;

revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

comment on table public.app_runtime_config is
  'Server-controlled production feature flags. Update the singleton row only.';
comment on column public.app_runtime_config.rewarded_ads_enabled is
  'Keep false until the app is store-linked and approved for AdMob serving.';

-- Keep server-selected games compatible with every client that is still
-- allowed to play. Raise minimum_supported_build only after the corresponding
-- App Store / Play Store release is available.

alter table public.app_runtime_config
add column minimum_supported_build integer not null default 1
  check (minimum_supported_build > 0),
add column ios_store_url text,
add column android_store_url text;

update public.app_runtime_config
set
  ios_store_url =
    'https://apps.apple.com/kr/search?term=%EB%94%B1%ED%95%9C%ED%8C%90%EB%A7%8C',
  android_store_url =
    'https://play.google.com/store/apps/details?id=com.justoneround.app'
where id;

alter table public.games
add column minimum_app_build integer not null default 1
  check (minimum_app_build > 0);

comment on column public.app_runtime_config.minimum_supported_build is
  'Clients below this build are blocked. Increase only after the store release is live.';
comment on column public.games.minimum_app_build is
  'First app build containing this game. The scheduler excludes games above the global minimum supported build.';

create function public.request_app_build()
returns integer
language plpgsql
stable
security definer set search_path = ''
as $$
declare
  headers_text text := current_setting('request.headers', true);
  headers jsonb;
  raw_build text;
begin
  if headers_text is null or headers_text = '' then
    return null;
  end if;

  headers := headers_text::jsonb;
  raw_build := headers ->> 'x-app-build';
  if raw_build ~ '^[0-9]+$' then
    return raw_build::integer;
  end if;

  -- Builds released before the header existed are build 1.
  return 1;
end;
$$;

create function public.assert_supported_client()
returns void
language plpgsql
stable
security definer set search_path = ''
as $$
declare
  client_build integer := public.request_app_build();
  minimum_build integer;
begin
  -- SQL migrations, scheduled work, and other non-HTTP calls have no request
  -- headers and must not be treated as legacy app clients.
  if client_build is null then
    return;
  end if;

  select config.minimum_supported_build
  into minimum_build
  from public.app_runtime_config config
  where config.id;

  minimum_build := coalesce(minimum_build, 1);
  if client_build < minimum_build then
    raise exception using
      message = 'app update required',
      detail = format(
        'client_build=%s minimum_supported_build=%s',
        client_build,
        minimum_build
      ),
      hint = 'Install the latest store version to continue.';
  end if;
end;
$$;

create function public.get_client_compatibility()
returns jsonb
language plpgsql
stable
security definer set search_path = ''
as $$
declare
  headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), ''),
    '{}'
  )::jsonb;
  client_build integer := coalesce(public.request_app_build(), 1);
  client_platform text := lower(coalesce(headers ->> 'x-app-platform', 'unknown'));
  config public.app_runtime_config;
begin
  select * into config
  from public.app_runtime_config runtime_config
  where runtime_config.id;

  return jsonb_build_object(
    'current_build', client_build,
    'minimum_supported_build', coalesce(config.minimum_supported_build, 1),
    'update_required',
      client_build < coalesce(config.minimum_supported_build, 1),
    'store_url', case client_platform
      when 'ios' then config.ios_store_url
      when 'android' then config.android_store_url
      else coalesce(config.ios_store_url, config.android_store_url)
    end
  );
end;
$$;

revoke all on function public.request_app_build() from public;
revoke all on function public.assert_supported_client() from public;
revoke all on function public.get_client_compatibility() from public;
grant execute on function public.get_client_compatibility()
  to anon, authenticated;

-- This function sits on every daily-game and attempt path. Checking here
-- protects legacy clients too: they send no x-app-build header and are treated
-- as build 1.
create or replace function public.current_play_date(
  at_time timestamptz default now()
)
returns date
language plpgsql
stable
security definer set search_path = ''
as $$
begin
  perform public.assert_supported_client();
  return (
    (at_time at time zone 'Asia/Seoul') - interval '6 hours'
  )::date;
end;
$$;

create or replace function public.ensure_daily_game(
  target_date date default public.current_play_date()
)
returns public.daily_games
language plpgsql
security definer set search_path = ''
as $$
declare
  existing_schedule public.daily_games;
  selected_game public.games;
  eligible_game_count integer;
  minimum_build integer;
begin
  select * into existing_schedule
  from public.daily_games
  where play_date = target_date;

  if existing_schedule is not null then
    return existing_schedule;
  end if;

  select coalesce(config.minimum_supported_build, 1)
  into minimum_build
  from public.app_runtime_config config
  where config.id;
  minimum_build := coalesce(minimum_build, 1);

  select count(*) into eligible_game_count
  from public.games
  where is_active
    and minimum_app_build <= minimum_build;

  if eligible_game_count = 0 then
    raise exception 'no compatible active games available';
  end if;

  select * into selected_game
  from public.games
  where is_active
    and minimum_app_build <= minimum_build
  order by id
  offset mod(target_date - date '2026-01-01', eligible_game_count)
  limit 1;

  insert into public.daily_games (play_date, game_id, game_version)
  values (target_date, selected_game.id, selected_game.version)
  on conflict (play_date) do nothing
  returning * into existing_schedule;

  if existing_schedule is null then
    select * into existing_schedule
    from public.daily_games
    where play_date = target_date;
  end if;

  return existing_schedule;
end;
$$;

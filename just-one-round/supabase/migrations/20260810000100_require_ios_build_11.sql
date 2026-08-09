-- iOS 1.0.6 (build 11) is publicly installable, while Android build 11 is
-- awaiting review on the closed-test track. Keep the shared floor at build 10
-- and apply a platform-specific iOS floor so Android testers are not blocked
-- before the closed-test update is installable.

alter table public.app_runtime_config
add column ios_minimum_supported_build integer
  check (ios_minimum_supported_build > 0),
add column android_minimum_supported_build integer
  check (android_minimum_supported_build > 0);

update public.app_runtime_config
set
  ios_minimum_supported_build = greatest(minimum_supported_build, 11),
  android_minimum_supported_build = minimum_supported_build
where id;

comment on column public.app_runtime_config.ios_minimum_supported_build is
  'Minimum supported iOS build. Falls back to minimum_supported_build when null.';
comment on column public.app_runtime_config.android_minimum_supported_build is
  'Minimum supported Android build. Falls back to minimum_supported_build when null.';

create or replace function public.assert_supported_client()
returns void
language plpgsql
stable
security definer set search_path = ''
as $$
declare
  headers_text text := current_setting('request.headers', true);
  headers jsonb := coalesce(nullif(headers_text, ''), '{}')::jsonb;
  client_build integer := public.request_app_build();
  client_platform text := lower(coalesce(headers ->> 'x-app-platform', 'unknown'));
  config public.app_runtime_config;
  minimum_build integer;
begin
  -- SQL migrations, scheduled work, and other non-HTTP calls have no request
  -- headers and must not be treated as legacy app clients.
  if client_build is null then
    return;
  end if;

  select * into config
  from public.app_runtime_config runtime_config
  where runtime_config.id;

  minimum_build := case client_platform
    when 'ios' then coalesce(
      config.ios_minimum_supported_build,
      config.minimum_supported_build,
      1
    )
    when 'android' then coalesce(
      config.android_minimum_supported_build,
      config.minimum_supported_build,
      1
    )
    else coalesce(config.minimum_supported_build, 1)
  end;

  if client_build < minimum_build then
    raise exception using
      message = 'app update required',
      detail = format(
        'client_platform=%s client_build=%s minimum_supported_build=%s',
        client_platform,
        client_build,
        minimum_build
      ),
      hint = 'Install the latest store version to continue.';
  end if;
end;
$$;

create or replace function public.get_client_compatibility()
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
  minimum_build integer;
begin
  select * into config
  from public.app_runtime_config runtime_config
  where runtime_config.id;

  minimum_build := case client_platform
    when 'ios' then coalesce(
      config.ios_minimum_supported_build,
      config.minimum_supported_build,
      1
    )
    when 'android' then coalesce(
      config.android_minimum_supported_build,
      config.minimum_supported_build,
      1
    )
    else coalesce(config.minimum_supported_build, 1)
  end;

  return jsonb_build_object(
    'current_build', client_build,
    'minimum_supported_build', minimum_build,
    'update_required', client_build < minimum_build,
    'store_url', case client_platform
      when 'ios' then config.ios_store_url
      when 'android' then config.android_store_url
      else coalesce(config.ios_store_url, config.android_store_url)
    end
  );
end;
$$;

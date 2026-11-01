-- Keep Android Alpha-only builds playable until the matching public Play
-- release is actually available. The array is intentionally empty here:
-- activation belongs to the guarded deploy script below, after build 30 is
-- confirmed public. The existing Android floor remains unchanged at 22.

alter table public.app_runtime_config
  add column android_production_only_builds integer[] not null default '{}'::integer[];

comment on column public.app_runtime_config.android_production_only_builds is
  'Android build numbers distributed only through Alpha. Once the corresponding public build is live, these builds require the production release while the normal Android floor remains unchanged.';

-- Preserve the current minimum-build, store URL, and update-observation
-- contract. A local checkout can have the reward migration omitted from its
-- applied history, so call its observation helper dynamically when present;
-- production has the helper from 20260915000100 and therefore keeps the same
-- existing observation and update-reward behavior.
create or replace function public.get_client_compatibility()
returns jsonb
language plpgsql
volatile
security definer set search_path = ''
as $$
declare
  headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), ''),
    '{}'
  )::jsonb;
  raw_client_build integer := public.request_app_build();
  client_build integer := coalesce(raw_client_build, 1);
  client_platform text := lower(coalesce(headers ->> 'x-app-platform', 'unknown'));
  config public.app_runtime_config;
  minimum_build integer;
  production_only_build boolean;
begin
  if raw_client_build is not null and (select auth.uid()) is not null
    and to_regprocedure('public.observe_client_build(integer,text)') is not null then
    execute 'select public.observe_client_build($1, $2)'
      using raw_client_build, client_platform;
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

  production_only_build := client_platform = 'android'
    and coalesce(config.android_production_only_builds, '{}'::integer[])
      @> array[client_build]::integer[];

  return jsonb_build_object(
    'current_build', client_build,
    'minimum_supported_build', minimum_build,
    'update_required', client_build < minimum_build or production_only_build,
    'store_url', case client_platform
      when 'ios' then config.ios_store_url
      when 'android' then config.android_store_url
      else coalesce(config.ios_store_url, config.android_store_url)
    end,
    'reason', case
      when production_only_build then 'production_release_required'
      else null
    end
  );
end;
$$;

-- Keep headerless SQL and internal calls exempt from the client gate, preserve
-- the existing platform-specific floor, and add only the Android
-- production-release membership check.
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
  production_only_build boolean;
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

  production_only_build := client_platform = 'android'
    and coalesce(config.android_production_only_builds, '{}'::integer[])
      @> array[client_build]::integer[];

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

  if production_only_build then
    raise exception using
      message = 'app update required',
      detail = format(
        'client_platform=%s client_build=%s reason=production_release_required',
        client_platform,
        client_build
      ),
      hint = 'Install the latest public Play release to continue.';
  end if;
end;
$$;

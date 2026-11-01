-- Guarded activation for the Android Alpha build 29 -> public build 30
-- transition.
--
-- Run only after Google Play publicly serves build 30. The explicit session
-- setting makes an accidental pre-release activation fail closed:
--
--   PGOPTIONS='-c app.android_production_build_30_public=true' \
--     psql ... --file deploy/android_alpha29_to_production30.sql
--
-- This changes only the membership array. The Android floor stays at 22,
-- iOS stays at 26, and the shared floor stays at 22. Builds 22 and 28 remain
-- supported; only the Alpha-only build 29 is required to move to public 30.
-- It deliberately does not rewrite games.minimum_app_build or daily_games;
-- verify any game-specific release floor separately and preserve snapshots.

begin;

select pg_advisory_xact_lock(hashtext('public.android_alpha29_to_production30'));

do $$
declare
  runtime_config public.app_runtime_config;
begin
  if current_setting('app.android_production_build_30_public', true)
      is distinct from 'true' then
    raise exception
      'refusing activation: confirm that Android build 30 is public in Google Play';
  end if;

  select *
  into runtime_config
  from public.app_runtime_config
  where id
  for update;

  if runtime_config.id is null then
    raise exception 'app runtime config singleton is missing';
  end if;

  if runtime_config.minimum_supported_build is distinct from 22
    or runtime_config.ios_minimum_supported_build is distinct from 26
    or runtime_config.android_minimum_supported_build is distinct from 22 then
    raise exception
      'refusing activation: compatibility floors changed (expected shared=22, iOS=26, Android=22)';
  end if;

  if coalesce(runtime_config.android_production_only_builds, '{}'::integer[])
      is distinct from '{}'::integer[] then
    raise exception
      'refusing activation: Android production-only membership is already populated';
  end if;
end;
$$;

update public.app_runtime_config
set android_production_only_builds = array[29]::integer[],
    updated_at = now()
  where id
  and minimum_supported_build = 22
  and ios_minimum_supported_build = 26
  and android_minimum_supported_build = 22
  and coalesce(android_production_only_builds, '{}'::integer[])
      = '{}'::integer[];

do $$
begin
  if not exists (
    select 1
    from public.app_runtime_config
    where id
      and android_production_only_builds = array[29]::integer[]
  ) then
    raise exception 'activation did not write Android build 29 membership';
  end if;
end;
$$;

commit;

-- Rollback (run as a separate, reviewed operation only when build 29 should
-- become playable again):
--
-- begin;
-- select pg_advisory_xact_lock(hashtext('public.android_alpha29_to_production30'));
-- update public.app_runtime_config
-- set android_production_only_builds = '{}'::integer[], updated_at = now()
-- where id and android_production_only_builds = array[29]::integer[];
-- commit;

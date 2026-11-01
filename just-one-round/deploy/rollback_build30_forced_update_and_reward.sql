-- Restore the exact pre-build-30 compatibility and reward configuration.
--
-- Run only as a reviewed rollback while the build-30 campaign is active.
-- Reward claims are history: this script never deletes claims and never
-- subtracts tickets already granted to players.

begin;

select pg_advisory_xact_lock(hashtext('public.build30_forced_update_and_reward'));

do $$
declare
  runtime_config public.app_runtime_config;
begin
  select *
  into runtime_config
  from public.app_runtime_config
  where id
  for update;

  if runtime_config.id is null then
    raise exception 'app runtime config singleton is missing';
  end if;

  if runtime_config.minimum_supported_build is distinct from 30
    or runtime_config.ios_minimum_supported_build is distinct from 30
    or runtime_config.android_minimum_supported_build is distinct from 30
    or runtime_config.android_production_only_builds is distinct from array[29]::integer[]
    or runtime_config.update_reward_enabled is distinct from true
    or runtime_config.update_reward_campaign is distinct from 'build-30-update-reward'
    or runtime_config.update_reward_target_build is distinct from 30
    or runtime_config.update_reward_started_at is null
    or runtime_config.update_reward_message is distinct from
       '업데이트 감사 선물로 도전권 1장을 드려요.' then
    raise exception
      'refusing rollback: build-30 forced-update campaign is not the active config';
  end if;

  if runtime_config.ios_store_url is distinct from
       'https://apps.apple.com/app/id6794861323'
    or runtime_config.android_store_url is distinct from
       'https://play.google.com/store/apps/details?id=com.justoneround.app' then
    raise exception 'refusing rollback: official store URLs changed';
  end if;
end;
$$;

update public.app_runtime_config
set
  minimum_supported_build = 22,
  ios_minimum_supported_build = 26,
  android_minimum_supported_build = 22,
  android_production_only_builds = '{}'::integer[],
  update_reward_enabled = true,
  update_reward_campaign = 'ios-build-26-update-reward',
  update_reward_target_build = 26,
  update_reward_started_at = '2026-10-02T01:03:24.179087Z'::timestamptz,
  update_reward_message = '업데이트 감사 선물로 도전권 1장을 드려요.',
  updated_at = now()
where id;

do $$
declare
  runtime_config public.app_runtime_config;
begin
  select *
  into runtime_config
  from public.app_runtime_config
  where id;

  if runtime_config.minimum_supported_build is distinct from 22
    or runtime_config.ios_minimum_supported_build is distinct from 26
    or runtime_config.android_minimum_supported_build is distinct from 22
    or runtime_config.android_production_only_builds is distinct from '{}'::integer[]
    or runtime_config.update_reward_enabled is distinct from true
    or runtime_config.update_reward_campaign is distinct from 'ios-build-26-update-reward'
    or runtime_config.update_reward_target_build is distinct from 26
    or runtime_config.update_reward_started_at is distinct from
       '2026-10-02T01:03:24.179087Z'::timestamptz
    or runtime_config.update_reward_message is distinct from
       '업데이트 감사 선물로 도전권 1장을 드려요.' then
    raise exception 'build 30 rollback did not restore the exact prior config';
  end if;
end;
$$;

commit;

-- Promote the approved iOS/Android build 30 release and start the matching
-- one-time challenge-ticket reward campaign.
--
-- This is an operator deployment, not an ordinary migration. Run it only
-- after both stores publicly serve build 30 and set both explicit session
-- confirmations in the same psql session:
--
--   PGOPTIONS='-c app.ios_production_build_30_public=true \
--     -c app.android_production_build_30_public=true' \
--   psql ... --file deploy/build30_forced_update_and_reward.sql
--
-- The transaction changes one singleton config row. It never grants tickets
-- directly and never deletes or rewrites reward claims, profiles, scores,
-- games, attempts, or schedules. Existing clients must claim the ticket
-- through public.claim_app_update_reward() after updating.

begin;

select pg_advisory_xact_lock(hashtext('public.build30_forced_update_and_reward'));

do $$
declare
  runtime_config public.app_runtime_config;
  old_started_at timestamptz := '2026-10-02T01:03:24.179087Z'::timestamptz;
  is_exact_old_state boolean;
  is_exact_desired_state boolean;
begin
  if current_setting('app.ios_production_build_30_public', true)
      is distinct from 'true'
    or current_setting('app.android_production_build_30_public', true)
      is distinct from 'true' then
    raise exception
      'refusing build 30 activation: confirm public iOS and Android build 30 in the session';
  end if;

  select *
  into runtime_config
  from public.app_runtime_config
  where id
  for update;

  if runtime_config.id is null then
    raise exception 'app runtime config singleton is missing';
  end if;

  -- Keep store links pinned to the already verified official products. A
  -- typo here would turn a forced update into a dead-end for old clients.
  if runtime_config.ios_store_url is distinct from
       'https://apps.apple.com/app/id6794861323'
    or runtime_config.android_store_url is distinct from
       'https://play.google.com/store/apps/details?id=com.justoneround.app' then
    raise exception
      'refusing build 30 activation: official store URLs changed';
  end if;

  is_exact_old_state :=
    runtime_config.minimum_supported_build = 22
    and runtime_config.ios_minimum_supported_build = 26
    and runtime_config.android_minimum_supported_build = 22
    and coalesce(runtime_config.android_production_only_builds, '{}'::integer[])
      = '{}'::integer[]
    and runtime_config.update_reward_enabled
    and runtime_config.update_reward_campaign = 'ios-build-26-update-reward'
    and runtime_config.update_reward_target_build = 26
    and runtime_config.update_reward_started_at = old_started_at
    and runtime_config.update_reward_message =
      '업데이트 감사 선물로 도전권 1장을 드려요.';

  -- A retry after a partially observed or successfully committed deployment is
  -- safe. The timestamp only needs to exist; the update below preserves it.
  is_exact_desired_state :=
    runtime_config.minimum_supported_build = 30
    and runtime_config.ios_minimum_supported_build = 30
    and runtime_config.android_minimum_supported_build = 30
    and coalesce(runtime_config.android_production_only_builds, '{}'::integer[])
      = array[29]::integer[]
    and runtime_config.update_reward_enabled
    and runtime_config.update_reward_campaign = 'build-30-update-reward'
    and runtime_config.update_reward_target_build = 30
    and runtime_config.update_reward_started_at is not null
    and runtime_config.update_reward_message =
      '업데이트 감사 선물로 도전권 1장을 드려요.';

  -- PL/pgSQL treats a NULL IF condition as false. Coalesce the state checks
  -- so a partially populated or nullable config can never pass closed-world
  -- validation by evaluating to NULL.
  if not coalesce(is_exact_old_state, false)
    and not coalesce(is_exact_desired_state, false) then
    raise exception
      'refusing build 30 activation: runtime config is neither the expected build 26 state nor the desired build 30 state';
  end if;
end;
$$;

update public.app_runtime_config
set
  minimum_supported_build = 30,
  ios_minimum_supported_build = 30,
  android_minimum_supported_build = 30,
  android_production_only_builds = array[29]::integer[],
  update_reward_enabled = true,
  update_reward_campaign = 'build-30-update-reward',
  update_reward_target_build = 30,
  update_reward_started_at = case
    when update_reward_campaign is distinct from 'build-30-update-reward'
      or update_reward_target_build is distinct from 30
      or not update_reward_enabled
      or update_reward_started_at is null
      then now()
    else update_reward_started_at
  end,
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

  if runtime_config.minimum_supported_build is distinct from 30
    or runtime_config.ios_minimum_supported_build is distinct from 30
    or runtime_config.android_minimum_supported_build is distinct from 30
    or runtime_config.android_production_only_builds is distinct from array[29]::integer[]
    or runtime_config.update_reward_enabled is distinct from true
    or runtime_config.update_reward_campaign is distinct from 'build-30-update-reward'
    or runtime_config.update_reward_target_build is distinct from 30
    or runtime_config.update_reward_started_at is null
    or runtime_config.update_reward_message is distinct from
       '업데이트 감사 선물로 도전권 1장을 드려요.'
    or runtime_config.ios_store_url is distinct from
       'https://apps.apple.com/app/id6794861323'
    or runtime_config.android_store_url is distinct from
       'https://play.google.com/store/apps/details?id=com.justoneround.app' then
    raise exception 'build 30 activation did not produce the expected config';
  end if;
end;
$$;

commit;

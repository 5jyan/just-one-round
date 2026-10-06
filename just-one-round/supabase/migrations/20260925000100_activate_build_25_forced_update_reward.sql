-- Build 25 (1.0.17) is approved on both stores. Require every older client
-- to update, and grant existing accounts one challenge ticket after upgrading.

update public.app_runtime_config
set
  minimum_supported_build = greatest(minimum_supported_build, 25),
  ios_minimum_supported_build = greatest(
    coalesce(ios_minimum_supported_build, minimum_supported_build),
    25
  ),
  android_minimum_supported_build = greatest(
    coalesce(android_minimum_supported_build, minimum_supported_build),
    25
  ),
  update_reward_started_at = case
    when update_reward_campaign is distinct from 'build-25-update-reward'
      or update_reward_target_build is distinct from 25
      or not update_reward_enabled
      then now()
    else coalesce(update_reward_started_at, now())
  end,
  update_reward_enabled = true,
  update_reward_campaign = 'build-25-update-reward',
  update_reward_target_build = 25,
  update_reward_message = '업데이트 감사 선물로 도전권 1장을 드려요.',
  updated_at = now()
where id;

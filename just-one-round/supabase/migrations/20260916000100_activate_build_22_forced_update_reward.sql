-- The 1.0.15 (build 22) store release is live on both platforms.
-- Raise the compatibility floor and start the one-time update reward campaign.

update public.app_runtime_config
set
  minimum_supported_build = greatest(minimum_supported_build, 22),
  ios_minimum_supported_build = greatest(
    coalesce(ios_minimum_supported_build, minimum_supported_build),
    22
  ),
  android_minimum_supported_build = greatest(
    coalesce(android_minimum_supported_build, minimum_supported_build),
    22
  ),
  updated_at = now()
where id;

select public.set_app_update_reward_campaign(
  true,
  'build-22-update-reward',
  22,
  '업데이트 감사 보상으로 도전권 1장을 드려요.'
);

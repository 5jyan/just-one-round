-- Google Play closed-test Alpha still serves build 22 while newer Android
-- builds await review. Keep iOS and the shared floor at build 25, but allow
-- Android testers to use the latest build that is actually installable.

update public.app_runtime_config
set android_minimum_supported_build = 22,
    updated_at = now()
where id;

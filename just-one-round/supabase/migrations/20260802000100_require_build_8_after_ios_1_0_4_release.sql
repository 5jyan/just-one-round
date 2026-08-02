-- iOS 1.0.4 (build 9) is live on the App Store. Requiring build 8
-- blocks the previous iOS build 7 while keeping Android build 8 supported.
update public.app_runtime_config
set minimum_supported_build = greatest(minimum_supported_build, 8)
where id;

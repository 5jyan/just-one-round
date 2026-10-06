-- iOS 1.0.11 (build 18) is publicly available in the App Store.
-- Apply the iOS-only floor after that release; keep the Android and shared
-- minimum_supported_build floors at build 15 because Android is not public yet.

update public.app_runtime_config
set ios_minimum_supported_build = greatest(
  coalesce(ios_minimum_supported_build, minimum_supported_build, 1),
  18
)
where id;

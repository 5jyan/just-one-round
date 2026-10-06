-- iOS and Android 1.0.9+15 are available in their release tracks.
-- Require build 15 on both platforms before enabling the games introduced by
-- this release in the shared daily rotation.

update public.app_runtime_config
set
  minimum_supported_build = greatest(minimum_supported_build, 15),
  ios_minimum_supported_build = greatest(
    coalesce(ios_minimum_supported_build, minimum_supported_build),
    15
  ),
  android_minimum_supported_build = greatest(
    coalesce(android_minimum_supported_build, minimum_supported_build),
    15
  )
where id;

update public.games
set is_active = true
where id in ('bathhouse_sort', 'lily_frog', 'net_boat');

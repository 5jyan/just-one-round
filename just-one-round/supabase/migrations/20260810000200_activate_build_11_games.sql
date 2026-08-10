-- Build 11 is the required client for both platforms before introducing the
-- two games shipped in 1.0.6 to the shared daily rotation.

update public.app_runtime_config
set
  minimum_supported_build = greatest(minimum_supported_build, 11),
  ios_minimum_supported_build = greatest(
    coalesce(ios_minimum_supported_build, minimum_supported_build),
    11
  ),
  android_minimum_supported_build = greatest(
    coalesce(android_minimum_supported_build, minimum_supported_build),
    11
  )
where id;

update public.games
set is_active = true
where id in ('ramen_timer', 'ten_pitch_slugger');

begin;

select plan(8);

select is(
  (select minimum_supported_build from public.app_runtime_config where id),
  25,
  'the shared minimum supported build is 25'
);
select is(
  (select ios_minimum_supported_build from public.app_runtime_config where id),
  25,
  'iOS requires build 25'
);
select is(
  (select android_minimum_supported_build from public.app_runtime_config where id),
  22,
  'Android allows the latest installable Alpha build'
);
select is(
  (select update_reward_campaign from public.app_runtime_config where id),
  'build-25-update-reward',
  'the build 25 reward campaign is active'
);
select is(
  (select update_reward_target_build from public.app_runtime_config where id),
  25,
  'the reward is reserved for build 25 and newer'
);

select set_config(
  'request.headers',
  '{"x-app-build":"24","x-app-platform":"ios"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  true,
  'iOS build 24 is forced to update'
);

select set_config(
  'request.headers',
  '{"x-app-build":"21","x-app-platform":"android"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  true,
  'Android build 21 is forced to update'
);

select set_config(
  'request.headers',
  '{"x-app-build":"22","x-app-platform":"android"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  false,
  'Android build 22 is supported'
);

select * from finish();
rollback;

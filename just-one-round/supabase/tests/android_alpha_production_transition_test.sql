begin;

select plan(24);

-- Test the transition with the current production floors that the guarded activation
-- script requires, then leave the local database untouched by the rollback.
update public.app_runtime_config
set minimum_supported_build = 22,
    ios_minimum_supported_build = 26,
    android_minimum_supported_build = 22,
    android_production_only_builds = '{}'::integer[]
where id;

select is(
  (select android_production_only_builds
   from public.app_runtime_config where id),
  '{}'::integer[],
  'the migration starts with no production-only Android builds'
);

select set_config(
  'request.headers',
  '{"x-app-build":"29","x-app-platform":"android"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  false,
  'inactive Alpha build 29 remains allowed'
);
select is(
  public.get_client_compatibility()->>'reason',
  null,
  'inactive Alpha build has no transition reason'
);

update public.app_runtime_config
set android_production_only_builds = array[29]::integer[]
where id;

select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  true,
  'active Alpha build 29 is blocked'
);
select is(
  (public.get_client_compatibility()->>'minimum_supported_build')::integer,
  22,
  'the special gate does not raise the Android floor'
);
select is(
  public.get_client_compatibility()->>'reason',
  'production_release_required',
  'the special gate exposes only the production transition reason'
);
select is(
  public.get_client_compatibility()->>'store_url',
  (select android_store_url from public.app_runtime_config where id),
  'the special gate keeps the normal Play store URL'
);

select set_config(
  'request.headers',
  '{"x-app-build":"22","x-app-platform":"android"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  false,
  'Android floor build 22 remains allowed'
);
select lives_ok(
  $$ select public.assert_supported_client() $$,
  'the server assertion allows Android floor build 22'
);

select set_config(
  'request.headers',
  '{"x-app-build":"28","x-app-platform":"android"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  false,
  'Android build 28 remains allowed'
);
select lives_ok(
  $$ select public.assert_supported_client() $$,
  'the server assertion allows Android build 28'
);

select set_config(
  'request.headers',
  '{"x-app-build":"30","x-app-platform":"android"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  false,
  'public Android build 30 is allowed'
);
select lives_ok(
  $$ select public.assert_supported_client() $$,
  'the server assertion allows public Android build 30'
);

select set_config(
  'request.headers',
  '{"x-app-build":"29","x-app-platform":"ios"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  false,
  'iOS build 29 is unaffected by Android membership'
);
select is(
  public.get_client_compatibility()->>'reason',
  null,
  'iOS has no Android transition reason'
);

select set_config(
  'request.headers',
  '{"x-app-build":"21","x-app-platform":"android"}',
  true
);
select throws_ok(
  $$ select public.assert_supported_client() $$,
  'P0001',
  'app update required',
  'the existing Android floor still blocks older clients'
);

select set_config(
  'request.headers',
  '{"x-app-build":"29","x-app-platform":"android"}',
  true
);
select throws_ok(
  $$ select public.assert_supported_client() $$,
  'P0001',
  'app update required',
  'the server assertion blocks Alpha build 29'
);

select set_config('request.headers', '', true);
select lives_ok(
  $$ select public.assert_supported_client() $$,
  'headerless SQL and internal calls bypass client compatibility checks'
);

select set_config(
  'request.headers',
  '{"x-app-build":"29"}',
  true
);
select lives_ok(
  $$ select public.assert_supported_client() $$,
  'a build without an Android platform header keeps the existing unknown-platform behavior'
);

select is(
  (select minimum_supported_build from public.app_runtime_config where id),
  22,
  'the shared compatibility floor is unchanged'
);
select is(
  (select ios_minimum_supported_build from public.app_runtime_config where id),
  26,
  'the iOS compatibility floor is unchanged'
);
select is(
  (select android_minimum_supported_build from public.app_runtime_config where id),
  22,
  'the Android compatibility floor is unchanged'
);

select ok(
  to_regprocedure('public.observe_client_build(integer,text)') is null
    or pg_get_functiondef(
      'public.get_client_compatibility()'::regprocedure
    ) like '%observe_client_build%',
  'the existing build-observation and update-reward path remains wired'
);
select ok(
  pg_get_functiondef('public.get_client_compatibility()'::regprocedure)
    like '%android_store_url%',
  'the existing store configuration remains part of compatibility responses'
);

select * from finish();
rollback;

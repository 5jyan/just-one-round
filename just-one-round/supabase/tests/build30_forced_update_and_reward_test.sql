-- This test is intentionally transaction-scoped. It uses the production
-- app_runtime_config row and production compatibility/reward functions, then
-- rolls every fixture back. Run it only after the forced-update reward
-- migration (20260915000100) and Android production-transition migration
-- (20261011000300) are present in the database; it does not install fallback
-- DDL that could hide a missing production migration.

begin;

select plan(22);

select ok(
  to_regclass('public.app_update_reward_claims') is not null,
  'the production update-reward claims table is installed'
);
select ok(
  to_regprocedure('public.claim_app_update_reward()') is not null,
  'the production update-reward claim function is installed'
);
select ok(
  to_regprocedure('public.observe_client_build(integer,text)') is not null,
  'the production build-observation function is installed'
);

select pg_advisory_xact_lock(hashtext('public.build30_forced_update_and_reward_test'));

-- Fixture the exact post-deploy state inside this transaction. The real
-- deploy script accepts only the recorded pre-deploy state or this state and
-- performs the same singleton-row update atomically.
update public.app_runtime_config
set
  minimum_supported_build = 30,
  ios_minimum_supported_build = 30,
  android_minimum_supported_build = 30,
  android_production_only_builds = array[29]::integer[],
  update_reward_enabled = true,
  update_reward_campaign = 'build-30-update-reward',
  update_reward_target_build = 30,
  update_reward_started_at = '2026-10-12T00:00:00Z'::timestamptz,
  update_reward_message = '업데이트 감사 선물로 도전권 1장을 드려요.'
where id;

select is(
  (select minimum_supported_build from public.app_runtime_config where id),
  30,
  'the shared floor is build 30'
);
select is(
  (select ios_minimum_supported_build from public.app_runtime_config where id),
  30,
  'iOS requires build 30'
);
select is(
  (select android_minimum_supported_build from public.app_runtime_config where id),
  30,
  'Android requires build 30'
);
select is(
  (select android_production_only_builds from public.app_runtime_config where id),
  array[29]::integer[],
  'Android Alpha build 29 is production-only'
);
select is(
  (select ios_store_url from public.app_runtime_config where id),
  'https://apps.apple.com/app/id6794861323',
  'the official App Store URL is unchanged'
);
select is(
  (select android_store_url from public.app_runtime_config where id),
  'https://play.google.com/store/apps/details?id=com.justoneround.app',
  'the official Play URL is unchanged'
);

select set_config(
  'request.headers',
  '{"x-app-build":"29","x-app-platform":"ios"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  true,
  'iOS build 29 is forced to update'
);

select set_config(
  'request.headers',
  '{"x-app-build":"28","x-app-platform":"android"}',
  true
);
select is(
  (public.get_client_compatibility()->>'update_required')::boolean,
  true,
  'Android build 28 is forced to update'
);

select set_config(
  'request.headers',
  '{"x-app-build":"29","x-app-platform":"android"}',
  true
);
select is(
  public.get_client_compatibility()->>'reason',
  'production_release_required',
  'Android Alpha build 29 reports the production-release reason'
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

-- Use fixed UUIDs that are only visible inside this rolled-back test. The
-- production auth trigger normally creates these rows; inserting them
-- explicitly keeps the test runnable against a schema-only local clone where
-- Supabase auth triggers are intentionally not dumped.
insert into auth.users (id, is_anonymous)
values
  ('b0300001-3030-4030-8030-000000000001', true),
  ('b0300002-3030-4030-8030-000000000002', true),
  ('b0300003-3030-4030-8030-000000000003', true),
  ('b0300004-3030-4030-8030-000000000004', true);

insert into public.profiles (
  id, created_at, updated_at, is_test_account, store_challenge_tickets
) values
  (
    'b0300001-3030-4030-8030-000000000001',
    '2026-10-01T00:00:00Z'::timestamptz,
    now(), false, 0
  ),
  (
    'b0300002-3030-4030-8030-000000000002',
    '2026-10-13T00:00:00Z'::timestamptz,
    now(), false, 0
  ),
  (
    'b0300003-3030-4030-8030-000000000003',
    '2026-10-01T00:00:00Z'::timestamptz,
    now(), true, 0
  ),
  (
    'b0300004-3030-4030-8030-000000000004',
    '2026-10-01T00:00:00Z'::timestamptz,
    now(), false, 0
  )
on conflict (id) do update set
  created_at = excluded.created_at,
  updated_at = excluded.updated_at,
  is_test_account = excluded.is_test_account,
  store_challenge_tickets = excluded.store_challenge_tickets;

update public.profiles
set
  last_seen_app_build = 28,
  last_seen_app_platform = 'ios',
  pending_update_from_build = null
where id = 'b0300001-3030-4030-8030-000000000001';

update public.profiles
set
  last_seen_app_build = 30,
  last_seen_app_platform = 'android',
  pending_update_from_build = null
where id = 'b0300004-3030-4030-8030-000000000004';

select set_config(
  'request.jwt.claim.sub',
  'b0300001-3030-4030-8030-000000000001',
  true
);
set local role authenticated;
select is(
  public.claim_app_update_reward()->>'tickets_granted',
  '1',
  'an existing profile receives one challenge ticket'::text
);
select is(
  public.claim_app_update_reward()->>'tickets_granted',
  '0',
  'a duplicate claim receives no second ticket'::text
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  'b0300002-3030-4030-8030-000000000002',
  true
);
set local role authenticated;
select is(
  public.claim_app_update_reward()->>'tickets_granted',
  '0',
  'a profile created after the campaign starts receives no ticket'::text
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  'b0300003-3030-4030-8030-000000000003',
  true
);
set local role authenticated;
select is(
  public.claim_app_update_reward()->>'tickets_granted',
  '0',
  'a test profile receives no production reward'::text
);
reset role;

select is(
  (select store_challenge_tickets::text from public.profiles
   where id = 'b0300001-3030-4030-8030-000000000001'),
  '1',
  'the existing profile balance increases exactly once'
);
select is(
  (select count(*)::text from public.app_update_reward_claims
   where user_id = 'b0300001-3030-4030-8030-000000000001'
     and campaign_id = 'build-30-update-reward'),
  '1',
  'the campaign stores exactly one claim for the existing profile'
);

select set_config(
  'request.jwt.claim.sub',
  'b0300004-3030-4030-8030-000000000004',
  true
);
set local role authenticated;
select is(
  public.claim_app_update_reward()->>'tickets_granted',
  '1',
  'an existing profile already observed on build 30 still receives one ticket'::text
);
reset role;

select set_config(
  'test.build30_started_at',
  (select update_reward_started_at::text from public.app_runtime_config where id),
  true
);

-- This is the retry branch from the deployment script: every desired field is
-- written again, while the already-created campaign timestamp is preserved.
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
  update_reward_message = '업데이트 감사 선물로 도전권 1장을 드려요.'
where id;

select is(
  (select update_reward_started_at::text from public.app_runtime_config where id),
  current_setting('test.build30_started_at'),
  'a deployment retry preserves the campaign start timestamp'
);

select * from finish();
rollback;

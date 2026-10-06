begin;

select plan(5);

update public.app_runtime_config
set
  rewarded_ads_enabled = true,
  local_test_ad_verification_enabled = false
where id = true;

insert into auth.users (id, is_anonymous)
values ('16161616-1616-4616-8616-161616161616', true);

select set_config(
  'request.jwt.claim.sub',
  '16161616-1616-4616-8616-161616161616',
  true
);

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds, started_at
) values (
  '16161616-1616-4616-8616-161616161616',
  public.current_play_date(),
  1,
  'practice',
  'apple_game_v2',
  1,
  140,
  now()
);

select lives_ok(
  $$ select public.prepare_practice_ad(public.current_play_date()) $$,
  'a local test reward session can be prepared normally'
);

select throws_ok(
  $$
    select public.verify_local_practice_ad_for_development((
      select id
      from public.rewarded_ad_grants
      where user_id = '16161616-1616-4616-8616-161616161616'
      order by prepared_at desc
      limit 1
    ))
  $$,
  'P0001',
  'local test ad verification disabled',
  'the development verifier is locked by default'
);

update public.app_runtime_config
set local_test_ad_verification_enabled = true
where id = true;

select lives_ok(
  $$
    select public.verify_local_practice_ad_for_development((
      select id
      from public.rewarded_ad_grants
      where user_id = '16161616-1616-4616-8616-161616161616'
      order by prepared_at desc
      limit 1
    ))
  $$,
  'the development verifier runs only after the local switch is enabled'
);

select is(
  (
    select status::text
    from public.rewarded_ad_grants
    where user_id = '16161616-1616-4616-8616-161616161616'
    order by prepared_at desc
    limit 1
  ),
  'verified',
  'the prepared local reward becomes SSV-verified'
);

select is(
  public.claim_practice_ticket_reward((
    select id
    from public.rewarded_ad_grants
    where user_id = '16161616-1616-4616-8616-161616161616'
    order by prepared_at desc
    limit 1
  ))->>'tickets_granted',
  '2',
  'the normal claim RPC grants two tickets after local verification'
);

select * from finish();
rollback;

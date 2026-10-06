begin;

select plan(7);

insert into auth.users (id, is_anonymous)
values ('23232323-2323-4232-8232-232323232323', true);

update public.app_runtime_config
set rewarded_ads_enabled = true,
    local_test_ad_verification_enabled = true
where id;

select set_config(
  'request.jwt.claim.sub',
  '23232323-2323-4232-8232-232323232323',
  true
);

select is(
  public.get_today_state()->>'coin_ad_available',
  'true',
  'the daily shop coin ad starts available'
);

create temporary table prepared_coin_ad as
select public.prepare_coin_ad(public.current_play_date()) as payload;

select is(
  (select payload->>'status' from prepared_coin_ad),
  'prepared',
  'the server prepares a coin reward session'
);

select lives_ok(
  format(
    'select public.verify_local_coin_ad_for_development(%L::uuid)',
    (select payload->>'id' from prepared_coin_ad)
  ),
  'local rewarded-ad verification can verify the coin session'
);

select is(
  public.claim_coin_ad_reward(
    (select (payload->>'id')::uuid from prepared_coin_ad)
  )->>'coins_granted',
  '50',
  'a verified daily shop ad grants 50 coins'
);

select is(
  public.claim_coin_ad_reward(
    (select (payload->>'id')::uuid from prepared_coin_ad)
  )->>'coins',
  '50',
  'retrying the claim does not grant coins twice'
);

select is(
  public.get_today_state()->>'coin_ad_available',
  'false',
  'the shop ad is unavailable after its reward is consumed'
);

select throws_ok(
  $$ select public.prepare_coin_ad(public.current_play_date()) $$,
  'P0001',
  'daily coin ad already used',
  'a second shop coin ad cannot be prepared on the same day'
);

select * from finish();
rollback;

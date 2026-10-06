begin;

select plan(23);

update public.app_runtime_config
set rewarded_ads_enabled = true
where id = true;

insert into auth.users (id, is_anonymous)
values
  ('13131313-1313-4313-8313-131313131313', true),
  ('14141414-1414-4414-8414-141414141414', true),
  ('15151515-1515-4515-8515-151515151515', true);

select set_config(
  'request.jwt.claim.sub',
  '13131313-1313-4313-8313-131313131313',
  true
);

select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'aaaaaaaa-0000-4000-8000-000000000001'
  )->>'ordinal',
  '1',
  'the free practice ticket starts practice one'
);
select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'aaaaaaaa-0000-4000-8000-000000000001'
  )->>'practice_ordinal',
  '1',
  'the first practice uses shared practice seed P1'
);
select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'aaaaaaaa-0000-4000-8000-000000000001'
  )->>'id',
  (
    select id::text
    from public.daily_play_sessions
    where user_id = '13131313-1313-4313-8313-131313131313'
      and client_request_id = 'aaaaaaaa-0000-4000-8000-000000000001'
  ),
  'a retried free-practice request returns the same session'
);
select is(
  (
    select count(*)::integer
    from public.daily_play_sessions
    where user_id = '13131313-1313-4313-8313-131313131313'
  ),
  1,
  'an idempotent retry does not consume another ticket'
);
select throws_ok(
  $$
    select public.claim_daily_practice_v2(
      public.current_play_date(),
      'aaaaaaaa-0000-4000-8000-000000000002'
    )
  $$,
  'P0001',
  'practice is not available',
  'a second practice is blocked before the ad reward'
);
select lives_ok(
  $$ select public.prepare_practice_ad(public.current_play_date()) $$,
  'the two-ticket practice reward can be prepared'
);

update public.rewarded_ad_grants
set status = 'verified', verified_at = now()
where user_id = '13131313-1313-4313-8313-131313131313'
  and grant_purpose = 'practice'
  and status = 'prepared';

select is(
  public.claim_practice_ticket_reward((
    select id
    from public.rewarded_ad_grants
    where user_id = '13131313-1313-4313-8313-131313131313'
  ))->>'tickets_granted',
  '2',
  'the verified ad grants two tickets without starting practice'
);
select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'aaaaaaaa-0000-4000-8000-000000000002'
  )->>'ordinal',
  '2',
  'the first rewarded ticket starts practice two'
);
select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'aaaaaaaa-0000-4000-8000-000000000002'
  )->>'practice_ordinal',
  '2',
  'practice two uses shared practice seed P2'
);
select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'aaaaaaaa-0000-4000-8000-000000000003'
  )->>'practice_ordinal',
  '3',
  'the final rewarded ticket uses shared practice seed P3'
);
select is(
  (public.claim_daily_attempt(public.current_play_date())).grant_type::text,
  'daily',
  'challenge remains free after every practice ticket is used'
);
select is(
  (
    select ordinal
    from public.daily_play_sessions
    where user_id = '13131313-1313-4313-8313-131313131313'
      and play_mode = 'challenge'
  ),
  4::smallint,
  'challenge follows three practices without changing its grant type'
);

update public.attempts
set status = 'expired'
where user_id = '13131313-1313-4313-8313-131313131313';

select throws_ok(
  $$ select public.claim_daily_attempt(public.current_play_date()) $$,
  'P0001',
  'challenge is not available',
  'a terminal challenge cannot be replayed'
);

select set_config(
  'request.jwt.claim.sub',
  '14141414-1414-4414-8414-141414141414',
  true
);

select is(
  (public.claim_daily_attempt(public.current_play_date())).ordinal,
  1::smallint,
  'another player can challenge before practicing'
);

update public.attempts
set status = 'expired'
where user_id = '14141414-1414-4414-8414-141414141414';

select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'bbbbbbbb-0000-4000-8000-000000000001'
  )->>'practice_ordinal',
  '1',
  'practice seed P1 is independent of challenge order'
);
select lives_ok(
  $$ select public.prepare_practice_ad(public.current_play_date()) $$,
  'the reward can be prepared after post-challenge free practice'
);

update public.rewarded_ad_grants
set status = 'verified', verified_at = now()
where user_id = '14141414-1414-4414-8414-141414141414'
  and grant_purpose = 'practice'
  and status = 'prepared';

select is(
  public.claim_practice_ticket_reward((
    select id
    from public.rewarded_ad_grants
    where user_id = '14141414-1414-4414-8414-141414141414'
  ))->>'practice_tickets_remaining',
  '2',
  'post-challenge reward also grants two tickets'
);
select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'bbbbbbbb-0000-4000-8000-000000000002'
  )->>'ordinal',
  '3',
  'the first rewarded practice follows challenge and free practice'
);
select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'bbbbbbbb-0000-4000-8000-000000000003'
  )->>'ordinal',
  '4',
  'the second rewarded practice is the final daily practice'
);

select set_config(
  'request.jwt.claim.sub',
  '15151515-1515-4515-8515-151515151515',
  true
);
select lives_ok(
  $$
    select public.register_device_installation(
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    )
  $$,
  'a fresh account registers its installation'
);

insert into public.device_daily_claims (device_hash, play_date)
values (
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  public.current_play_date()
);

select isnt(
  public.get_today_state()->>'challenge_available',
  'true',
  'a device-limited account cannot start the challenge'
);
select isnt(
  public.get_today_state()->>'practice_reward_available',
  'true',
  'a device-limited account cannot watch an unusable reward ad'
);
select is(
  public.get_today_state()->>'device_daily_limit_reached',
  'true',
  'the home state explains the device-level daily limit'
);

select * from finish();
rollback;

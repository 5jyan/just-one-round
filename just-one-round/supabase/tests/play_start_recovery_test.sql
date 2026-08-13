begin;

select plan(18);

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
  'the first free practice starts'
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
  'an idempotent retry does not consume another play ordinal'
);

select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'aaaaaaaa-0000-4000-8000-000000000002'
  )->>'ordinal',
  '2',
  'a distinct second practice receives the next ordinal'
);

select lives_ok(
  $$ select public.prepare_rewarded_ad(public.current_play_date()) $$,
  'the required challenge ad can be prepared after two practices'
);

update public.rewarded_ad_grants
set status = 'verified', verified_at = now()
where user_id = '13131313-1313-4313-8313-131313131313'
  and grant_purpose = 'ranked_extra'
  and status = 'prepared';

select is(
  (public.claim_daily_attempt(public.current_play_date())).ordinal,
  3::smallint,
  'a refreshed client consumes a verified challenge grant after restart'
);

select is(
  (
    select status::text
    from public.rewarded_ad_grants
    where user_id = '13131313-1313-4313-8313-131313131313'
      and grant_purpose = 'ranked_extra'
  ),
  'consumed',
  'the recovered challenge grant is consumed exactly once'
);

select is(
  (
    public.claim_rewarded_attempt_without_kakao((
      select id
      from public.rewarded_ad_grants
      where user_id = '13131313-1313-4313-8313-131313131313'
        and grant_purpose = 'ranked_extra'
    ))
  ).id,
  (
    select attempt_id
    from public.daily_play_sessions
    where user_id = '13131313-1313-4313-8313-131313131313'
      and play_mode = 'challenge'
  ),
  'a lost rewarded-challenge response returns the same live attempt'
);

update public.attempts
set status = 'expired'
where user_id = '13131313-1313-4313-8313-131313131313';

select throws_ok(
  $$ select public.claim_daily_attempt(public.current_play_date()) $$,
  'P0001',
  'challenge is not available',
  'a stale client cannot replay a terminal ranked challenge'
);

select set_config(
  'request.jwt.claim.sub',
  '14141414-1414-4414-8414-141414141414',
  true
);

select is(
  (public.claim_daily_attempt(public.current_play_date())).ordinal,
  1::smallint,
  'the second account starts with its free challenge'
);

update public.attempts
set status = 'expired'
where user_id = '14141414-1414-4414-8414-141414141414';

select lives_ok(
  $$ select public.prepare_practice_ad(public.current_play_date()) $$,
  'the first post-challenge practice ad can be prepared'
);

update public.rewarded_ad_grants
set status = 'verified', verified_at = now()
where user_id = '14141414-1414-4414-8414-141414141414'
  and grant_purpose = 'practice'
  and status = 'prepared';

select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'bbbbbbbb-0000-4000-8000-000000000001'
  )->>'grant_type',
  'practice_ad',
  'a refreshed client attaches a verified practice grant after restart'
);

select is(
  (
    select status::text
    from public.rewarded_ad_grants
    where user_id = '14141414-1414-4414-8414-141414141414'
      and grant_purpose = 'practice'
  ),
  'consumed',
  'the recovered practice grant is consumed exactly once'
);

select is(
  public.claim_practice_attempt((
    select id
    from public.rewarded_ad_grants
    where user_id = '14141414-1414-4414-8414-141414141414'
      and grant_purpose = 'practice'
  ))->>'id',
  (
    select id::text
    from public.daily_play_sessions
    where user_id = '14141414-1414-4414-8414-141414141414'
      and reward_grant_id is not null
  ),
  'a lost rewarded-practice response returns the same session'
);

select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    'bbbbbbbb-0000-4000-8000-000000000002'
  )->>'ordinal',
  '3',
  'later practice starts for free after the one daily ad'
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
  'a device-limited account is not shown an unusable challenge button'
);

select is(
  public.get_today_state()->>'device_daily_limit_reached',
  'true',
  'the home state explains the device-level daily limit'
);

select * from finish();
rollback;

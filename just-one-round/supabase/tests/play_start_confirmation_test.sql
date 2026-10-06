begin;

select plan(19);

select set_config(
  'request.headers',
  '{"x-app-build":"12","x-app-platform":"ios"}',
  true
);

insert into auth.users (id, is_anonymous)
values
  ('18181818-1818-4818-8818-181818181818', true),
  ('19191919-1919-4919-8919-191919191919', true),
  ('20202020-2020-4020-8020-202020202020', true);

select set_config(
  'request.jwt.claim.sub',
  '18181818-1818-4818-8818-181818181818',
  true
);

select lives_ok(
  $$
    select public.register_device_installation(
      '1818181818181818181818181818181818181818181818181818181818181818'
    )
  $$,
  'the challenge account registers its device'
);

select is(
  (public.claim_daily_attempt(public.current_play_date())).ordinal,
  1::smallint,
  'a challenge is issued'
);

select is(
  public.get_today_state()->>'challenge_pending',
  'true',
  'an issued build-12 challenge is pending before runtime confirmation'
);

select is(
  public.get_today_state()->>'challenge_available',
  'true',
  'the pending challenge remains recoverable despite the device claim'
);

select lives_ok(
  $$
    select public.expire_attempt((
      select id from public.attempts
      where user_id = '18181818-1818-4818-8818-181818181818'
    ))
  $$,
  'leaving before the runtime starts does not fail expiration recovery'
);

select is(
  (
    select status::text from public.attempts
    where user_id = '18181818-1818-4818-8818-181818181818'
  ),
  'issued',
  'leaving before start does not consume the challenge'
);

select is(
  (public.claim_daily_attempt(public.current_play_date())).id,
  (
    select id from public.attempts
    where user_id = '18181818-1818-4818-8818-181818181818'
  ),
  'a restarted client recovers the same challenge'
);

select lives_ok(
  $$
    select public.confirm_daily_play_started((
      select id from public.attempts
      where user_id = '18181818-1818-4818-8818-181818181818'
    ))
  $$,
  'the loaded runtime confirms the challenge start'
);

select is(
  public.daily_play_choice_state(
    '18181818-1818-4818-8818-181818181818',
    public.current_play_date()
  )->>'challenge_in_progress',
  'true',
  'a confirmed challenge is now in progress'
);

select set_config(
  'request.jwt.claim.sub',
  '19191919-1919-4919-8919-191919191919',
  true
);

select lives_ok(
  $$
    select public.register_device_installation(
      '1919191919191919191919191919191919191919191919191919191919191919'
    )
  $$,
  'the practice account registers its device'
);

select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    '19191919-0000-4000-8000-000000000001'
  )->>'ordinal',
  '1',
  'a practice is issued without counting as started'
);

select is(
  public.get_today_state()->>'play_count',
  '0',
  'the unstarted practice does not consume a play ordinal'
);

select is(
  public.claim_daily_practice_v2(
    public.current_play_date(),
    '19191919-0000-4000-8000-000000000002'
  )->>'id',
  (
    select id::text from public.daily_play_sessions
    where user_id = '19191919-1919-4919-8919-191919191919'
  ),
  'a new local request id recovers the same pending practice'
);

select is(
  (
    select count(*)::integer from public.daily_play_sessions
    where user_id = '19191919-1919-4919-8919-191919191919'
  ),
  1,
  'reinstall recovery does not create duplicate practice sessions'
);

select lives_ok(
  $$
    select public.confirm_daily_play_started((
      select id from public.daily_play_sessions
      where user_id = '19191919-1919-4919-8919-191919191919'
    ))
  $$,
  'the loaded runtime confirms the practice start'
);

select is(
  public.get_today_state()->>'play_count',
  '1',
  'the confirmed practice counts exactly once'
);

select set_config(
  'request.headers',
  '{"x-app-build":"11","x-app-platform":"ios"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '20202020-2020-4020-8020-202020202020',
  true
);

select lives_ok(
  $$
    select public.register_device_installation(
      '2020202020202020202020202020202020202020202020202020202020202020'
    )
  $$,
  'a build-11 account registers its device'
);

select is(
  (public.claim_daily_attempt(public.current_play_date())).ordinal,
  1::smallint,
  'an older supported client still issues its challenge'
);

select ok(
  (
    select started_at is not null from public.daily_play_sessions
    where user_id = '20202020-2020-4020-8020-202020202020'
  ),
  'build 11 keeps issue-is-start compatibility'
);

select * from finish();
rollback;

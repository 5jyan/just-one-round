begin;

select plan(6);

update public.app_runtime_config
set rewarded_ads_enabled = true
where id = true;

insert into auth.users (id, is_anonymous)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);

select is(
  (public.claim_daily_attempt(public.current_play_date())).ordinal,
  1::smallint,
  'a first-play challenge is issued without an ad'
);

update public.attempts
set status = 'expired'
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select ok(
  (public.daily_play_choice_state(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    public.current_play_date()
  )->>'practice_requires_ad')::boolean,
  'practice after a first-play challenge requires the daily ad'
);

select lives_ok(
  $$ select public.prepare_practice_ad(public.current_play_date()) $$,
  'the one practice ad can be prepared'
);

update public.rewarded_ad_grants
set status = 'verified', verified_at = now()
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and status = 'prepared';

select is(
  public.claim_practice_attempt((
    select id
    from public.rewarded_ad_grants
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and status = 'verified'
  ))->>'ordinal',
  '2',
  'the verified ad issues the first practice'
);

select is(
  public.claim_daily_practice(public.current_play_date())->>'ordinal',
  '3',
  'later practice is issued without another ad'
);

select is(
  public.prepare_practice_ad(public.current_play_date())->>'id',
  (
    select id::text
    from public.rewarded_ad_grants
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and grant_purpose = 'practice'
      and status = 'consumed'
  ),
  'a stale client recovers the consumed practice grant without another ad'
);

select * from finish();
rollback;

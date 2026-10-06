begin;

select plan(20);

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
  public.claim_daily_practice(public.current_play_date())->>'ordinal',
  '1',
  'the free practice ticket issues practice one'
);
select is(
  public.get_today_state()->>'practice_tickets_remaining',
  '0',
  'the free practice leaves no ticket'
);
select is(
  public.get_today_state()->>'practice_reward_available',
  'true',
  'the first two-ticket refill is available'
);

select lives_ok(
  $$ select public.prepare_practice_ad(public.current_play_date()) $$,
  'the first refill ad can be prepared'
);

update public.rewarded_ad_grants
set status = 'verified', verified_at = now()
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and status = 'prepared';

select is(
  public.claim_practice_ticket_reward((
    select id
    from public.rewarded_ad_grants
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    order by prepared_at desc
    limit 1
  ))->>'tickets_granted',
  '2',
  'the first SSV completion grants two tickets'
);
select is(
  public.get_today_state()->>'practice_tickets_remaining',
  '2',
  'both first-refill tickets remain before practice starts'
);

select is(
  (public.claim_daily_attempt(public.current_play_date())).grant_type::text,
  'daily',
  'challenge remains a free daily grant'
);

update public.attempts
set status = 'expired'
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  public.claim_daily_practice(public.current_play_date())->>'ordinal',
  '3',
  'the first rewarded ticket starts practice three'
);
select is(
  public.claim_daily_practice(public.current_play_date())->>'ordinal',
  '4',
  'the second rewarded ticket starts practice four'
);
select is(
  public.get_today_state()->>'practice_tickets_remaining',
  '0',
  'the first refill can be fully consumed'
);
select is(
  public.get_today_state()->>'practice_reward_available',
  'true',
  'another refill becomes available at zero tickets'
);

select lives_ok(
  $$ select public.prepare_practice_ad(public.current_play_date()) $$,
  'the second refill ad can be prepared on the same day'
);
select is(
  (
    select count(*)::integer
    from public.rewarded_ad_grants
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  2,
  'the second refill uses a distinct SSV session'
);

update public.rewarded_ad_grants
set status = 'verified', verified_at = now()
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and status = 'prepared';

select is(
  public.claim_practice_ticket_reward((
    select id
    from public.rewarded_ad_grants
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    order by prepared_at desc
    limit 1
  ))->>'tickets_granted',
  '2',
  'the second SSV completion grants two more tickets'
);
select is(
  public.daily_play_choice_state(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    public.current_play_date()
  )->>'practice_reward_count',
  '2',
  'choice state counts both completed refill ads'
);
select is(
  public.get_today_state()->>'practice_tickets_remaining',
  '2',
  'the second refill restores two tickets'
);
select is(
  public.claim_daily_practice(public.current_play_date())->>'ordinal',
  '5',
  'the third rewarded ticket starts practice five'
);
select is(
  public.claim_daily_practice(public.current_play_date())->>'ordinal',
  '6',
  'the fourth rewarded ticket starts practice six'
);
select is(
  public.get_today_state()->>'practice_tickets_remaining',
  '0',
  'the second refill can also be fully consumed'
);

select is(
  public.claim_practice_ticket_reward((
    select id
    from public.rewarded_ad_grants
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    order by prepared_at desc
    limit 1
  ))->>'tickets_granted',
  '2',
  'a lost second-refill response remains idempotently recoverable'
);

select * from finish();
rollback;

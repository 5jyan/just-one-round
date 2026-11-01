begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(33);

insert into auth.users (id, is_anonymous)
values ('21212121-2121-4121-8121-212121212121', true);

update public.profiles
set coin_balance = 400
where id = '21212121-2121-4121-8121-212121212121';

select set_config(
  'request.jwt.claim.sub',
  '21212121-2121-4121-8121-212121212121',
  true
);

select is(
  public.purchase_shop_item(
    'practice_ticket', 'aaaaaaaa-0000-4000-8000-000000000001'
  )->>'coins',
  '300',
  'a practice ticket costs 100 coins'
);
select is(
  public.purchase_shop_item(
    'practice_ticket', 'aaaaaaaa-0000-4000-8000-000000000001'
  )->>'practice_tickets',
  '1',
  'retrying a purchase request does not grant another ticket'
);
select is(
  (select coin_balance::text from public.profiles
   where id = '21212121-2121-4121-8121-212121212121'),
  '300',
  'an idempotent retry does not spend coins twice'
);
select is(
  public.purchase_shop_item(
    'challenge_ticket', 'aaaaaaaa-0000-4000-8000-000000000002'
  )->>'coins',
  '50',
  'a challenge ticket costs 250 coins'
);
select is(
  public.daily_play_choice_state(
    '21212121-2121-4121-8121-212121212121', public.current_play_date()
  )->>'practice_tickets_remaining',
  '2',
  'a purchased practice ticket is added after the daily free ticket'
);

select public.ensure_daily_game(public.current_play_date());

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds, started_at
)
select
  '21212121-2121-4121-8121-212121212121', scheduled.play_date, 1,
  'practice', scheduled.game_id, scheduled.game_version,
  versioned.duration_seconds, now()
from public.daily_games scheduled
join public.game_rule_versions versioned
  on versioned.game_id = scheduled.game_id
 and versioned.version = scheduled.game_version
where scheduled.play_date = public.current_play_date();

select is(
  (select store_practice_tickets::text from public.profiles
   where id = '21212121-2121-4121-8121-212121212121'),
  '1',
  'the free practice is consumed before store inventory'
);

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds, started_at
)
select
  '21212121-2121-4121-8121-212121212121', scheduled.play_date, 2,
  'practice', scheduled.game_id, scheduled.game_version,
  versioned.duration_seconds, now()
from public.daily_games scheduled
join public.game_rule_versions versioned
  on versioned.game_id = scheduled.game_id
 and versioned.version = scheduled.game_version
where scheduled.play_date = public.current_play_date();

select is(
  (select store_practice_tickets::text from public.profiles
   where id = '21212121-2121-4121-8121-212121212121'),
  '0',
  'practice beyond the free capacity consumes store inventory'
);

-- Reward earned after a store-funded practice must grant both new tickets.
insert into public.rewarded_ad_grants (
  user_id, play_date, status, grant_purpose, expires_at, game_id, game_version, game_duration_seconds
) values (
  '21212121-2121-4121-8121-212121212121', public.current_play_date(),
  'consumed', 'practice', public.next_daily_reset_at(public.current_play_date()), 'apple_game_v2', 1, 140
);
select is(public.daily_play_choice_state('21212121-2121-4121-8121-212121212121', public.current_play_date())->>'practice_tickets_remaining', '2', 'store practice does not consume the new ad reward');
select is(public.daily_play_choice_state('21212121-2121-4121-8121-212121212121', public.current_play_date())->>'practice_session_count', '2', 'total practice statistics still include store sessions');

-- Tomorrow-preview practice spends the same day balance and retry is idempotent.
select public.ensure_daily_game(public.current_play_date() + 1);
select public.claim_preview_practice(public.current_play_date(), public.current_play_date() + 1, 'bbbbbbbb-0000-4000-8000-000000000001');
select is(public.daily_play_choice_state('21212121-2121-4121-8121-212121212121', public.current_play_date())->>'practice_tickets_remaining', '1', 'preview consumes exactly one shared ad ticket');
select public.claim_preview_practice(public.current_play_date(), public.current_play_date() + 1, 'bbbbbbbb-0000-4000-8000-000000000001');
select is(public.daily_play_choice_state('21212121-2121-4121-8121-212121212121', public.current_play_date())->>'practice_tickets_remaining', '1', 'retry does not spend another ticket');
select public.confirm_daily_play_started(id) from public.daily_play_sessions where client_request_id='bbbbbbbb-0000-4000-8000-000000000001';

update public.daily_play_sessions set ordinal=5 where client_request_id='bbbbbbbb-0000-4000-8000-000000000001';
insert into public.attempts (
  user_id, play_date, game_id, game_version, ordinal,
  grant_type, status
)
select
  '21212121-2121-4121-8121-212121212121', scheduled.play_date,
  scheduled.game_id, scheduled.game_version, 3, 'daily', 'expired'
from public.daily_games scheduled
where scheduled.play_date = public.current_play_date();

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode, attempt_id,
  game_id, game_version, game_duration_seconds, started_at
)
select
  attempt.user_id, attempt.play_date, 3, 'challenge', attempt.id,
  attempt.game_id, attempt.game_version, versioned.duration_seconds, now()
from public.attempts attempt
join public.game_rule_versions versioned
  on versioned.game_id = attempt.game_id
 and versioned.version = attempt.game_version
where attempt.user_id = '21212121-2121-4121-8121-212121212121'
  and attempt.play_date = public.current_play_date()
  and attempt.ordinal = 3;

select is(
  public.daily_play_choice_state(
    '21212121-2121-4121-8121-212121212121', public.current_play_date()
  )->>'challenge_requires_ad',
  'true',
  'the first completed challenge unlocks exactly one ad challenge'
);
select throws_ok(
  $$ select public.claim_daily_attempt(public.current_play_date()) $$,
  'P0001',
  'extra challenge choice required',
  'a purchased challenge ticket cannot skip the ad challenge'
);

insert into public.rewarded_ad_grants (
  user_id, play_date, status, grant_purpose, expires_at
) values (
  '21212121-2121-4121-8121-212121212121', public.current_play_date(),
  'consumed', 'ranked_extra', public.next_daily_reset_at(public.current_play_date())
);

insert into public.attempts (
  user_id, play_date, game_id, game_version, ordinal,
  grant_type, status
)
select
  '21212121-2121-4121-8121-212121212121', scheduled.play_date,
  scheduled.game_id, scheduled.game_version, 4, 'rewarded_ad', 'expired'
from public.daily_games scheduled
where scheduled.play_date = public.current_play_date();

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode, attempt_id, reward_grant_id,
  game_id, game_version, game_duration_seconds, started_at,
  entitlement_source
)
select
  attempt.user_id, attempt.play_date, 4, 'challenge', attempt.id, grant_row.id,
  attempt.game_id, attempt.game_version, versioned.duration_seconds, now(),
  'rewarded_ad'
from public.attempts attempt
join public.game_rule_versions versioned
  on versioned.game_id = attempt.game_id
 and versioned.version = attempt.game_version
join public.rewarded_ad_grants grant_row
  on grant_row.user_id = attempt.user_id
 and grant_row.play_date = attempt.play_date
 and grant_row.grant_purpose = 'ranked_extra'
where attempt.user_id = '21212121-2121-4121-8121-212121212121'
  and attempt.play_date = public.current_play_date()
  and attempt.ordinal = 4;

select is(
  public.daily_play_choice_state(
    '21212121-2121-4121-8121-212121212121', public.current_play_date()
  )->>'ranked_ad_attempt_used',
  'true',
  'the consumed ranked ad is exposed to the client'
);
select is(
  public.daily_play_choice_state(
    '21212121-2121-4121-8121-212121212121', public.current_play_date()
  )->>'challenge_available',
  'true',
  'a challenge ticket becomes usable only after the ad challenge'
);
select is(
  (public.claim_challenge_ticket_attempt(public.current_play_date())).grant_type::text,
  'store_ticket',
  'the next challenge spends a purchased ticket'
);
select is(
  (select store_challenge_tickets::text from public.profiles
   where id = '21212121-2121-4121-8121-212121212121'),
  '0',
  'claiming the ticket challenge decrements persistent inventory'
);

update public.profiles
set store_challenge_tickets = 3
where id = '21212121-2121-4121-8121-212121212121';

update public.attempts
set status = 'expired'
where user_id = '21212121-2121-4121-8121-212121212121'
  and grant_type = 'store_ticket'
  and status = 'issued';
update public.daily_play_sessions
set started_at = coalesce(started_at, now())
where user_id = '21212121-2121-4121-8121-212121212121'
  and entitlement_source = 'store_ticket'
  and started_at is null;

select is(
  public.daily_play_choice_state(
    '21212121-2121-4121-8121-212121212121', public.current_play_date()
  )->>'challenge_available',
  'true',
  'another purchased challenge ticket reopens the same challenge button'
);

select is(
  (public.claim_challenge_ticket_attempt(public.current_play_date())).grant_type::text,
  'store_ticket',
  'a second ticket challenge can be claimed on the same day'
);
select is(
  (select store_challenge_tickets::text from public.profiles
   where id = '21212121-2121-4121-8121-212121212121'),
  '2',
  'the second ticket challenge consumes one ticket'
);
update public.attempts
set status = 'expired'
where user_id = '21212121-2121-4121-8121-212121212121'
  and grant_type = 'store_ticket'
  and status = 'issued';
update public.daily_play_sessions
set started_at = coalesce(started_at, now())
where user_id = '21212121-2121-4121-8121-212121212121'
  and entitlement_source = 'store_ticket'
  and started_at is null;

select is(
  public.daily_play_choice_state(
    '21212121-2121-4121-8121-212121212121', public.current_play_date()
  )->>'challenge_available',
  'true',
  'ticket challenges remain available after another completed retry'
);

select is(
  (public.claim_challenge_ticket_attempt(public.current_play_date())).grant_type::text,
  'store_ticket',
  'a third ticket challenge can be claimed on the same day'
);
select is(
  (select store_challenge_tickets::text from public.profiles
   where id = '21212121-2121-4121-8121-212121212121'),
  '1',
  'the third ticket challenge consumes one ticket'
);

update public.attempts
set status = 'expired'
where user_id = '21212121-2121-4121-8121-212121212121'
  and grant_type = 'store_ticket'
  and status = 'issued';
update public.daily_play_sessions
set started_at = coalesce(started_at, now())
where user_id = '21212121-2121-4121-8121-212121212121'
  and entitlement_source = 'store_ticket'
  and started_at is null;

select is(
  public.daily_play_choice_state(
    '21212121-2121-4121-8121-212121212121', public.current_play_date()
  )->>'challenge_available',
  'true',
  'ticket challenges remain available while inventory is positive'
);

select is(
  (public.claim_challenge_ticket_attempt(public.current_play_date())).grant_type::text,
  'store_ticket',
  'a fourth ticket challenge can be claimed on the same day'
);
select is(
  (select store_challenge_tickets::text from public.profiles
   where id = '21212121-2121-4121-8121-212121212121'),
  '0',
  'the final ticket challenge consumes the last ticket'
);

update public.attempts
set status = 'expired'
where user_id = '21212121-2121-4121-8121-212121212121'
  and grant_type = 'store_ticket'
  and status = 'issued';
update public.daily_play_sessions
set started_at = coalesce(started_at, now())
where user_id = '21212121-2121-4121-8121-212121212121'
  and entitlement_source = 'store_ticket'
  and started_at is null;

select is(
  public.daily_play_choice_state(
    '21212121-2121-4121-8121-212121212121', public.current_play_date()
  )->>'challenge_available',
  'false',
  'the challenge closes only after all tickets are spent'
);

select is(public.daily_play_choice_state('21212121-2121-4121-8121-212121212121', public.current_play_date())->>'practice_tickets_remaining', '1', 'ticket challenge claims leave the remaining practice ticket intact');
select is((select store_practice_tickets::text from public.profiles where id='21212121-2121-4121-8121-212121212121'), '0', 'challenge claims never debit practice inventory');
select public.claim_daily_practice_v2(public.current_play_date(), 'bbbbbbbb-0000-4000-8000-000000000002');
select is(public.daily_play_choice_state('21212121-2121-4121-8121-212121212121', public.current_play_date())->>'practice_tickets_remaining', '0', 'both ad tickets remain usable after store practice and challenges');
select public.confirm_daily_play_started(id) from public.daily_play_sessions where client_request_id='bbbbbbbb-0000-4000-8000-000000000002';
insert into public.rewarded_ad_grants (user_id, play_date, status, grant_purpose, expires_at, game_id, game_version, game_duration_seconds) values ('21212121-2121-4121-8121-212121212121',public.current_play_date(),'consumed','practice',public.next_daily_reset_at(public.current_play_date()),'apple_game_v2',1,140);
select is(public.daily_play_choice_state('21212121-2121-4121-8121-212121212121', public.current_play_date())->>'practice_tickets_remaining', '2', 'repeat ad reward grants another full pair');
update public.profiles set store_practice_tickets=1 where id='21212121-2121-4121-8121-212121212121';
select public.claim_daily_practice_v2(public.current_play_date(), 'bbbbbbbb-0000-4000-8000-000000000003');
select is((select store_practice_tickets::text from public.profiles where id='21212121-2121-4121-8121-212121212121'), '1', 'new ad capacity is spent before remaining store inventory');
select is(public.daily_play_choice_state('21212121-2121-4121-8121-212121212121', public.current_play_date())->>'practice_tickets_remaining', '2', 'one ad ticket and one store ticket remain');

select * from finish();
rollback;

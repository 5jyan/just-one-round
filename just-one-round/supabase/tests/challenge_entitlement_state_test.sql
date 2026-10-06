begin;

select plan(8);

insert into auth.users (id, is_anonymous)
values ('31313131-3131-4131-8131-313131313131', true);

select public.ensure_daily_game(public.current_play_date());

update public.app_runtime_config
set rewarded_ads_enabled = true
where id;

update public.profiles
set
  is_test_account = false,
  store_challenge_tickets = 1,
  store_nickname_change_tickets = 3
where id = '31313131-3131-4131-8131-313131313131';

select set_config(
  'request.jwt.claim.sub',
  '31313131-3131-4131-8131-313131313131',
  true
);

insert into public.attempts (
  user_id, play_date, game_id, game_version, ordinal, grant_type, status
)
select
  '31313131-3131-4131-8131-313131313131', scheduled.play_date,
  scheduled.game_id, scheduled.game_version, 1, 'daily', 'expired'
from public.daily_games scheduled
where scheduled.play_date = public.current_play_date();

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode, attempt_id,
  game_id, game_version, game_duration_seconds, started_at,
  entitlement_source
)
select
  attempt.user_id, attempt.play_date, attempt.ordinal, 'challenge',
  attempt.id, attempt.game_id, attempt.game_version, versioned.duration_seconds,
  now(), 'daily'
from public.attempts attempt
join public.game_rule_versions versioned
  on versioned.game_id = attempt.game_id
 and versioned.version = attempt.game_version
where attempt.user_id = '31313131-3131-4131-8131-313131313131'
  and attempt.play_date = public.current_play_date()
  and attempt.ordinal = 1;

insert into public.rewarded_ad_grants (
  user_id, play_date, status, grant_purpose, expires_at, consumed_at
)
values (
  '31313131-3131-4131-8131-313131313131', public.current_play_date(),
  'consumed', 'ranked_extra', public.next_daily_reset_at(public.current_play_date()),
  now()
);

insert into public.attempts (
  user_id, play_date, game_id, game_version, ordinal, grant_type, status
)
select
  '31313131-3131-4131-8131-313131313131', scheduled.play_date,
  scheduled.game_id, scheduled.game_version, 2, 'rewarded_ad', 'expired'
from public.daily_games scheduled
where scheduled.play_date = public.current_play_date();

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode, attempt_id, reward_grant_id,
  game_id, game_version, game_duration_seconds, started_at,
  entitlement_source
)
select
  attempt.user_id, attempt.play_date, attempt.ordinal, 'challenge',
  attempt.id, grant_row.id, attempt.game_id, attempt.game_version,
  versioned.duration_seconds, now(), 'rewarded_ad'
from public.attempts attempt
join public.game_rule_versions versioned
  on versioned.game_id = attempt.game_id
 and versioned.version = attempt.game_version
join public.rewarded_ad_grants grant_row
  on grant_row.user_id = attempt.user_id
 and grant_row.play_date = attempt.play_date
 and grant_row.grant_purpose = 'ranked_extra'
where attempt.user_id = '31313131-3131-4131-8131-313131313131'
  and attempt.play_date = public.current_play_date()
  and attempt.ordinal = 2;

select is(
  public.get_today_state()->>'ad_challenge_available',
  'false',
  'a consumed ranked ad is not exposed as an available ad challenge'
);
select is(
  public.get_today_state()->>'extra_challenge_available',
  'true',
  'a purchased ticket keeps the extra challenge available'
);
select is(
  public.get_today_state()->>'challenge_ticket_available',
  'true',
  'the purchased challenge ticket is exposed as available'
);
select is(
  public.get_today_state()->>'challenge_requires_ad',
  'false',
  'the next challenge does not require another ad after the ad challenge'
);
select is(
  public.get_today_state()->>'ranked_ad_attempt_used',
  'true',
  'the consumed ranked ad remains marked as used'
);
select is(
  public.get_today_state()->>'store_challenge_tickets',
  '1',
  'the purchased challenge ticket balance is preserved'
);
select is(
  public.get_today_state()->>'store_nickname_change_tickets',
  '3',
  'the nickname ticket wrapper field is preserved'
);
select is(
  public.get_today_state()->>'ad_attempt_available',
  'false',
  'the legacy ad attempt flag is also closed after the ranked ad'
);

select * from finish();
rollback;

begin;

select plan(12);

insert into auth.users (id, is_anonymous)
values ('11111111-1111-4111-8111-111111111111', true);

select is(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'practice_tickets_remaining',
  '1',
  'a fresh day starts with one free practice ticket'
);
select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'challenge_available')::boolean,
  'the daily challenge starts available'
);
select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'practice_available')::boolean,
  'the free practice ticket can be used'
);

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds
) values (
  '11111111-1111-4111-8111-111111111111', date '2099-02-01', 1,
  'practice', 'apple_game_v2', 1, 140
);

select is(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'practice_tickets_remaining',
  '0',
  'the free practice consumes its one ticket'
);
select isnt(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'practice_available',
  'true',
  'practice closes when no ticket remains'
);
select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'practice_reward_available')::boolean,
  'the two-ticket ad reward opens after free practice'
);
select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'challenge_available')::boolean,
  'challenge stays free after practice'
);
select isnt(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'challenge_requires_ad',
  'true',
  'challenge never requires an ad'
);

insert into public.rewarded_ad_grants (
  user_id, play_date, status, grant_purpose,
  game_id, game_version, game_duration_seconds, expires_at
) values (
  '11111111-1111-4111-8111-111111111111', date '2099-02-01',
  'consumed', 'practice', 'apple_game_v2', 1, 140,
  now() + interval '1 day'
);

select is(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'practice_ticket_capacity',
  '3',
  'the ad raises daily practice capacity to three'
);
select is(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'practice_tickets_remaining',
  '2',
  'the ad grants exactly two remaining tickets'
);
select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'practice_available')::boolean,
  'practice reopens after the ticket reward'
);
select isnt(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111', date '2099-02-01'
  )->>'practice_reward_available',
  'true',
  'another reward cannot be stacked while two tickets remain'
);

select * from finish();
rollback;

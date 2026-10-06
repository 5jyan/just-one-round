begin;

select plan(12);

insert into auth.users (id, is_anonymous)
values ('55555555-5555-4555-8555-555555555555', true);

select isnt(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_reward_available',
  'true',
  'the refill stays hidden before free practice is used'
);

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds, started_at
) values (
  '55555555-5555-4555-8555-555555555555', date '2099-02-02', 1,
  'practice', 'apple_game_v2', 1, 140, now()
);

select ok(
  (public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_reward_available')::boolean,
  'a refill opens after the free ticket is consumed'
);
select isnt(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'challenge_requires_ad',
  'true',
  'practice never turns challenge into an ad-gated play'
);

insert into public.rewarded_ad_grants (
  user_id, play_date, status, grant_purpose,
  game_id, game_version, game_duration_seconds, expires_at
) values (
  '55555555-5555-4555-8555-555555555555', date '2099-02-02',
  'consumed', 'practice', 'apple_game_v2', 1, 140,
  now() + interval '1 day'
);

select is(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_tickets_remaining',
  '2',
  'one ad grants exactly two tickets'
);
select isnt(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_reward_available',
  'true',
  'another refill cannot be stacked while tickets remain'
);

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds, started_at
) values
  (
    '55555555-5555-4555-8555-555555555555', date '2099-02-02', 2,
    'practice', 'apple_game_v2', 1, 140, now()
  ),
  (
    '55555555-5555-4555-8555-555555555555', date '2099-02-02', 3,
    'practice', 'apple_game_v2', 1, 140, now()
  );

select is(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_tickets_remaining',
  '0',
  'both rewarded tickets can be consumed'
);
select ok(
  (public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_reward_available')::boolean,
  'the refill opens again whenever balance returns to zero'
);

select lives_ok(
  $$
    insert into public.rewarded_ad_grants (
      user_id, play_date, status, grant_purpose,
      game_id, game_version, game_duration_seconds, expires_at
    ) values (
      '55555555-5555-4555-8555-555555555555', date '2099-02-02',
      'consumed', 'practice', 'apple_game_v2', 1, 140,
      now() + interval '1 day'
    )
  $$,
  'a second verified reward is accepted on the same day'
);
select is(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_reward_count',
  '2',
  'both rewarded ads are counted'
);
select is(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_ticket_capacity',
  '5',
  'two ads raise total daily entitlement to five tickets'
);
select is(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_tickets_remaining',
  '2',
  'the second ad adds two fresh tickets'
);
select is(
  (
    select count(*)::integer
    from public.rewarded_ad_grants
    where user_id = '55555555-5555-4555-8555-555555555555'
      and play_date = date '2099-02-02'
  ),
  2,
  'both daily reward grants remain independently auditable'
);

select * from finish();
rollback;

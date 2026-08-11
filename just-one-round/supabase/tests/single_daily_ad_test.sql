begin;

select plan(12);

insert into auth.users (id, is_anonymous)
values
  ('55555555-5555-4555-8555-555555555555', true),
  ('66666666-6666-4666-8666-666666666666', true);

select isnt(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'challenge_requires_ad',
  'true',
  'the first challenge is free'
);

select isnt(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_requires_ad',
  'true',
  'practice before a challenge is free'
);

insert into public.attempts (
  id, user_id, play_date, game_id, game_version, ordinal, grant_type, status
) values (
  '77777777-7777-4777-8777-777777777777',
  '55555555-5555-4555-8555-555555555555',
  date '2099-02-02', 'apple_game_v2', 1, 1, 'daily', 'expired'
);
insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode, attempt_id,
  game_id, game_version, game_duration_seconds
) values (
  '55555555-5555-4555-8555-555555555555', date '2099-02-02', 1,
  'challenge', '77777777-7777-4777-8777-777777777777',
  'apple_game_v2', 1, 140
);

select ok(
  (public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_available')::boolean,
  'practice is available after a first-play challenge'
);

select ok(
  (public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_requires_ad')::boolean,
  'the first practice after a first-play challenge requires the one ad'
);

insert into public.rewarded_ad_grants (
  user_id, play_date, status, grant_purpose,
  game_id, game_version, game_duration_seconds, expires_at
) values (
  '55555555-5555-4555-8555-555555555555', date '2099-02-02',
  'consumed', 'practice', 'apple_game_v2', 1, 140, now() + interval '1 day'
);

select ok(
  (public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'ad_watched')::boolean,
  'a consumed reward marks the daily ad as watched'
);

select isnt(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'practice_requires_ad',
  'true',
  'practice is free after the daily ad'
);

select isnt(
  public.daily_play_choice_state(
    '55555555-5555-4555-8555-555555555555', date '2099-02-02'
  )->>'next_play_requires_ad',
  'true',
  'no later play requires another ad'
);

select throws_ok(
  $$
    insert into public.rewarded_ad_grants (
      user_id, play_date, grant_purpose, expires_at
    ) values (
      '55555555-5555-4555-8555-555555555555', date '2099-02-02',
      'ranked_extra', now() + interval '1 day'
    )
  $$,
  'P0001',
  'daily rewarded ad already used',
  'a second daily rewarded ad grant is rejected'
);

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds
) values (
  '66666666-6666-4666-8666-666666666666', date '2099-02-02', 1,
  'practice', 'apple_game_v2', 1, 140
);

select ok(
  (public.daily_play_choice_state(
    '66666666-6666-4666-8666-666666666666', date '2099-02-02'
  )->>'challenge_requires_ad')::boolean,
  'a challenge after practice requires the daily ad'
);

select isnt(
  public.daily_play_choice_state(
    '66666666-6666-4666-8666-666666666666', date '2099-02-02'
  )->>'practice_requires_ad',
  'true',
  'the second practice is still free'
);

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds
) values (
  '66666666-6666-4666-8666-666666666666', date '2099-02-02', 2,
  'practice', 'apple_game_v2', 1, 140
);

select ok(
  (public.daily_play_choice_state(
    '66666666-6666-4666-8666-666666666666', date '2099-02-02'
  )->>'challenge_requires_ad')::boolean,
  'the required third-play challenge uses the daily ad'
);

select isnt(
  public.daily_play_choice_state(
    '66666666-6666-4666-8666-666666666666', date '2099-02-02'
  )->>'practice_available',
  'true',
  'a third practice remains unavailable'
);

select * from finish();
rollback;

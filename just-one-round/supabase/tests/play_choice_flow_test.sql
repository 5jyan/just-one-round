begin;

select plan(11);

insert into auth.users (id, is_anonymous)
values ('11111111-1111-4111-8111-111111111111', true);

select is(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'play_count',
  '0',
  'a fresh day starts at play zero'
);
select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'challenge_available')::boolean,
  'challenge is available on play one'
);
select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'practice_available')::boolean,
  'practice is available on play one'
);

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds
) values (
  '11111111-1111-4111-8111-111111111111', date '2099-02-01', 1,
  'practice', 'apple_game_v2', 1, 140
);

select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'challenge_available')::boolean,
  'challenge remains available after one practice'
);
select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'practice_available')::boolean,
  'practice remains available for play two'
);
select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'next_play_requires_ad')::boolean,
  'play two requires an ad'
);

insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode,
  game_id, game_version, game_duration_seconds
) values (
  '11111111-1111-4111-8111-111111111111', date '2099-02-01', 2,
  'practice', 'apple_game_v2', 1, 140
);

select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'challenge_available')::boolean,
  'challenge is required on play three'
);
select isnt(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'practice_available',
  'true',
  'a third consecutive practice is unavailable'
);

insert into public.attempts (
  id, user_id, play_date, game_id, game_version, ordinal, grant_type
) values (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  date '2099-02-01', 'apple_game_v2', 1, 3, 'rewarded_ad'
);
insert into public.daily_play_sessions (
  user_id, play_date, ordinal, play_mode, attempt_id,
  game_id, game_version, game_duration_seconds
) values (
  '11111111-1111-4111-8111-111111111111', date '2099-02-01', 3,
  'challenge', '22222222-2222-4222-8222-222222222222',
  'apple_game_v2', 1, 140
);

select isnt(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'practice_available',
  'true',
  'practice waits while the challenge is in progress'
);

update public.attempts
set status = 'expired'
where id = '22222222-2222-4222-8222-222222222222';

select ok(
  (public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'practice_available')::boolean,
  'practice is available after the challenge finishes'
);
select isnt(
  public.daily_play_choice_state(
    '11111111-1111-4111-8111-111111111111',
    date '2099-02-01'
  )->>'challenge_available',
  'true',
  'a second challenge is unavailable'
);

select * from finish();
rollback;

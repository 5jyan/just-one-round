-- Run after 20260924000100_western_duel.sql inside a transaction and roll back.
do $$
declare
  play_day date := public.current_play_date();
  bot_user uuid := gen_random_uuid();
  shooter_a uuid := gen_random_uuid();
  shooter_b uuid := gen_random_uuid();
  test_shooter uuid := gen_random_uuid();
  challenger_a uuid := gen_random_uuid();
  challenger_b uuid := gen_random_uuid();
  bot_attempt uuid;
  a_attempt uuid;
  b_attempt uuid;
  test_attempt uuid;
  challenge_a_attempt uuid;
  challenge_b_attempt uuid;
  first_opponent jsonb;
  second_opponent jsonb;
  other_opponent jsonb;
begin
  perform set_config('request.headers', '{"x-app-build":"24","x-app-platform":"ios"}', true);

  insert into auth.users(id, is_anonymous) values
    (bot_user, true), (shooter_a, true), (shooter_b, true),
    (test_shooter, true), (challenger_a, true), (challenger_b, true);

  update public.profiles set nickname = 'A 총잡이' where id = shooter_a;
  update public.profiles set nickname = 'B 총잡이' where id = shooter_b;
  update public.profiles set nickname = '테스트 총잡이', is_test_account = true
  where id = test_shooter;

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal,
    grant_type, game_duration_seconds
  ) values (bot_user, play_day, 'western_duel', 1, 1, 'daily', 30)
  returning id into bot_attempt;
  insert into public.daily_play_sessions(
    user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (bot_user, play_day, 1, 'challenge', bot_attempt,
    'western_duel', 1, 30);
  perform set_config('request.jwt.claim.sub', bot_user::text, true);
  first_opponent := public.confirm_western_duel_started(bot_attempt);
  if first_opponent->>'is_bot' <> 'true'
    or (first_opponent->>'reaction_ms')::integer not between 350 and 550 then
    raise exception 'empty leaderboard must assign a 350–550ms bot';
  end if;

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal,
    grant_type, game_duration_seconds
  ) values (shooter_a, play_day, 'western_duel', 1, 1, 'daily', 30)
  returning id into a_attempt;
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal,
    grant_type, game_duration_seconds
  ) values (shooter_b, play_day, 'western_duel', 1, 1, 'daily', 30)
  returning id into b_attempt;
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal,
    grant_type, game_duration_seconds
  ) values (test_shooter, play_day, 'western_duel', 1, 1, 'daily', 30)
  returning id into test_attempt;

  insert into public.scores(
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values
    (a_attempt, shooter_a, play_day, 'western_duel', 1, 999800, 8500),
    (b_attempt, shooter_b, play_day, 'western_duel', 1, 999700, 8600),
    (test_attempt, test_shooter, play_day, 'western_duel', 1, 999900, 8200);

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal,
    grant_type, game_duration_seconds
  ) values (challenger_a, play_day, 'western_duel', 1, 1, 'daily', 30)
  returning id into challenge_a_attempt;
  insert into public.daily_play_sessions(
    user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (challenger_a, play_day, 1, 'challenge', challenge_a_attempt,
    'western_duel', 1, 30);
  perform set_config('request.jwt.claim.sub', challenger_a::text, true);
  first_opponent := public.confirm_western_duel_started(challenge_a_attempt);
  second_opponent := public.confirm_western_duel_started(challenge_a_attempt);
  if first_opponent <> second_opponent then
    raise exception 'opponent snapshot changed on retry';
  end if;
  if first_opponent->>'is_bot' <> 'false'
    or (first_opponent->>'reaction_ms')::integer not in (200, 300) then
    raise exception 'first real assignment ignored eligible human scores';
  end if;

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal,
    grant_type, game_duration_seconds
  ) values (challenger_b, play_day, 'western_duel', 1, 1, 'daily', 30)
  returning id into challenge_b_attempt;
  insert into public.daily_play_sessions(
    user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (challenger_b, play_day, 1, 'challenge', challenge_b_attempt,
    'western_duel', 1, 30);
  perform set_config('request.jwt.claim.sub', challenger_b::text, true);
  other_opponent := public.confirm_western_duel_started(challenge_b_attempt);
  if other_opponent->>'is_bot' <> 'false'
    or other_opponent->>'reaction_ms' = first_opponent->>'reaction_ms' then
    raise exception 'least-used real opponent was not selected first';
  end if;

  -- The ranked result is the challenger's milliseconds, not win/loss.
  perform set_config('request.jwt.claim.sub', challenger_a::text, true);
  update public.attempts
  set issued_at = now() - interval '9 seconds'
  where id = challenge_a_attempt;
  update public.daily_play_sessions
  set started_at = now() - interval '9 seconds'
  where attempt_id = challenge_a_attempt;
  perform public.submit_daily_score(challenge_a_attempt, 999700, 0, 0, 8500);
  if not exists (
    select 1 from public.scores
    where attempt_id = challenge_a_attempt and raw_score = 999700
  ) then
    raise exception 'valid reaction score was not submitted';
  end if;

  perform set_config('request.jwt.claim.sub', challenger_b::text, true);
  update public.attempts
  set issued_at = now() - interval '9 seconds'
  where id = challenge_b_attempt;
  begin
    perform public.submit_daily_score(challenge_b_attempt, 998499, 0, 0, 8500);
    raise exception 'score below 1500ms bound was accepted';
  exception when others then
    if sqlerrm = 'score below 1500ms bound was accepted' then raise; end if;
  end;
  if exists (select 1 from public.scores where attempt_id = challenge_b_attempt) then
    raise exception 'invalid reaction created a rank score';
  end if;
end;
$$;

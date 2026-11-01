-- Run after 20261011000200_previous_game_winner.sql inside a transaction.
begin;

alter table public.scores disable trigger scores_enforce_daily_deadline;

do $$
declare
  play_day date := public.current_play_date();
  target_old date := play_day - 1000;
  target_latest date := play_day - 999;
  other_game_date date := play_day - 998;
  empty_old date := play_day - 1004;
  empty_latest date := play_day - 1003;
  challenger uuid := '10000000-0000-4000-8000-000000000001';
  old_winner uuid := '10000000-0000-4000-8000-000000000002';
  tie_winner_a uuid := '20000000-0000-4000-8000-000000000001';
  tie_winner_b uuid := '30000000-0000-4000-8000-000000000001';
  test_winner uuid := '40000000-0000-4000-8000-000000000001';
  empty_old_winner uuid := '50000000-0000-4000-8000-000000000001';
  old_attempt uuid := '11000000-0000-4000-8000-000000000001';
  tie_attempt_a uuid := '22000000-0000-4000-8000-000000000001';
  tie_attempt_b uuid := '33000000-0000-4000-8000-000000000001';
  test_attempt uuid := '44000000-0000-4000-8000-000000000001';
  empty_old_attempt uuid := '55000000-0000-4000-8000-000000000001';
  result jsonb;
begin
  perform set_config(
    'request.headers',
    '{"x-app-build":"27","x-app-platform":"ios"}',
    true
  );

  insert into auth.users(id, is_anonymous) values
    (challenger, true),
    (old_winner, true),
    (tie_winner_a, true),
    (tie_winner_b, true),
    (test_winner, true),
    (empty_old_winner, true);

  update public.profiles
  set nickname = '조회 도전자'
  where id = challenger;
  update public.profiles
  set nickname = '오래된 우승자'
  where id = old_winner;
  update public.profiles
  set nickname = '먼저 도착한 우승자', experience_points = 900
  where id = tie_winner_a;
  update public.profiles
  set nickname = '나중에 도착한 우승자'
  where id = tie_winner_b;
  update public.profiles
  set nickname = '테스트 우승자', is_test_account = true
  where id = test_winner;
  update public.profiles
  set nickname = '빈 회차 이전 우승자'
  where id = empty_old_winner;

  insert into public.daily_games(play_date, game_id, game_version) values
    (target_old, 'dung_dodge_v2', 1),
    (target_latest, 'dung_dodge_v2', 1),
    (other_game_date, 'gravity_switch', 1),
    (empty_old, 'mole_reaction', 1),
    (empty_latest, 'mole_reaction', 1)
  on conflict (play_date) do update
    set game_id = excluded.game_id,
        game_version = excluded.game_version;

  insert into public.attempts(
    id, user_id, play_date, game_id, game_version, ordinal,
    grant_type, status, game_duration_seconds
  ) values
    (old_attempt, old_winner, target_old, 'dung_dodge_v2', 1, 1,
      'daily', 'submitted', 60),
    (tie_attempt_a, tie_winner_a, target_latest, 'dung_dodge_v2', 1, 1,
      'daily', 'submitted', 60),
    (tie_attempt_b, tie_winner_b, target_latest, 'dung_dodge_v2', 1, 1,
      'daily', 'submitted', 60),
    (test_attempt, test_winner, target_latest, 'dung_dodge_v2', 1, 1,
      'daily', 'submitted', 60),
    (empty_old_attempt, empty_old_winner, empty_old, 'mole_reaction', 1, 1,
      'daily', 'submitted', 60);

  insert into public.scores(
    attempt_id, user_id, play_date, game_id, game_version,
    raw_score, duration_ms, submitted_at
  ) values
    (old_attempt, old_winner, target_old, 'dung_dodge_v2', 1,
      1000, 1000, target_old::timestamptz + interval '1 hour'),
    (tie_attempt_a, tie_winner_a, target_latest, 'dung_dodge_v2', 1,
      500, 1000, target_latest::timestamptz + interval '2 hours'),
    (tie_attempt_b, tie_winner_b, target_latest, 'dung_dodge_v2', 1,
      500, 1000, target_latest::timestamptz + interval '3 hours'),
    (test_attempt, test_winner, target_latest, 'dung_dodge_v2', 1,
      9999, 1000, target_latest::timestamptz + interval '30 minutes'),
    (empty_old_attempt, empty_old_winner, empty_old, 'mole_reaction', 1,
      800, 1000, empty_old::timestamptz + interval '1 hour');

  perform set_config('request.jwt.claim.sub', challenger::text, true);

  result := public.get_previous_game_winner(
    'dung_dodge_v2',
    (other_game_date + 1)
  );
  if result->'leaders'->0->>'nickname' <> '먼저 도착한 우승자'
    or (result->'leaders'->0->>'score')::integer <> 500
    or result->'leaders'->0->>'user_id' <> tie_winner_a::text then
    raise exception 'target-game winner did not use latest target schedule and tie order: %', result;
  end if;
  if (result->'leaders'->0->>'level')::integer <> 4
    or result->'leaders'->0->>'nickname_color' <> 'default' then
    raise exception 'winner profile fields were not returned: %', result;
  end if;

  insert into public.blocked_profiles(blocker_id, blocked_id)
  values (challenger, tie_winner_a);
  result := public.get_previous_game_winner(
    'dung_dodge_v2',
    (other_game_date + 1)
  );
  if result->'leaders'->0->>'nickname' <> '차단한 사용자'
    or result->'leaders'->0->>'user_id' is not null then
    raise exception 'blocked winner was not masked: %', result;
  end if;

  if public.get_previous_game_winner('mole_reaction', empty_latest + 1)
    is not null then
    raise exception 'latest target schedule without a score fell back to an older winner';
  end if;

  if public.get_previous_game_winner('mole_reaction', play_day - 2000)
    is not null then
    raise exception 'first-launch query unexpectedly returned a winner';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.get_previous_game_winner(text,date)',
    'execute'
  ) then
    raise exception 'authenticated role cannot execute previous winner RPC';
  end if;
  if has_function_privilege(
    'anon',
    'public.get_previous_game_winner(text,date)',
    'execute'
  ) then
    raise exception 'anon role can execute previous winner RPC';
  end if;
end;
$$;

alter table public.scores enable trigger scores_enforce_daily_deadline;

rollback;

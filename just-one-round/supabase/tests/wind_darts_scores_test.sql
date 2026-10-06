-- Run after 20261005000200_wind_darts_unlimited_v3.sql inside a transaction
-- and roll back.
begin;

do $$
declare
  play_day date := public.current_play_date();
  challenger uuid := gen_random_uuid();
  better_player uuid := gen_random_uuid();
  lower_player uuid := gen_random_uuid();
  perfect_player uuid := gen_random_uuid();
  challenger_history uuid;
  better_attempt uuid;
  lower_attempt uuid;
  perfect_history uuid;
  challenge_attempt uuid;
  perfect_challenge_attempt uuid;
  challenge_session uuid := gen_random_uuid();
  perfect_session uuid := gen_random_uuid();
  opponent jsonb;
  repeated_opponent jsonb;
  submitted jsonb;
begin
  perform set_config('request.headers', '{"x-app-build":"27","x-app-platform":"ios"}', true);

  insert into auth.users(id, is_anonymous) values
    (challenger, true), (better_player, true),
    (lower_player, true), (perfect_player, true);

  update public.profiles set nickname = '도전자' where id = challenger;
  update public.profiles set nickname = '고수 단골' where id = better_player;
  update public.profiles set nickname = '낮은 기록' where id = lower_player;
  update public.profiles
  set nickname = '만점 도전자', is_test_account = true
  where id = perfect_player;

  -- Seed each player's all-time best. Only the 150-point human is above the
  -- challenger's 100-point personal best; the lower human must be excluded.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values (challenger, play_day, 'wind_darts', 1, 1, 'daily', 75, 'submitted')
  returning id into challenger_history;
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values (better_player, play_day, 'wind_darts', 1, 1, 'daily', 75, 'submitted')
  returning id into better_attempt;
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values (lower_player, play_day, 'wind_darts', 1, 1, 'daily', 75, 'submitted')
  returning id into lower_attempt;
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values (perfect_player, play_day, 'wind_darts', 1, 1, 'daily', 75, 'submitted')
  returning id into perfect_history;

  insert into public.wind_darts_shot_records(attempt_id, user_id, shot_scores, total_score)
  values
    (challenger_history, challenger, array[20,20,20,20,20]::smallint[], 100),
    (better_attempt, better_player, array[30,30,30,30,30]::smallint[], 150),
    (lower_attempt, lower_player, array[10,10,10,10,10]::smallint[], 50),
    (perfect_history, perfect_player, array[60,60,60,60,60]::smallint[], 300);
  insert into public.scores(
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values
    (challenger_history, challenger, play_day, 'wind_darts', 1, 100, 40000),
    (better_attempt, better_player, play_day, 'wind_darts', 1, 150, 40000),
    (lower_attempt, lower_player, play_day, 'wind_darts', 1, 50, 40000),
    (perfect_history, perfect_player, play_day, 'wind_darts', 1, 300, 40000);

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds
  ) values (challenger, play_day, 'wind_darts', 1, 2, 'rewarded_ad', 75)
  returning id into challenge_attempt;
  insert into public.daily_play_sessions(
    id, user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (
    challenge_session, challenger, play_day, 2, 'challenge', challenge_attempt,
    'wind_darts', 1, 75
  );

  perform set_config('request.jwt.claim.sub', challenger::text, true);
  opponent := public.confirm_wind_darts_started(challenge_attempt);
  repeated_opponent := public.confirm_wind_darts_started(challenge_attempt);
  if opponent <> repeated_opponent then
    raise exception 'opponent snapshot changed on retry';
  end if;
  if opponent->>'is_bot' <> 'false'
    or opponent->>'nickname' <> '고수 단골'
    or opponent->'shot_scores' <> '[30,30,30,30,30]'::jsonb then
    raise exception 'challenger was not assigned a higher real opponent: %', opponent;
  end if;
  if not exists (
    select 1 from public.daily_play_sessions
    where id = challenge_session and started_at is not null
  ) then raise exception 'starting a darts game did not confirm its session'; end if;

  update public.attempts
  set issued_at = now() - interval '20 seconds'
  where id = challenge_attempt;
  submitted := public.submit_wind_darts_score(
    challenge_attempt, array[25,60,39,57,20]::smallint[], 10000
  );
  perform public.submit_wind_darts_score(
    challenge_attempt, array[25,60,39,57,20]::smallint[], 10000
  );
  if not exists (
    select 1 from public.wind_darts_shot_records
    where attempt_id = challenge_attempt
      and total_score = 201
      and shot_scores = array[25,60,39,57,20]::smallint[]
  ) then raise exception 'five individual dart scores were not persisted'; end if;
  if (select count(*) from public.scores where attempt_id = challenge_attempt) <> 1 then
    raise exception 'score retry inserted a duplicate leaderboard result';
  end if;
  if submitted->>'score' <> '201' then
    raise exception 'leaderboard score does not equal the five-shot total: %', submitted;
  end if;

  -- A perfect personal record cannot be beaten under standard darts scoring;
  -- the documented maximum-score bot is therefore the only valid fallback.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds
  ) values (perfect_player, play_day, 'wind_darts', 1, 2, 'rewarded_ad', 75)
  returning id into perfect_challenge_attempt;
  insert into public.daily_play_sessions(
    id, user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (
    perfect_session, perfect_player, play_day, 2, 'challenge',
    perfect_challenge_attempt, 'wind_darts', 1, 75
  );
  perform set_config('request.jwt.claim.sub', perfect_player::text, true);
  opponent := public.confirm_wind_darts_started(perfect_challenge_attempt);
  if opponent->>'is_bot' <> 'true'
    or opponent->'shot_scores' <> '[60,60,60,60,60]'::jsonb then
    raise exception 'maximum-score player did not receive the perfect-score fallback';
  end if;
end;
$$;

do $$
declare
  play_day date := public.current_play_date();
  v3_challenger uuid := gen_random_uuid();
  v3_lower_only_challenger uuid := gen_random_uuid();
  v2_history uuid;
  v2_lower_only_history uuid;
  v3_lower_candidate uuid := gen_random_uuid();
  v3_higher_candidate uuid := gen_random_uuid();
  v3_lower_attempt uuid;
  v3_higher_attempt uuid;
  v3_challenge_attempt uuid;
  v3_lower_only_challenge_attempt uuid;
  v3_challenge_session uuid := gen_random_uuid();
  v3_lower_only_challenge_session uuid := gen_random_uuid();
  opponent jsonb;
begin
  perform set_config('request.headers', '{"x-app-build":"27","x-app-platform":"ios"}', true);

  insert into auth.users(id, is_anonymous)
  values
    (v3_challenger, true),
    (v3_lower_only_challenger, true),
    (v3_lower_candidate, true),
    (v3_higher_candidate, true);
  update public.profiles
  set nickname = 'v3 이전 기록 도전자'
  where id = v3_challenger;
  update public.profiles
  set nickname = 'v3 낮은 기록 도전자'
  where id = v3_lower_only_challenger;
  update public.profiles
  set nickname = 'v3 낮은 상대'
  where id = v3_lower_candidate;
  update public.profiles
  set nickname = 'v3 높은 상대'
  where id = v3_higher_candidate;

  -- A v2 personal best still sets the threshold for a new v3 challenge.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values (
    v3_challenger, play_day, 'wind_darts', 2, 1, 'daily', 75, 'submitted'
  )
  returning id into v2_history;
  -- Give the second challenger the same cross-version 200-point best.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values (
    v3_lower_only_challenger, play_day, 'wind_darts', 2, 1,
    'daily', 75, 'submitted'
  ) returning id into v2_lower_only_history;

  insert into public.wind_darts_shot_records(
    attempt_id, user_id, shot_scores, total_score
  ) values
    (v2_history, v3_challenger, array[40,40,40,40,20,20]::smallint[], 200),
    (v2_lower_only_history, v3_lower_only_challenger,
      array[40,40,40,40,20,20]::smallint[], 200);
  insert into public.scores(
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values
    (v2_history, v3_challenger, play_day, 'wind_darts', 2, 200, 40000),
    (v2_lower_only_history, v3_lower_only_challenger,
      play_day, 'wind_darts', 2, 200, 40000);

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values
    (v3_lower_candidate, play_day, 'wind_darts', 3, 1, 'daily', 75, 'submitted')
  returning id into v3_lower_attempt;
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values
    (v3_higher_candidate, play_day, 'wind_darts', 3, 1, 'daily', 75, 'submitted')
  returning id into v3_higher_attempt;
  insert into public.wind_darts_shot_records(
    attempt_id, user_id, shot_scores, total_score
  ) values
    (v3_lower_attempt, v3_lower_candidate,
      array[10,10,10,10,10,10]::smallint[], 60),
    (v3_higher_attempt, v3_higher_candidate,
      array[40,40,40,40,40,40]::smallint[], 240);
  insert into public.scores(
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values
    (v3_lower_attempt, v3_lower_candidate, play_day, 'wind_darts', 3, 60, 40000),
    (v3_higher_attempt, v3_higher_candidate,
      play_day, 'wind_darts', 3, 240, 40000);

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds
  ) values (v3_challenger, play_day, 'wind_darts', 3, 2, 'rewarded_ad', 75)
  returning id into v3_challenge_attempt;
  insert into public.daily_play_sessions(
    id, user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (
    v3_challenge_session, v3_challenger, play_day, 2, 'challenge',
    v3_challenge_attempt, 'wind_darts', 3, 75
  );

  perform set_config('request.jwt.claim.sub', v3_challenger::text, true);
  opponent := public.confirm_wind_darts_started(v3_challenge_attempt);
  if opponent->>'game_version' <> '3'
    or opponent->>'is_bot' <> 'false'
    or opponent->>'nickname' <> 'v3 높은 상대'
    or opponent->'shot_scores' <> '[40,40,40,40,40,40]'::jsonb then
    raise exception 'v3 did not compare against the cross-version 200-point best: %', opponent;
  end if;

  -- Hide the already-snapshotted 240-point candidate to leave only the lower
  -- v3 candidate in the pool for the second 200-point challenger.
  update public.profiles
  set is_test_account = true
  where id = v3_higher_candidate;

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds
  ) values (
    v3_lower_only_challenger, play_day, 'wind_darts', 3, 2, 'rewarded_ad', 75
  ) returning id into v3_lower_only_challenge_attempt;
  insert into public.daily_play_sessions(
    id, user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (
    v3_lower_only_challenge_session, v3_lower_only_challenger, play_day, 2,
    'challenge', v3_lower_only_challenge_attempt, 'wind_darts', 3, 75
  );
  perform set_config(
    'request.jwt.claim.sub', v3_lower_only_challenger::text, true
  );
  opponent := public.confirm_wind_darts_started(v3_lower_only_challenge_attempt);
  if opponent->>'game_version' <> '3'
    or opponent->>'is_bot' <> 'true'
    or opponent->'shot_scores' <> '[60,60,60,60,60,60]'::jsonb then
    raise exception 'v3 lower-only pool did not use the six-shot bot fallback: %', opponent;
  end if;
end;
$$;

do $$
declare
  play_day date := public.current_play_date();
  v3_user uuid := gen_random_uuid();
  v3_attempt uuid;
  v3_session uuid := gen_random_uuid();
  opponent jsonb;
  submitted jsonb;
  rejected boolean;
begin
  perform set_config('request.headers', '{"x-app-build":"27","x-app-platform":"ios"}', true);

  insert into auth.users(id, is_anonymous) values (v3_user, true);
  update public.profiles
  set nickname = '무제한 도전자'
  where id = v3_user;
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds
  ) values (
    v3_user, play_day, 'wind_darts', 3, 1, 'daily', 75
  ) returning id into v3_attempt;
  insert into public.daily_play_sessions(
    id, user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (
    v3_session, v3_user, play_day, 1, 'challenge', v3_attempt,
    'wind_darts', 3, 75
  );

  perform set_config('request.jwt.claim.sub', v3_user::text, true);
  opponent := public.confirm_wind_darts_started(v3_attempt);
  if jsonb_array_length(opponent->'shot_scores') <> 6 then
    raise exception 'v3 opponent did not contain six scores: %', opponent;
  end if;

  -- The server still rejects impossible early results.
  rejected := false;
  begin
    perform public.submit_wind_darts_score(
      v3_attempt, array[60,60,60,0,0,0]::smallint[], 7000
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'v3 early result was accepted'; end if;

  rejected := false;
  begin
    perform public.submit_wind_darts_score(
      v3_attempt, array[60,60,60,0,0,0]::smallint[], 120000
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'v3 elapsed-time check was bypassed'; end if;

  -- 120 seconds is valid for v3 and is stored without the old 75-second cap.
  update public.attempts
  set issued_at = now() - interval '130 seconds'
  where id = v3_attempt;
  submitted := public.submit_wind_darts_score(
    v3_attempt, array[60,60,60,0,0,0]::smallint[], 120000
  );
  perform public.submit_wind_darts_score(
    v3_attempt, array[0,0,0,0,0,0]::smallint[], 8000
  );
  if submitted->>'score' <> '180' then
    raise exception 'v3 score total was not stored: %', submitted;
  end if;
  if (select count(*) from public.scores where attempt_id = v3_attempt) <> 1
    or (select duration_ms from public.scores where attempt_id = v3_attempt)
       <> 120000 then
    raise exception 'v3 actual duration was capped or duplicated';
  end if;
end;
$$;

do $$
declare
  play_day date := public.current_play_date();
  v2_challenger uuid := gen_random_uuid();
  v2_candidate uuid := gen_random_uuid();
  v2_history_v1 uuid;
  v2_history_v2 uuid;
  v2_candidate_attempt uuid;
  v2_challenge_attempt uuid;
  v2_bad_attempt uuid;
  v2_table_attempt uuid;
  v2_opponent_attempt uuid;
  v2_session uuid := gen_random_uuid();
  v2_bad_session uuid := gen_random_uuid();
  v2_opponent_session uuid := gen_random_uuid();
  opponent jsonb;
  repeated_opponent jsonb;
  submitted jsonb;
  rejected boolean;
begin
  perform set_config('request.headers', '{"x-app-build":"27","x-app-platform":"ios"}', true);

  insert into auth.users(id, is_anonymous)
  values (v2_challenger, true), (v2_candidate, true);
  update public.profiles
  set nickname = '버전 2 도전자'
  where id = v2_challenger;
  update public.profiles
  set nickname = '여섯 발 고수'
  where id = v2_candidate;

  -- The challenger has a higher v1 record but a lower v2 record. Opponent
  -- selection must compare personal bests within the target attempt version.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values
    (v2_challenger, play_day - 1, 'wind_darts', 1, 1, 'daily', 75, 'submitted')
  returning id into v2_history_v1;
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values
    (v2_challenger, play_day, 'wind_darts', 2, 2, 'daily', 75, 'submitted')
  returning id into v2_history_v2;
  insert into public.wind_darts_shot_records(
    attempt_id, user_id, shot_scores, total_score
  ) values
    (v2_history_v1, v2_challenger, array[60,60,60,60,60]::smallint[], 300),
    (v2_history_v2, v2_challenger, array[20,20,20,20,20,20]::smallint[], 120);
  insert into public.scores(
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values
    (v2_history_v2, v2_challenger, play_day, 'wind_darts', 2, 120, 40000);

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, status
  ) values (v2_candidate, play_day, 'wind_darts', 2, 1, 'daily', 75, 'submitted')
  returning id into v2_candidate_attempt;
  insert into public.wind_darts_shot_records(
    attempt_id, user_id, shot_scores, total_score
  ) values (
    v2_candidate_attempt, v2_candidate,
    array[30,30,30,30,30,30]::smallint[], 180
  );
  insert into public.scores(
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values (
    v2_candidate_attempt, v2_candidate, play_day, 'wind_darts', 2, 180, 40000
  );

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds
  ) values (v2_challenger, play_day, 'wind_darts', 2, 3, 'rewarded_ad', 75)
  returning id into v2_challenge_attempt;
  insert into public.daily_play_sessions(
    id, user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (
    v2_session, v2_challenger, play_day, 3, 'challenge', v2_challenge_attempt,
    'wind_darts', 2, 75
  );

  perform set_config('request.jwt.claim.sub', v2_challenger::text, true);
  opponent := public.confirm_wind_darts_started(v2_challenge_attempt);
  repeated_opponent := public.confirm_wind_darts_started(v2_challenge_attempt);
  if opponent <> repeated_opponent then
    raise exception 'v2 opponent snapshot changed on retry';
  end if;
  if opponent->>'game_version' <> '2'
    or opponent->>'is_bot' <> 'false'
    or opponent->>'nickname' <> '여섯 발 고수'
    or opponent->'shot_scores' <> '[30,30,30,30,30,30]'::jsonb then
    raise exception 'v2 opponent did not use the target version pool: %', opponent;
  end if;
  if jsonb_array_length(opponent->'shot_scores') <> 6 then
    raise exception 'v2 opponent did not contain six scores';
  end if;

  update public.attempts
  set issued_at = now() - interval '20 seconds'
  where id = v2_challenge_attempt;
  submitted := public.submit_wind_darts_score(
    v2_challenge_attempt, array[50,60,39,57,20,60]::smallint[], 10000
  );
  perform public.submit_wind_darts_score(
    v2_challenge_attempt, array[50,60,39,57,20,60]::smallint[], 10000
  );
  if not exists (
    select 1 from public.wind_darts_shot_records
    where attempt_id = v2_challenge_attempt
      and total_score = 286
      and shot_scores = array[50,60,39,57,20,60]::smallint[]
  ) then raise exception 'six v2 dart scores were not persisted'; end if;
  if (select count(*) from public.scores where attempt_id = v2_challenge_attempt) <> 1 then
    raise exception 'v2 score retry inserted a duplicate leaderboard result';
  end if;
  if submitted->>'score' <> '286' then
    raise exception 'v2 leaderboard score does not equal six-shot total: %', submitted;
  end if;

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds
  ) values (v2_challenger, play_day, 'wind_darts', 2, 4, 'rewarded_ad', 75)
  returning id into v2_bad_attempt;
  insert into public.daily_play_sessions(
    id, user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (
    v2_bad_session, v2_challenger, play_day, 4, 'challenge', v2_bad_attempt,
    'wind_darts', 2, 75
  );
  perform public.confirm_wind_darts_started(v2_bad_attempt);
  update public.attempts
  set issued_at = now() - interval '20 seconds'
  where id = v2_bad_attempt;

  rejected := false;
  begin
    perform public.submit_wind_darts_score(
      v2_bad_attempt, array[25,0,0,0,0,0]::smallint[], 10000
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'v2 bull 25 was accepted'; end if;

  rejected := false;
  begin
    perform public.submit_wind_darts_score(
      v2_bad_attempt, array[1,2,3,4,5]::smallint[], 10000
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'v2 five-shot payload was accepted'; end if;

  rejected := false;
  begin
    perform public.submit_wind_darts_score(
      v2_bad_attempt, array[61,60,60,60,60,60]::smallint[], 10000
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'v2 over-maximum score was accepted'; end if;

  rejected := false;
  begin
    perform public.submit_wind_darts_score(
      v2_bad_attempt, null::smallint[], 10000
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'v2 null array was accepted'; end if;

  rejected := false;
  begin
    perform public.submit_wind_darts_score(
      v2_bad_attempt, array[1,null,3,4,5,6]::smallint[], 10000
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'v2 null element was accepted'; end if;

  rejected := false;
  begin
    perform public.submit_wind_darts_score(
      v2_bad_attempt, array[[1,2,3],[4,5,6]]::smallint[], 10000
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'v2 multidimensional array was accepted'; end if;

  rejected := false;
  begin
    perform public.submit_wind_darts_score(
      v2_bad_attempt, '[0:5]={1,2,3,4,5,6}'::smallint[], 10000
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'v2 non-one lower bound was accepted'; end if;

  update public.attempts set issued_at = now() - interval '80 seconds'
  where id = v2_bad_attempt;
  perform public.submit_wind_darts_score(
    v2_bad_attempt, array[60,60,60,60,60,60]::smallint[], 75099
  );
  if not exists (select 1 from public.wind_darts_shot_records
    where attempt_id = v2_bad_attempt and total_score = 360) then
    raise exception 'legal six-shot maximum was rejected';
  end if;
  if not exists (select 1 from public.scores
    where attempt_id = v2_bad_attempt and duration_ms = 75000) then
    raise exception 'queued timeout duration was not normalized';
  end if;

  -- Verify the widened table constraints independently of the RPC checks.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds
  ) values (v2_challenger, play_day, 'wind_darts', 2, 5, 'rewarded_ad', 75)
  returning id into v2_table_attempt;
  rejected := false;
  begin
    insert into public.wind_darts_shot_records(
      attempt_id, user_id, shot_scores, total_score
    ) values (
      v2_table_attempt, v2_challenger,
      array[[1,2,3],[4,5,6]]::smallint[], 21
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'shot-record multidimensional array was accepted'; end if;

  rejected := false;
  begin
    insert into public.wind_darts_shot_records(
      attempt_id, user_id, shot_scores, total_score
    ) values (
      v2_table_attempt, v2_challenger,
      '[0:5]={1,2,3,4,5,6}'::smallint[], 21
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'shot-record non-one lower bound was accepted'; end if;

  rejected := false;
  begin
    insert into public.wind_darts_shot_records(
      attempt_id, user_id, shot_scores, total_score
    ) values (
      v2_table_attempt, v2_challenger,
      array[1,2,3,4,5,6]::smallint[], 361
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'shot-record maximum score was accepted'; end if;

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds
  ) values (v2_challenger, play_day, 'wind_darts', 2, 6, 'rewarded_ad', 75)
  returning id into v2_opponent_attempt;
  insert into public.daily_play_sessions(
    id, user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds
  ) values (
    v2_opponent_session, v2_challenger, play_day, 6, 'challenge',
    v2_opponent_attempt, 'wind_darts', 2, 75
  );
  rejected := false;
  begin
    insert into public.wind_darts_opponents(
      session_id, nickname, shot_scores, total_score, is_bot
    ) values (
      v2_opponent_session, '잘못된 상대',
      '[0:5]={1,2,3,4,5,6}'::smallint[], 21, true
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'opponent non-one lower bound was accepted'; end if;

  rejected := false;
  begin
    insert into public.wind_darts_opponents(
      session_id, nickname, shot_scores, total_score, is_bot
    ) values (
      v2_opponent_session, '잘못된 상대',
      array[60,60,60,60,60,60]::smallint[], 361, true
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then raise exception 'opponent maximum score was accepted'; end if;
end;
$$;

do $$
declare
  play_day date := public.current_play_date();
  test_user uuid := gen_random_uuid();
  claimed public.attempts;
  state jsonb;
  developer_games jsonb;
  session_version integer;
  session_duration integer;
begin
  insert into auth.users(id, is_anonymous) values (test_user, true);
  update public.profiles
  set is_test_account = true, test_game_id = 'wind_darts'
  where id = test_user;
  perform set_config('request.jwt.claim.sub', test_user::text, true);

  state := public.get_today_state();
  if state->'game'->>'id' <> 'wind_darts'
    or state->'game'->>'version' <> '3'
    or state->'game'->>'duration_seconds' <> '75' then
    raise exception 'test game selection did not expose wind darts v3: %', state;
  end if;
  developer_games := public.get_developer_games();
  if not exists (
    select 1
    from jsonb_array_elements(developer_games) game
    where game->>'id' = 'wind_darts' and game->>'version' = '3'
  ) then
    raise exception 'inactive wind darts v3 was not exposed to test selector';
  end if;

  claimed := public.claim_daily_attempt(play_day);
  if claimed.game_id <> 'wind_darts' or claimed.game_version <> 3 then
    raise exception 'new test attempt did not use wind darts v3: %', claimed;
  end if;
  select session.game_version, session.game_duration_seconds
  into session_version, session_duration
  from public.daily_play_sessions session
  where session.attempt_id = claimed.id;
  if session_version <> 3 or session_duration <> 75 then
    raise exception 'new test session did not use wind darts v3: %/%',
      session_version, session_duration;
  end if;
end;
$$;

rollback;

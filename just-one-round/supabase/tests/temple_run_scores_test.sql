-- Run after 20261015000100_temple_run.sql and
-- 20261017000100_homebound_run_metadata.sql inside a transaction and roll back.
begin;

do $$
declare
  play_day date := public.current_play_date();
  tester uuid := gen_random_uuid();
  invalid_user uuid := gen_random_uuid();
  claim_attempt uuid;
  score_attempt uuid;
  invalid_score_attempt uuid;
  developer_games jsonb;
  today_state jsonb;
  submitted jsonb;
  rejected boolean;
begin
  perform set_config('request.headers', '{"x-app-build":"31","x-app-platform":"ios"}', true);

  insert into auth.users(id, is_anonymous)
  values (tester, true), (invalid_user, true);
  update public.profiles
  set nickname = '유적 테스트', is_test_account = true, test_game_id = 'temple_run'
  where id = tester;
  perform set_config('request.jwt.claim.sub', tester::text, true);

  if (select is_active from public.games where id = 'temple_run') then
    raise exception 'Temple Run must remain inactive while staged';
  end if;
  if not exists (
    select 1
    from public.game_rule_versions
    where game_id = 'temple_run'
      and version = 1
      and duration_seconds = 300
      and minimum_app_build = 31
  ) then
    raise exception 'Temple Run v1 rule snapshot is missing';
  end if;

  developer_games := public.get_developer_games();
  if not exists (
    select 1
    from jsonb_array_elements(developer_games) game
    where game->>'id' = 'temple_run'
      and (game->>'version')::integer = 1
      and game->>'display_name' = '집에 좀 가자'
  ) then
    raise exception 'staged Temple Run is not selectable by test accounts: %',
      developer_games;
  end if;

  today_state := public.get_today_state();
  if today_state->'game'->>'id' <> 'temple_run'
    or (today_state->'game'->>'version')::integer <> 1
    or (today_state->'game'->>'duration_seconds')::integer <> 300
    or today_state->'game'->>'display_name' <> '집에 좀 가자'
    or today_state->'game'->>'description' <>
      '상자와 셔터를 피해 골목을 달리고 공사 도랑을 뛰어넘어 집에 도착하세요.' then
    raise exception 'test account today state did not expose Temple Run: %',
      today_state->'game';
  end if;

  claim_attempt := (public.claim_daily_attempt(play_day)).id;
  if not exists (
    select 1
    from public.attempts
    where id = claim_attempt
      and game_id = 'temple_run'
      and game_version = 1
      and game_duration_seconds = 300
  ) then
    raise exception 'test-account claim did not issue Temple Run v1';
  end if;

  -- A timeout is a valid ranked result at the duration ceiling.
  update public.attempts
  set issued_at = now() - interval '301 seconds'
  where id = claim_attempt;
  submitted := public.submit_daily_score(claim_attempt, 6000, 3, 0, 300000);
  if submitted->>'score' <> '6000' then
    raise exception 'valid Temple Run score was not returned: %', submitted;
  end if;
  perform public.submit_daily_score(claim_attempt, 6000, 3, 0, 300000);
  if (select count(*) from public.scores where attempt_id = claim_attempt) <> 1 then
    raise exception 'Temple Run score retry inserted a duplicate';
  end if;

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, issued_at
  ) values (
    tester, play_day, 'temple_run', 1, 2, 'rewarded_ad', 300,
    now() - interval '6 seconds'
  ) returning id into score_attempt;

  rejected := false;
  begin
    perform public.submit_daily_score(score_attempt, 100001, 0, 1, 5000);
  exception when others then
    rejected := true;
  end;
  if not rejected then
    raise exception 'Temple Run score above 100000 was accepted';
  end if;
  if exists (select 1 from public.scores where attempt_id = score_attempt) then
    raise exception 'invalid Temple Run score created a leaderboard row';
  end if;

  -- Missing a turn ends the run without incrementing collisions. That result
  -- remains valid before the five-minute ceiling.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, issued_at
  ) values (
    tester, play_day, 'temple_run', 1, 3, 'rewarded_ad', 300,
    now() - interval '20 seconds'
  ) returning id into invalid_score_attempt;
  perform public.submit_daily_score(invalid_score_attempt, 120, 0, 0, 15000);

  -- A shield absorbs one solid hit, so the following fatal hit can submit
  -- collisions=2. A shielded timeout can also finish with collisions=1.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, issued_at
  ) values (
    tester, play_day, 'temple_run', 1, 4, 'rewarded_ad', 300,
    now() - interval '35 seconds'
  ) returning id into invalid_score_attempt;
  perform public.submit_daily_score(invalid_score_attempt, 700, 2, 2, 30000);

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, issued_at
  ) values (
    tester, play_day, 'temple_run', 1, 5, 'rewarded_ad', 300,
    now() - interval '301 seconds'
  ) returning id into invalid_score_attempt;
  perform public.submit_daily_score(invalid_score_attempt, 5000, 1, 1, 300000);

  -- A timeout at the exact duration ceiling is accepted even with no hit.
  -- 7202 is the validator's coarse 24m/s upper bound plus its two-metre
  -- tolerance.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, issued_at
  ) values (
    tester, play_day, 'temple_run', 1, 6, 'rewarded_ad', 300,
    now() - interval '301 seconds'
  ) returning id into invalid_score_attempt;
  perform public.submit_daily_score(invalid_score_attempt, 7202, 0, 0, 300000);

  -- A player can collect another shield after spending the previous one, so
  -- a timeout with three accumulated solid hits remains a valid result.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, issued_at
  ) values (
    tester, play_day, 'temple_run', 1, 7, 'rewarded_ad', 300,
    now() - interval '301 seconds'
  ) returning id into invalid_score_attempt;
  perform public.submit_daily_score(invalid_score_attempt, 5000, 1, 3, 300000);

  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, issued_at
  ) values (
    invalid_user, play_day, 'temple_run', 1, 1, 'daily', 300,
    now() - interval '6 seconds'
  ) returning id into invalid_score_attempt;

  perform set_config('request.jwt.claim.sub', invalid_user::text, true);
  rejected := false;
  begin
    perform public.submit_daily_score(invalid_score_attempt, 50000, 0, 0, 5000);
  exception when others then
    rejected := true;
  end;
  if not rejected then
    raise exception 'Temple Run physically impossible distance was accepted';
  end if;

  -- The distance component also cannot be below the elapsed 8m/s floor.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, issued_at
  ) values (
    invalid_user, play_day, 'temple_run', 1, 2, 'daily', 300,
    now() - interval '31 seconds'
  ) returning id into invalid_score_attempt;

  rejected := false;
  begin
    perform public.submit_daily_score(invalid_score_attempt, 0, 0, 0, 30000);
  exception when others then
    rejected := true;
  end;
  if not rejected then
    raise exception 'Temple Run below-minimum distance was accepted';
  end if;

  -- The runtime cannot report more than a shielded hit followed by a
  -- terminal hit.
  insert into public.attempts(
    user_id, play_date, game_id, game_version, ordinal, grant_type,
    game_duration_seconds, issued_at
  ) values (
    invalid_user, play_day, 'temple_run', 1, 3, 'daily', 300,
    now() - interval '31 seconds'
  ) returning id into invalid_score_attempt;

  rejected := false;
  begin
    perform public.submit_daily_score(invalid_score_attempt, 300, 0, 301, 30000);
  exception when others then
    rejected := true;
  end;
  if not rejected then
    raise exception 'Temple Run collision count above runtime bound was accepted';
  end if;
end;
$$;

rollback;

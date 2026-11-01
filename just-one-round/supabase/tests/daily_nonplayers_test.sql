-- Run after 20261012000100_daily_nonplayers.sql inside a transaction.
begin;

select plan(4);

do $$
declare
  play_day date := public.current_play_date();
  preview_day date := play_day + 1;
  game_id text := 'dung_dodge_v2';
  viewer uuid := '61000000-0000-4000-8000-000000000001';
  started_user uuid := '61000000-0000-4000-8000-000000000002';
  issued_user uuid := '61000000-0000-4000-8000-000000000003';
  preview_user uuid := '61000000-0000-4000-8000-000000000004';
  score_only_user uuid := '61000000-0000-4000-8000-000000000005';
  blocked_user uuid := '61000000-0000-4000-8000-000000000006';
  test_user uuid := '61000000-0000-4000-8000-000000000007';
  anonymous_name_user uuid := '61000000-0000-4000-8000-000000000008';
  blank_name_user uuid := '61000000-0000-4000-8000-000000000009';
  page_user_a uuid := '61000000-0000-4000-8000-00000000000a';
  page_user_b uuid := '61000000-0000-4000-8000-00000000000b';
  page_user_c uuid := '61000000-0000-4000-8000-00000000000c';
  started_session uuid := '62000000-0000-4000-8000-000000000001';
  issued_session uuid := '62000000-0000-4000-8000-000000000002';
  preview_session uuid := '62000000-0000-4000-8000-000000000003';
  score_attempt uuid := '63000000-0000-4000-8000-000000000001';
  response jsonb;
  preview_response jsonb;
  page_one jsonb;
  page_two jsonb;
  next_cursor text;
begin
  perform set_config(
    'request.headers',
    '{"x-app-build":"27","x-app-platform":"ios"}',
    true
  );

  insert into auth.users(id, is_anonymous) values
    (viewer, true),
    (started_user, true),
    (issued_user, true),
    (preview_user, true),
    (score_only_user, true),
    (blocked_user, true),
    (test_user, true),
    (anonymous_name_user, true),
    (blank_name_user, true),
    (page_user_a, true),
    (page_user_b, true),
    (page_user_c, true);

  update public.profiles
  set nickname = case id
    when viewer then '조회자'
    when started_user then '이미 시작함'
    when issued_user then '발급만 받음'
    when preview_user then '내일 연습중'
    when score_only_user then '점수만 있음'
    when blocked_user then '차단된 유저'
    when test_user then '테스트 유저'
    when anonymous_name_user then '신원미상#123'
    when blank_name_user then '   '
    when page_user_a then '페이지 사용자 A'
    when page_user_b then '페이지 사용자 B'
    when page_user_c then '페이지 사용자 C'
  end,
  is_test_account = id = test_user,
  experience_points = case when id = page_user_b then 900 else 0 end,
  nickname_color = case when id = page_user_b then 'mint' else 'default' end
  where id in (
    viewer, started_user, issued_user, preview_user, score_only_user,
    blocked_user, test_user, anonymous_name_user, blank_name_user,
    page_user_a, page_user_b, page_user_c
  );

  insert into public.daily_play_sessions(
    id, user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds, started_at,
    target_game_date
  ) values
    (
      started_session, started_user, play_day, 1, 'practice', null,
      game_id, 1, 300, now(), play_day
    ),
    (
      issued_session, issued_user, play_day, 1, 'practice', null,
      game_id, 1, 300, null, play_day
    ),
    (
      preview_session, preview_user, play_day, 1, 'practice', null,
      game_id, 1, 300, now(), preview_day
    );

  insert into public.attempts(
    id, user_id, play_date, game_id, game_version, ordinal,
    grant_type, status, game_duration_seconds
  ) values (
    score_attempt, score_only_user, play_day, game_id, 1, 1,
    'daily', 'submitted', 300
  );

  alter table public.scores disable trigger scores_enforce_daily_deadline;
  insert into public.scores(
    attempt_id, user_id, play_date, game_id, game_version,
    raw_score, duration_ms, submitted_at
  ) values (
    score_attempt, score_only_user, play_day, game_id, 1,
    1234, 1000, now()
  );
  alter table public.scores enable trigger scores_enforce_daily_deadline;

  insert into public.blocked_profiles(blocker_id, blocked_id)
  values (viewer, blocked_user);

  perform set_config('request.jwt.claim.sub', viewer::text, true);
  response := public.get_daily_nonplayers(play_day, game_id);

  if response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', started_user::text
  )) then
    raise exception 'started user was returned: %', response;
  end if;
  if response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', preview_user::text
  )) is false then
    raise exception 'preview target session was not treated as a nonplayer for today: %', response;
  end if;
  if response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', score_only_user::text
  )) then
    raise exception 'score-only user was returned: %', response;
  end if;
  if response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', issued_user::text
  )) is false then
    raise exception 'issued-only user was not returned: %', response;
  end if;
  preview_response := public.get_daily_nonplayers(preview_day, game_id);
  if preview_response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', preview_user::text
  )) then
    raise exception 'preview target session was returned for its target date: %', preview_response;
  end if;
  if response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', viewer::text
  )) then
    raise exception 'viewer was returned: %', response;
  end if;
  if response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', blocked_user::text
  )) then
    raise exception 'blocked user was returned: %', response;
  end if;
  if response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', test_user::text
  )) then
    raise exception 'test user was returned: %', response;
  end if;
  if response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', anonymous_name_user::text
  )) then
    raise exception 'generated anonymous nickname was returned: %', response;
  end if;
  if response->'players' @> jsonb_build_array(jsonb_build_object(
    'user_id', blank_name_user::text
  )) then
    raise exception 'blank nickname was returned: %', response;
  end if;

  page_one := public.get_daily_nonplayers(
    play_day, game_id, page_user_a, 1
  );
  next_cursor := page_one->>'next_cursor';
  if jsonb_array_length(page_one->'players') <> 1
    or page_one->'players'->0->>'user_id' <> page_user_b::text
    or next_cursor <> page_user_b::text then
    raise exception 'pagination did not return the first row and cursor: %', page_one;
  end if;
  page_two := public.get_daily_nonplayers(
    play_day, game_id, next_cursor::uuid, 1
  );
  if jsonb_array_length(page_two->'players') <> 1
    or page_two->'players'->0->>'user_id' <> page_user_c::text
    or page_two->>'next_cursor' is not null then
    raise exception 'cursor skipped or repeated a row: page one %, page two %', page_one, page_two;
  end if;
end;
$$;

select pass('daily nonplayers filters and paginates correctly');
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_daily_nonplayers(date,text,uuid,integer)',
    'execute'
  ),
  'authenticated role can execute daily nonplayers RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_daily_nonplayers(date,text,uuid,integer)',
    'execute'
  ),
  'anon role cannot execute daily nonplayers RPC'
);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$ select public.get_daily_nonplayers(
    public.current_play_date(), 'dung_dodge_v2'
  ) $$,
  'P0001',
  'authentication required',
  'unauthenticated callers are rejected'
);

select * from finish();

rollback;

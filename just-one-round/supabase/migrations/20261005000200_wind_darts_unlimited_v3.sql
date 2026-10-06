-- Wind darts v3 keeps the shared 75-second catalog/session metadata for
-- compatibility, but removes the player-facing runtime and submit upper
-- bound. New attempts use six throws and version-scoped opponents. v1/v2
-- attempts, records, queued submissions, and their 75-second validation stay
-- valid through the same RPCs.

insert into public.games (
  id, version, display_name, description, duration_seconds,
  is_active, minimum_app_build
) values (
  'wind_darts', 3, '펍 다트',
  '시간 제한 없이 12방향 바람과 흔들리는 조준점을 읽고 여섯 발의 기록을 겨루세요.',
  75, false, 27
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  -- Publishing remains an operator decision; this migration only selects the
  -- new version for new test-account attempts.
  is_active = public.games.is_active,
  minimum_app_build = excluded.minimum_app_build;

create or replace function public.claim_test_wind_darts_attempt_v3(
  expected_play_date date
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  selected_game public.game_rule_versions;
  existing_attempt public.attempts;
  claimed_attempt public.attempts;
  next_ordinal smallint;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if not exists (
    select 1
    from public.profiles profile
    where profile.id = current_user_id
      and profile.is_test_account
      and profile.test_game_id = 'wind_darts'
  ) then
    raise exception 'wind darts test selection required';
  end if;

  select versioned.*
  into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = 'wind_darts'
    and versioned.version = 3;
  if selected_game.game_id is null then
    raise exception 'wind darts v3 catalog entry not found';
  end if;

  -- A lost claim response is safe to retry before a start session exists.
  select attempt.*
  into existing_attempt
  from public.attempts attempt
  where attempt.user_id = current_user_id
    and attempt.play_date = play_day
    and attempt.game_id = 'wind_darts'
    and attempt.game_version = 3
    and attempt.status = 'issued'
    and not exists (
      select 1
      from public.daily_play_sessions session
      where session.attempt_id = attempt.id
    )
  order by attempt.ordinal desc, attempt.issued_at desc
  limit 1;
  if existing_attempt.id is not null then
    return existing_attempt;
  end if;

  select (coalesce(max(attempt.ordinal), 0) + 1)::smallint
  into next_ordinal
  from public.attempts attempt
  where attempt.user_id = current_user_id
    and attempt.play_date = play_day;

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type, issued_at
  ) values (
    current_user_id, play_day, selected_game.game_id, selected_game.version,
    next_ordinal, 'daily', now()
  ) returning * into claimed_attempt;
  return claimed_attempt;
end;
$$;

revoke all on function public.claim_test_wind_darts_attempt_v3(date)
  from public, anon, authenticated, service_role;

-- Keep the v1/v2 claim wrapper available as the fallback for every other
-- game, but route a fresh selected wind-darts test attempt to v3.
alter function public.claim_daily_attempt(date)
rename to claim_daily_attempt_before_wind_darts_v3;

create function public.claim_daily_attempt(
  expected_play_date date
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  is_test boolean := false;
  selected_test_game_id text;
  existing_attempt public.attempts;
  claimed_attempt public.attempts;
  selected_game public.game_rule_versions;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  select coalesce(profile.is_test_account, false), profile.test_game_id
  into is_test, selected_test_game_id
  from public.profiles profile
  where profile.id = current_user_id;

  if is_test and selected_test_game_id = 'wind_darts' then
    perform pg_advisory_xact_lock(
      hashtext(current_user_id::text), hashtext(play_day::text)
    );

    -- Preserve a pending start from v1/v2/v3 rather than issuing a second
    -- attempt while a client is retrying its queued start request.
    select attempt.*
    into existing_attempt
    from public.daily_play_sessions session
    join public.attempts attempt on attempt.id = session.attempt_id
    where session.user_id = current_user_id
      and session.play_date = play_day
      and session.play_mode = 'challenge'
      and session.started_at is null
      and attempt.status = 'issued'
    order by session.created_at desc, session.id desc
    limit 1;
    if existing_attempt.id is not null then
      return existing_attempt;
    end if;

    -- Recover a pre-migration issued attempt without rewriting its version.
    select attempt.*
    into existing_attempt
    from public.attempts attempt
    where attempt.user_id = current_user_id
      and attempt.play_date = play_day
      and attempt.status = 'issued'
      and not exists (
        select 1
        from public.daily_play_sessions session
        where session.attempt_id = attempt.id
      )
    order by attempt.ordinal desc, attempt.issued_at desc
    limit 1;
    if existing_attempt.id is not null then
      return existing_attempt;
    end if;

    claimed_attempt := public.claim_test_wind_darts_attempt_v3(
      expected_play_date
    );
    select versioned.*
    into selected_game
    from public.game_rule_versions versioned
    where versioned.game_id = claimed_attempt.game_id
      and versioned.version = claimed_attempt.game_version;
    if selected_game.game_id is null then
      raise exception 'game version not found';
    end if;

    insert into public.daily_play_sessions (
      user_id, play_date, ordinal, play_mode, attempt_id, game_id,
      game_version, game_duration_seconds, created_at
    ) values (
      current_user_id, play_day, claimed_attempt.ordinal, 'challenge',
      claimed_attempt.id, claimed_attempt.game_id, claimed_attempt.game_version,
      selected_game.duration_seconds, claimed_attempt.issued_at
    ) on conflict (attempt_id) do nothing;
    return claimed_attempt;
  end if;

  return public.claim_daily_attempt_before_wind_darts_v3(expected_play_date);
end;
$$;

revoke all on function public.claim_daily_attempt_before_wind_darts_v3(date)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_daily_attempt(date) from public;
grant execute on function public.claim_daily_attempt(date) to authenticated;

-- Expose the current v3 catalog to the selected test account while keeping
-- the previous state wrapper as the compatibility fallback.
alter function public.get_today_state()
rename to get_today_state_before_wind_darts_v3;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_wind_darts_v3();
  current_user_id uuid := (select auth.uid());
  selected_game public.game_rule_versions;
begin
  select versioned.*
  into selected_game
  from public.game_rule_versions versioned
  join public.games game
    on game.id = versioned.game_id and game.version = versioned.version
  join public.profiles profile
    on profile.id = current_user_id
  where profile.is_test_account
    and profile.test_game_id = 'wind_darts'
    and versioned.game_id = 'wind_darts'
    and versioned.version = 3;

  if selected_game.game_id is not null then
    state := jsonb_set(
      state,
      '{game}',
      jsonb_build_object(
        'id', selected_game.game_id,
        'version', selected_game.version,
        'display_name', selected_game.display_name,
        'description', selected_game.description,
        'duration_seconds', selected_game.duration_seconds
      ),
      true
    );
  end if;
  return state;
end;
$$;

revoke all on function public.get_today_state_before_wind_darts_v3()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

create or replace function public.confirm_wind_darts_started(
  play_reference_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  target_session public.daily_play_sessions;
  existing public.wind_darts_opponents;
  selected record;
  personal_best integer;
  shot_count integer;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into target_session
  from public.daily_play_sessions session
  where session.user_id = current_user_id
    and session.play_date = public.current_play_date()
    and (session.id = play_reference_id or session.attempt_id = play_reference_id)
  for update;
  if target_session.id is null
    or target_session.game_id <> 'wind_darts'
    or target_session.game_version not in (1, 2, 3) then
    raise exception 'wind darts session not found';
  end if;
  shot_count := case when target_session.game_version = 1 then 5 else 6 end;

  select * into existing
  from public.wind_darts_opponents
  where session_id = target_session.id;
  if existing.session_id is not null then
    return jsonb_build_object(
      'nickname', existing.nickname,
      'shot_scores', to_jsonb(existing.shot_scores),
      'is_bot', existing.is_bot,
      'game_version', target_session.game_version
    );
  end if;

  perform public.confirm_daily_play_started(play_reference_id);
  select coalesce(max(record.total_score), 0)::integer
  into personal_best
  from public.wind_darts_shot_records record
  join public.attempts attempt on attempt.id = record.attempt_id
  where record.user_id = current_user_id
    and attempt.game_id = 'wind_darts'
    and (
      attempt.game_version = target_session.game_version
      or (
        target_session.game_version = 3
        and attempt.game_version in (1, 2, 3)
      )
    );

  select best.user_id, best.attempt_id, best.total_score, best.shot_scores,
         profile.nickname
  into selected
  from (
    select distinct on (score.user_id)
      score.user_id, score.attempt_id, shots.total_score, shots.shot_scores,
      score.submitted_at
    from public.scores score
    join public.wind_darts_shot_records shots
      on shots.attempt_id = score.attempt_id
    join public.attempts attempt on attempt.id = shots.attempt_id
    join public.profiles profile on profile.id = score.user_id
    where score.game_id = 'wind_darts'
      and score.game_version = target_session.game_version
      and attempt.game_id = 'wind_darts'
      and attempt.game_version = target_session.game_version
      and shots.total_score > personal_best
      and score.user_id <> current_user_id
      and not coalesce(profile.is_test_account, false)
    order by score.user_id, shots.total_score desc, score.submitted_at asc
  ) best
  join public.profiles profile on profile.id = best.user_id
  order by random()
  limit 1;

  if selected.user_id is null then
    insert into public.wind_darts_opponents(
      session_id, nickname, shot_scores, total_score, is_bot
    ) values (
      target_session.id, '펍의 단골',
      array_fill(60::smallint, array[shot_count]),
      60 * shot_count, true
    ) returning * into existing;
  else
    insert into public.wind_darts_opponents(
      session_id, nickname, shot_scores, total_score, is_bot,
      source_user_id, source_attempt_id
    ) values (
      target_session.id, coalesce(selected.nickname, '이름 없는 단골'),
      selected.shot_scores, selected.total_score, false,
      selected.user_id, selected.attempt_id
    ) returning * into existing;
  end if;

  return jsonb_build_object(
    'nickname', existing.nickname,
    'shot_scores', to_jsonb(existing.shot_scores),
    'is_bot', existing.is_bot,
    'game_version', target_session.game_version
  );
end;
$$;

revoke all on function public.confirm_wind_darts_started(uuid) from public, anon;
grant execute on function public.confirm_wind_darts_started(uuid) to authenticated;

create or replace function public.submit_wind_darts_score(
  attempt_id uuid,
  shot_scores smallint[],
  duration_ms integer
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  active_attempt public.attempts;
  target_session public.daily_play_sessions;
  shot_count integer;
  maximum_score integer;
  total_score integer;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  select * into active_attempt from public.attempts
  where id = attempt_id and user_id = current_user_id for update;
  if active_attempt.id is null then raise exception 'attempt not found'; end if;

  -- Idempotency must be checked before any version or duration validation so
  -- a queued retry of an already accepted v1/v2/v3 result is harmless.
  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued'
    or active_attempt.game_id <> 'wind_darts'
    or active_attempt.game_version not in (1, 2, 3) then
    raise exception 'active wind darts attempt not found';
  end if;

  shot_count := case when active_attempt.game_version = 1 then 5 else 6 end;
  maximum_score := 60 * shot_count;
  select * into target_session
  from public.daily_play_sessions session
  where session.attempt_id = active_attempt.id
    and session.user_id = current_user_id
    and session.play_mode = 'challenge'
    and session.game_id = 'wind_darts'
    and session.game_version = active_attempt.game_version
    and session.game_duration_seconds = 75
    and session.started_at is not null
  for update;
  if target_session.id is null then
    raise exception 'wind darts game was not started';
  end if;
  if not exists (
    select 1 from public.wind_darts_opponents opponent
    where opponent.session_id = target_session.id
  ) then
    raise exception 'wind darts opponent was not assigned';
  end if;

  -- PostgreSQL CHECK expressions accept NULL as unknown, so reject every
  -- malformed array explicitly before cardinality or unnest is evaluated.
  if shot_scores is null
    or array_ndims(shot_scores) is distinct from 1
    or cardinality(shot_scores) is null
    or cardinality(shot_scores) <> shot_count
    or array_lower(shot_scores, 1) is distinct from 1
    or array_upper(shot_scores, 1) is distinct from cardinality(shot_scores)
    or array_position(shot_scores, null::smallint) is not null then
    raise exception 'exactly % one-dimensional shot scores are required', shot_count;
  end if;

  if exists (
    select 1
    from unnest(shot_scores) score
    where (
      active_attempt.game_version = 1
      and score not in (0, 25, 50)
      and not (score between 1 and 20)
      and not (score between 2 and 40 and score % 2 = 0)
      and not (score between 3 and 60 and score % 3 = 0)
    ) or (
      active_attempt.game_version in (2, 3)
      and score not in (0, 50)
      and not (score between 1 and 20)
      and not (score between 2 and 40 and score % 2 = 0)
      and not (score between 3 and 60 and score % 3 = 0)
    )
  ) then
    raise exception 'invalid dart score';
  end if;

  total_score := (
    select coalesce(sum(value), 0)::integer
    from unnest(shot_scores) value
  );
  if total_score not between 0 and maximum_score then
    raise exception 'invalid wind darts result';
  end if;

  if active_attempt.game_version = 3 then
    -- v3 has no upper bound: duration is the actual positive elapsed time,
    -- with the same 8-second minimum used to reject impossible submissions.
    if duration_ms is null or duration_ms < 8000 then
      raise exception 'invalid wind darts result';
    end if;
  else
    if duration_ms is null or duration_ms not between 8000 and 75100 then
      raise exception 'invalid wind darts result';
    end if;
    -- Preserve the one queued 100ms frame tolerance for v1/v2 retries.
    duration_ms := least(duration_ms, 75000);
  end if;
  perform public.assert_score_submission_elapsed(active_attempt.issued_at, duration_ms);

  insert into public.wind_darts_shot_records(
    attempt_id, user_id, shot_scores, total_score
  ) values (active_attempt.id, current_user_id, shot_scores, total_score);
  insert into public.scores (
    attempt_id, user_id, play_date, game_id, game_version,
    raw_score, duration_ms
  ) values (
    active_attempt.id, current_user_id, active_attempt.play_date,
    active_attempt.game_id, active_attempt.game_version,
    total_score, duration_ms
  );
  update public.attempts set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;
  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

revoke all on function public.submit_wind_darts_score(uuid, smallint[], integer)
  from public, anon;
grant execute on function public.submit_wind_darts_score(uuid, smallint[], integer)
  to authenticated;

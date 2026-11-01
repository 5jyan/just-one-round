-- Wind darts v4 adds an outer 25-point bull, keeps the inner 50-point bull,
-- and makes the seventh dart golden (double its normal score). Existing
-- attempts remain bound to their original immutable rule version.

insert into public.games (
  id, version, display_name, description, duration_seconds,
  is_active, minimum_app_build
) values (
  'wind_darts', 4, '펍 다트',
  '시간 제한 없이 일곱 발을 던지세요. 중앙 불은 50점, 바깥 불은 25점이며 마지막 황금 다트는 2배 점수입니다.',
  75, false, 27
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  is_active = public.games.is_active,
  minimum_app_build = excluded.minimum_app_build;

alter table public.wind_darts_shot_records
  drop constraint if exists wind_darts_shot_records_shot_scores_check,
  drop constraint if exists wind_darts_shot_records_total_score_check;

alter table public.wind_darts_shot_records
  add constraint wind_darts_shot_records_shot_scores_check check (
    (
      shot_scores is not null
      and array_ndims(shot_scores) = 1
      and cardinality(shot_scores) in (5, 6, 7)
      and array_lower(shot_scores, 1) = 1
      and array_upper(shot_scores, 1) = cardinality(shot_scores)
      and array_position(shot_scores, null::smallint) is null
    ) is true
  ),
  add constraint wind_darts_shot_records_total_score_check check (
    (
      total_score is not null
      and total_score between 0 and case
        when cardinality(shot_scores) = 7 then 480
        else 60 * cardinality(shot_scores)
      end
    ) is true
  );

alter table public.wind_darts_opponents
  drop constraint if exists wind_darts_opponents_shot_scores_check,
  drop constraint if exists wind_darts_opponents_total_score_check;

alter table public.wind_darts_opponents
  add constraint wind_darts_opponents_shot_scores_check check (
    (
      shot_scores is not null
      and array_ndims(shot_scores) = 1
      and cardinality(shot_scores) in (5, 6, 7)
      and array_lower(shot_scores, 1) = 1
      and array_upper(shot_scores, 1) = cardinality(shot_scores)
      and array_position(shot_scores, null::smallint) is null
    ) is true
  ),
  add constraint wind_darts_opponents_total_score_check check (
    (
      total_score is not null
      and total_score between 0 and case
        when cardinality(shot_scores) = 7 then 480
        else 60 * cardinality(shot_scores)
      end
    ) is true
  );

-- The v3 routing wrapper calls this helper by its historical name. New claims
-- use v4, while its generic pending-attempt recovery preserves existing v1-v3.
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
    select 1 from public.profiles profile
    where profile.id = current_user_id
      and profile.is_test_account
      and profile.test_game_id = 'wind_darts'
  ) then
    raise exception 'wind darts test selection required';
  end if;

  select versioned.* into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = 'wind_darts' and versioned.version = 4;
  if selected_game.game_id is null then
    raise exception 'wind darts v4 catalog entry not found';
  end if;

  select attempt.* into existing_attempt
  from public.attempts attempt
  where attempt.user_id = current_user_id
    and attempt.play_date = play_day
    and attempt.game_id = 'wind_darts'
    and attempt.game_version = 4
    and attempt.status = 'issued'
    and not exists (
      select 1 from public.daily_play_sessions session
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
  where attempt.user_id = current_user_id and attempt.play_date = play_day;

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

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_wind_darts_v3();
  current_user_id uuid := (select auth.uid());
  selected_game public.game_rule_versions;
begin
  select versioned.* into selected_game
  from public.game_rule_versions versioned
  join public.games game
    on game.id = versioned.game_id and game.version = versioned.version
  join public.profiles profile on profile.id = current_user_id
  where profile.is_test_account
    and profile.test_game_id = 'wind_darts'
    and versioned.game_id = 'wind_darts'
    and versioned.version = 4;

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
    or target_session.game_version not in (1, 2, 3, 4) then
    raise exception 'wind darts session not found';
  end if;
  shot_count := case
    when target_session.game_version = 1 then 5
    when target_session.game_version = 4 then 7
    else 6
  end;

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
  select coalesce(max(record.total_score), 0)::integer into personal_best
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
      or (
        target_session.game_version = 4
        and attempt.game_version in (1, 2, 3, 4)
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
    if target_session.game_version = 4 then
      insert into public.wind_darts_opponents(
        session_id, nickname, shot_scores, total_score, is_bot
      ) values (
        target_session.id, '펍의 단골',
        array[60,60,60,60,60,60,120]::smallint[], 480, true
      ) returning * into existing;
    else
      insert into public.wind_darts_opponents(
        session_id, nickname, shot_scores, total_score, is_bot
      ) values (
        target_session.id, '펍의 단골',
        array_fill(60::smallint, array[shot_count]), 60 * shot_count, true
      ) returning * into existing;
    end if;
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

  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued'
    or active_attempt.game_id <> 'wind_darts'
    or active_attempt.game_version not in (1, 2, 3, 4) then
    raise exception 'active wind darts attempt not found';
  end if;

  shot_count := case
    when active_attempt.game_version = 1 then 5
    when active_attempt.game_version = 4 then 7
    else 6
  end;
  maximum_score := case when active_attempt.game_version = 4
    then 480 else 60 * shot_count end;
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
    from unnest(shot_scores) with ordinality as dart(score, ordinal)
    where not case
      when active_attempt.game_version = 1 then
        dart.score in (0, 25, 50)
        or dart.score between 1 and 20
        or (dart.score between 2 and 40 and dart.score % 2 = 0)
        or (dart.score between 3 and 60 and dart.score % 3 = 0)
      when active_attempt.game_version in (2, 3) then
        dart.score in (0, 50)
        or dart.score between 1 and 20
        or (dart.score between 2 and 40 and dart.score % 2 = 0)
        or (dart.score between 3 and 60 and dart.score % 3 = 0)
      when active_attempt.game_version = 4 then
        (dart.ordinal <> 7 or dart.score % 2 = 0)
        and (
          case when dart.ordinal = 7 then dart.score / 2 else dart.score end
            in (0, 25, 50)
          or case when dart.ordinal = 7 then dart.score / 2 else dart.score end
            between 1 and 20
          or (
            case when dart.ordinal = 7 then dart.score / 2 else dart.score end
              between 2 and 40
            and (case when dart.ordinal = 7 then dart.score / 2 else dart.score end) % 2 = 0
          )
          or (
            case when dart.ordinal = 7 then dart.score / 2 else dart.score end
              between 3 and 60
            and (case when dart.ordinal = 7 then dart.score / 2 else dart.score end) % 3 = 0
          )
        )
      else false
    end
  ) then
    raise exception 'invalid dart score';
  end if;

  total_score := (
    select coalesce(sum(value), 0)::integer from unnest(shot_scores) value
  );
  if total_score not between 0 and maximum_score then
    raise exception 'invalid wind darts result';
  end if;

  if active_attempt.game_version in (3, 4) then
    if duration_ms is null or duration_ms < 8000 then
      raise exception 'invalid wind darts result';
    end if;
  else
    if duration_ms is null or duration_ms not between 8000 and 75100 then
      raise exception 'invalid wind darts result';
    end if;
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

-- Wind darts keeps each throw alongside the leaderboard score so the exact
-- five-dart opponent can be replayed and compared on every shot.
insert into public.games (
  id, version, display_name, description, duration_seconds,
  is_active, minimum_app_build
) values (
  'wind_darts', 1, '펍 다트',
  '바람과 회전하는 다트판을 읽고 다섯 발의 기록을 겨루세요.',
  75, false, 27
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  is_active = false,
  minimum_app_build = excluded.minimum_app_build;

create table public.wind_darts_shot_records (
  attempt_id uuid primary key references public.attempts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  shot_scores smallint[] not null check (
    cardinality(shot_scores) = 5
    and array_lower(shot_scores, 1) = 1
    and array_upper(shot_scores, 1) = 5
  ),
  total_score smallint not null check (total_score between 0 and 300),
  created_at timestamptz not null default now()
);

create index wind_darts_shot_records_rank_idx
  on public.wind_darts_shot_records(total_score desc, created_at);

alter table public.wind_darts_shot_records enable row level security;
revoke all on table public.wind_darts_shot_records from public, anon, authenticated;

create table public.wind_darts_opponents (
  session_id uuid primary key references public.daily_play_sessions(id) on delete cascade,
  nickname text not null,
  shot_scores smallint[] not null check (cardinality(shot_scores) = 5),
  total_score smallint not null check (total_score between 0 and 300),
  is_bot boolean not null,
  source_user_id uuid references auth.users(id) on delete set null,
  source_attempt_id uuid references public.attempts(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint wind_darts_bot_source check (
    (is_bot and source_user_id is null and source_attempt_id is null)
    or not is_bot
  )
);

alter table public.wind_darts_opponents enable row level security;
revoke all on table public.wind_darts_opponents from public, anon, authenticated;

create function public.confirm_wind_darts_started(play_reference_id uuid)
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
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select * into target_session
  from public.daily_play_sessions session
  where session.user_id = current_user_id
    and session.play_date = public.current_play_date()
    and (session.id = play_reference_id or session.attempt_id = play_reference_id)
  for update;
  if target_session.id is null
    or target_session.game_id <> 'wind_darts'
    or target_session.game_version <> 1 then
    raise exception 'wind darts session not found';
  end if;

  select * into existing from public.wind_darts_opponents
  where session_id = target_session.id;
  if existing.session_id is not null then
    return jsonb_build_object(
      'nickname', existing.nickname,
      'shot_scores', to_jsonb(existing.shot_scores),
      'is_bot', existing.is_bot
    );
  end if;

  perform public.confirm_daily_play_started(play_reference_id);
  select coalesce(max(record.total_score), 0)::integer into personal_best
  from public.wind_darts_shot_records record
  where record.user_id = current_user_id;

  select best.user_id, best.attempt_id, best.total_score, best.shot_scores,
         profile.nickname
  into selected
  from (
    select distinct on (score.user_id)
      score.user_id, score.attempt_id, shots.total_score, shots.shot_scores,
      score.submitted_at
    from public.scores score
    join public.wind_darts_shot_records shots on shots.attempt_id = score.attempt_id
    join public.profiles profile on profile.id = score.user_id
    where score.game_id = 'wind_darts'
      and score.game_version = 1
      and shots.total_score > personal_best
      and score.user_id <> current_user_id
      and not coalesce(profile.is_test_account, false)
    order by score.user_id, shots.total_score desc, score.submitted_at asc
  ) best
  join public.profiles profile on profile.id = best.user_id
  order by random()
  limit 1;

  if selected.user_id is null then
    -- 300 is the game's finite maximum. At a personal best of 300, no higher
    -- legal opponent exists; the perfect bot is the closest possible match.
    insert into public.wind_darts_opponents(
      session_id, nickname, shot_scores, total_score, is_bot
    ) values (
      target_session.id, '펍의 단골', array[60,60,60,60,60]::smallint[], 300, true
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
    'is_bot', existing.is_bot
  );
end;
$$;

revoke all on function public.confirm_wind_darts_started(uuid) from public, anon;
grant execute on function public.confirm_wind_darts_started(uuid) to authenticated;

create function public.submit_wind_darts_score(
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
  total_score integer;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select * into active_attempt from public.attempts
  where id = attempt_id and user_id = current_user_id for update;
  if active_attempt.id is null then raise exception 'attempt not found'; end if;
  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued'
    or active_attempt.game_id <> 'wind_darts'
    or active_attempt.game_version <> 1 then
    raise exception 'active wind darts attempt not found';
  end if;

  select * into target_session from public.daily_play_sessions session
  where session.attempt_id = active_attempt.id
    and session.user_id = current_user_id
    and session.play_mode = 'challenge'
    and session.game_duration_seconds = 75
    and session.started_at is not null
  for update;
  if target_session.id is null then raise exception 'wind darts game was not started'; end if;
  if not exists (
    select 1 from public.wind_darts_opponents opponent
    where opponent.session_id = target_session.id
  ) then raise exception 'wind darts opponent was not assigned'; end if;

  if cardinality(shot_scores) <> 5 or array_lower(shot_scores, 1) <> 1
    or array_upper(shot_scores, 1) <> 5 then
    raise exception 'exactly five shot scores are required';
  end if;
  if exists (
    select 1 from unnest(shot_scores) score
    where score not in (0, 25, 50)
      and not (score between 1 and 20)
      and not (score between 2 and 40 and score % 2 = 0)
      and not (score between 3 and 60 and score % 3 = 0)
  ) then raise exception 'invalid dart score'; end if;

  total_score := (select coalesce(sum(value), 0)::integer from unnest(shot_scores) value);
  if total_score not between 0 and 300
    or duration_ms not between 8000 and 75000 then
    raise exception 'invalid wind darts result';
  end if;
  perform public.assert_score_submission_elapsed(active_attempt.issued_at, duration_ms);

  insert into public.wind_darts_shot_records(attempt_id, user_id, shot_scores, total_score)
  values (active_attempt.id, current_user_id, shot_scores, total_score);
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

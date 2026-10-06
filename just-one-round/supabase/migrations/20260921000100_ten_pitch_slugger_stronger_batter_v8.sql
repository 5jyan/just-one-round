-- 홈런왕 규칙 버전 8: 7구의 강타자는 기존 거리 계산 결과만 1.25배
-- (반올림)하고, 나머지 투구의 판정은 이전 체인을 그대로 위임한다.
--
-- Rollback: 이 migration을 되돌려 과거 migration을 수정하지 않는다. v8이
-- 참조 중이 아닐 때에만 별도 운영 절차로 games.version을 7로 복귀하고,
-- 이 migration이 보존한 submit_daily_score_before_* 함수와 이전 wrapper를
-- 새 forward migration에서 복원한다. v8의 game_rule_versions/attempts/scores
-- 행은 삭제하지 않는다.

insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds,
  is_active,
  minimum_app_build
) values (
  'ten_pitch_slugger',
  8,
  '홈런왕',
  '7구에는 강타자가 등장해 기존 비거리를 1.25배로 키웁니다. 나머지 9구는 점점 빨라지는 공을 받아쳐 최대 비거리를 기록하세요.',
  300,
  true,
  10
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  is_active = excluded.is_active,
  minimum_app_build = excluded.minimum_app_build
where public.games.version < excluded.version;

-- The catalog row is versioned independently from each scheduled snapshot.
-- Only future 홈런왕 rows may move to v8; yesterday and today's snapshots
-- remain immutable and continue to submit against the rules they issued with.
update public.daily_games as scheduled
set game_version = catalog.version
from public.games as catalog
where scheduled.play_date > public.current_play_date()
  and scheduled.game_id = 'ten_pitch_slugger'
  and scheduled.game_id = catalog.id
  and scheduled.game_version is distinct from catalog.version
  and catalog.is_active;

do $$
begin
  if to_regprocedure(
    'public.submit_daily_score(uuid,integer,integer,integer,integer)'
  ) is null
    and to_regprocedure(
      'public.submit_daily_score_before_ten_pitch_slugger_v8(uuid,integer,integer,integer,integer)'
    ) is null then
    raise exception 'submit_daily_score wrapper chain is missing';
  end if;

  -- The guard makes a rerun safe after a partial migration or local reset.
  if to_regprocedure(
    'public.submit_daily_score(uuid,integer,integer,integer,integer)'
  ) is not null
    and to_regprocedure(
      'public.submit_daily_score_before_ten_pitch_slugger_v8(uuid,integer,integer,integer,integer)'
    ) is null then
    alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
      rename to submit_daily_score_before_ten_pitch_slugger_v8;
  end if;
end;
$$;

revoke all on function public.submit_daily_score_before_ten_pitch_slugger_v8(
  uuid, integer, integer, integer, integer
) from public, anon;

create or replace function public.submit_daily_score(
  attempt_id uuid,
  raw_score integer,
  stars_collected integer,
  collisions integer,
  duration_ms integer
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  active_attempt public.attempts;
  scheduled_duration integer;
  submitted_score integer := $2;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id and user_id = current_user_id
  for update;

  if active_attempt is null then raise exception 'attempt not found'; end if;
  -- Match the latest wrapper's early delegation order so v1-v7 and every
  -- non-slugger game execute their established validation exactly once.
  if active_attempt.game_id is distinct from 'ten_pitch_slugger'
    or active_attempt.game_version is distinct from 8 then
    return public.submit_daily_score_before_ten_pitch_slugger_v8(
      attempt_id,
      raw_score,
      stars_collected,
      collisions,
      duration_ms
    );
  end if;

  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued' then raise exception 'active attempt not found'; end if;

  scheduled_duration := active_attempt.game_duration_seconds;
  if scheduled_duration is null then raise exception 'attempt game rules not found'; end if;

  perform public.assert_score_submission_elapsed(
    active_attempt.issued_at,
    duration_ms
  );

  if submitted_score is null
    or stars_collected is null
    or collisions is null
    or duration_ms is null
    or submitted_score not between 0 and 16875
    or stars_collected not between 0 and 10
    or collisions not between 0 and 10
    or stars_collected + collisions <> 10
    or duration_ms not between 25000 and scheduled_duration * 1000
    or (stars_collected = 0 and submitted_score <> 0)
    or (stars_collected > 0 and submitted_score < 3500) then
    raise exception 'invalid ten pitch slugger v8 result';
  end if;

  insert into public.scores (
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values (
    active_attempt.id, current_user_id, active_attempt.play_date,
    active_attempt.game_id, active_attempt.game_version, submitted_score, duration_ms
  );

  update public.attempts
  set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;

  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

revoke all on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  from public, anon;
grant execute on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  to authenticated;

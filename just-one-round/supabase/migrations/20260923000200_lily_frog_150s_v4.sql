-- Publish the 150-second rules as a new immutable game version. Existing
-- issued v3 attempts keep using the v3 validator below this migration.
update public.games
set version = 4,
    duration_seconds = 150,
    description =
      '착지 즉시 다음 점프를 입력하고, 150초 안에 연잎을 건너세요.'
where id = 'lily_frog';

alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
  rename to submit_daily_score_before_lily_frog_v4;

revoke all on function public.submit_daily_score_before_lily_frog_v4(
  uuid, integer, integer, integer, integer
) from public, anon, authenticated;

create function public.submit_daily_score(
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
  submitted_score integer := $2;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id and user_id = current_user_id
  for update;

  if active_attempt is null then raise exception 'attempt not found'; end if;

  -- Keep every non-v4 path on the already deployed validator. This includes
  -- v3 attempts issued before the catalog update and all other games.
  if active_attempt.game_id <> 'lily_frog'
    or active_attempt.game_version <> 4 then
    return public.submit_daily_score_before_lily_frog_v4(
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

  perform public.assert_score_submission_elapsed(
    active_attempt.issued_at,
    duration_ms
  );

  if active_attempt.game_duration_seconds <> 150
    or stars_collected not between 0 and 1000
    or collisions not between 0 and 1
    or duration_ms not between 3000 and 150000
    or (collisions = 0 and duration_ms <> 150000)
    or (collisions = 1 and duration_ms >= 150000)
    or submitted_score not between 0 and 200000
    or submitted_score % 10 <> 0
    or submitted_score < stars_collected * 30 then
    raise exception 'invalid lily frog result';
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

-- Replace the two automatic clock peeks with signed feedback after the first
-- two accepted taps. Scoring, duration, and completion validation are unchanged.
update public.games
set version = 4,
    description =
      '처음 3초로 감각을 익히고, 첫 두 입력의 목표 오차를 보정하며 10초, 20초, 30초를 맞추세요.'
where id = 'ramen_timer';

alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
  rename to submit_daily_score_before_ramen_timer_v4;

revoke all on function public.submit_daily_score_before_ramen_timer_v4(
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
  submitted_score integer := $2;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id and user_id = current_user_id
  for update;

  if active_attempt is null then raise exception 'attempt not found'; end if;

  if active_attempt.game_id is distinct from 'ramen_timer'
    or active_attempt.game_version is distinct from 4 then
    return public.submit_daily_score_before_ramen_timer_v4(
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

  if active_attempt.game_duration_seconds is null
    or active_attempt.game_duration_seconds <> 45
    or submitted_score is null
    or stars_collected is null
    or collisions is null
    or duration_ms is null
    or stars_collected <> 0
    or collisions <> 0
    or not (
      (submitted_score = 0 and duration_ms = 45000)
      or (
        submitted_score between 3525750 and 3600000
        and submitted_score % 10 = 0
        and duration_ms between 3700 and 45000
        and duration_ms % 10 = 0
        and 3600000 - submitted_score >= abs(duration_ms - 30000)
      )
    ) then
    raise exception 'invalid ramen timer result';
  end if;

  if now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts set status = 'expired' where id = active_attempt.id;
    raise exception 'attempt expired';
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

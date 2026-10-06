-- Blackjack v4 guarantees an ace in the player's opening hand on round 7.
-- Existing schedules and attempts keep their original rule-version snapshot.
update public.games
set version = 4,
    description = '딜러 공개 카드를 보고 배팅해 10라운드 동안 코인을 불리세요. 7번째 판에는 시작 카드로 A 한 장을 받습니다.',
    minimum_app_build = 23
where id = 'beat_the_dealer' and version < 4;

update public.daily_games as scheduled
set game_version = 4
where scheduled.play_date > public.current_play_date()
  and scheduled.game_id = 'beat_the_dealer'
  and scheduled.game_version < 4;

alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
  rename to submit_daily_score_before_blackjack_v4;

revoke all on function public.submit_daily_score_before_blackjack_v4(
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
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id and user_id = current_user_id
  for update;

  if active_attempt is null then raise exception 'attempt not found'; end if;

  if active_attempt.game_id is distinct from 'beat_the_dealer'
    or active_attempt.game_version is distinct from 4 then
    return public.submit_daily_score_before_blackjack_v4(
      attempt_id, raw_score, stars_collected, collisions, duration_ms
    );
  end if;

  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued' then raise exception 'active attempt not found'; end if;

  perform public.assert_score_submission_elapsed(active_attempt.issued_at, duration_ms);

  if active_attempt.game_duration_seconds is null
    or active_attempt.game_duration_seconds <> 180
    or raw_score is null
    or stars_collected is null
    or collisions is null
    or duration_ms is null
    or raw_score not between 0 and 925
    or raw_score % 5 <> 0
    or stars_collected <> 0
    or collisions <> 0
    or duration_ms not between 1 and 180000 then
    raise exception 'invalid blackjack v4 result';
  end if;

  if now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts set status = 'expired' where id = active_attempt.id;
    raise exception 'attempt expired';
  end if;

  insert into public.scores (
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values (
    active_attempt.id, current_user_id, active_attempt.play_date,
    active_attempt.game_id, active_attempt.game_version, raw_score, duration_ms
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

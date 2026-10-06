update public.games
set
  version = 2,
  display_name = '만선호',
  description = '빠른 통통배로 위험한 피라냐·청새치·상어·거대 고래를 피해 그물로 둘러싸 잡으세요.',
  duration_seconds = 180
where id = 'net_boat';

alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
  rename to submit_daily_score_before_net_boat_v2;

revoke all on function public.submit_daily_score_before_net_boat_v2(
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

  if active_attempt.game_id <> 'net_boat'
    or active_attempt.game_version <> 2 then
    return public.submit_daily_score_before_net_boat_v2(
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

  if active_attempt.game_duration_seconds <> 180
    or stars_collected <> 0
    or collisions not between 0 and 1
    or duration_ms not between 3000 and 180000
    or (collisions = 0 and duration_ms <> 180000)
    or (collisions = 1 and duration_ms >= 180000)
    or submitted_score not between 0 and 1000000
    or submitted_score % 100 <> 0 then
    raise exception 'invalid net boat v2 result';
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

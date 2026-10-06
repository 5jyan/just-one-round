-- Net Boat v3 extends the playable window to five minutes without adding a
-- fourth difficulty stage or changing the existing whale schedule. Keep the
-- previous wrapper in the delegation chain so historical attempts continue to
-- validate with the rules they were issued under.
update public.games
set
  version = 3,
  display_name = '만선호',
  description = '최대 5분 동안 빠른 통통배로 위험한 생물과 돌 벽을 피해 그물로 둘러싸 잡으세요.',
  duration_seconds = 300
where id = 'net_boat';

alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
  rename to submit_daily_score_before_net_boat_v3;

revoke all on function public.submit_daily_score_before_net_boat_v3(
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

  -- IS DISTINCT FROM is intentional: malformed NULL game metadata must not
  -- fall through into the v3 branch, and all non-v3 attempts must retain the
  -- validator chain that was active when they were issued.
  if active_attempt.game_id is distinct from 'net_boat'
    or active_attempt.game_version is distinct from 3 then
    return public.submit_daily_score_before_net_boat_v3(
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

  -- Every value is checked explicitly before any OR predicate can evaluate to
  -- NULL and bypass the v3 invariants.
  if active_attempt.game_duration_seconds is null
    or active_attempt.game_duration_seconds <> 300
    or submitted_score is null
    or stars_collected is null
    or collisions is null
    or duration_ms is null
    or stars_collected <> 0
    or collisions not between 0 and 1
    or duration_ms not between 3000 and 300000
    or (collisions = 0 and duration_ms <> 300000)
    or (collisions = 1 and duration_ms >= 300000)
    or submitted_score not between 0 and 1000000
    or submitted_score % 10 <> 0 then
    raise exception 'invalid net boat v3 result';
  end if;

  perform public.assert_score_submission_elapsed(
    active_attempt.issued_at,
    duration_ms
  );

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

-- Register the fixed ten-event reaction test. The game is available to the
-- current client build and joins the persisted daily rotation when the next
-- date is allocated.
insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds,
  is_active,
  minimum_app_build
) values (
  'mole_reaction',
  1,
  '두더지 반응속도',
  '1~7초 기다렸다가 나타나는 두더지 10마리를 눌러 가중 반응시간을 줄이세요.',
  180,
  true,
  21
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  is_active = excluded.is_active,
  minimum_app_build = excluded.minimum_app_build;

alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
  rename to submit_daily_score_before_mole_reaction;

revoke all on function public.submit_daily_score_before_mole_reaction(
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

  -- Keep validators for older attempts in their original delegation chain.
  if active_attempt.game_id is distinct from 'mole_reaction'
    or active_attempt.game_version is distinct from 1 then
    return public.submit_daily_score_before_mole_reaction(
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

  -- `raw_score` is the descending leaderboard encoding of the player's total
  -- milliseconds: 1,000,000 - total_ms. A clear run has total_ms >= 11
  -- (nine normal 1ms reactions plus one weighted golden 2ms reaction).
  if active_attempt.game_duration_seconds is null
    or active_attempt.game_duration_seconds <> 180
    or submitted_score is null
    or stars_collected is null
    or collisions is null
    or duration_ms is null
    or stars_collected <> 0
    or collisions not between 0 and 1000
    or duration_ms not between 1 and 180000
    or submitted_score not between 1 and 999989 then
    raise exception 'invalid mole reaction result';
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

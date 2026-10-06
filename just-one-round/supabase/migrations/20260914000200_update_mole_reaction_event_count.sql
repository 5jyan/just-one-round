-- The seven-mole experiment never shipped. Publish the current one-warmup,
-- one-golden rules as a new immutable version instead of editing v1 metadata.
update public.games
set version = 2,
    description =
      '준비 두더지 한 번 뒤 진짜 황금 두더지 한 마리의 반응시간을 줄이세요.',
    minimum_app_build = 25
where id = 'mole_reaction';

-- Future snapshots follow the new rules. Existing snapshots and attempts keep
-- their captured v1 validator and metadata.
update public.daily_games
set game_version = 2
where play_date > public.current_play_date()
  and game_id = 'mole_reaction'
  and game_version < 2;

-- Preserve the deployed v1 validator for old mole attempts and every other
-- game, then add the v2 validator for the current one-warmup/one-golden run.
alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
  rename to submit_daily_score_before_mole_reaction_v2;

revoke all on function public.submit_daily_score_before_mole_reaction_v2(
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

  -- v1 attempts and all non-mole games retain their existing validation chain.
  if active_attempt.game_id is distinct from 'mole_reaction'
    or active_attempt.game_version is distinct from 2 then
    return public.submit_daily_score_before_mole_reaction_v2(
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

  -- The preparation reaction is excluded from the ranked total. A perfect
  -- scored golden reaction is therefore 1ms * 2 = 2ms, encoding to 999,998.
  if active_attempt.game_duration_seconds is null
    or active_attempt.game_duration_seconds <> 180
    or submitted_score is null
    or stars_collected is null
    or collisions is null
    or duration_ms is null
    or stars_collected <> 0
    or collisions not between 0 and 1000
    or duration_ms not between 1 and 180000
    or submitted_score not between 1 and 999998 then
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

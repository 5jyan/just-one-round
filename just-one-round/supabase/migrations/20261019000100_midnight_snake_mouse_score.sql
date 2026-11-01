-- Mouse pickups now award three points. Keep v3's immutable game version and
-- widen only its validated maximum to match the client rules.
do $$
begin
  if to_regprocedure(
    'public.submit_daily_score(uuid,integer,integer,integer,integer)'
  ) is null
    and to_regprocedure(
      'public.submit_daily_score_before_midnight_snake_mouse_score(uuid,integer,integer,integer,integer)'
    ) is null then
    raise exception 'submit_daily_score wrapper chain is missing';
  end if;

  -- Preserve the latest shared validator chain when this migration is rerun.
  if to_regprocedure(
    'public.submit_daily_score(uuid,integer,integer,integer,integer)'
  ) is not null
    and to_regprocedure(
      'public.submit_daily_score_before_midnight_snake_mouse_score(uuid,integer,integer,integer,integer)'
    ) is null then
    alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
      rename to submit_daily_score_before_midnight_snake_mouse_score;
  end if;
end;
$$;

revoke all on function public.submit_daily_score_before_midnight_snake_mouse_score(
  uuid, integer, integer, integer, integer
) from public, anon, authenticated;

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

  -- Preserve every older game and version validator in the existing chain.
  if active_attempt.game_id is distinct from 'midnight_snake'
    or active_attempt.game_version is distinct from 3 then
    return public.submit_daily_score_before_midnight_snake_mouse_score(
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
    or active_attempt.game_duration_seconds <> 300
    or submitted_score not between 0 and 149
    or stars_collected <> 0
    or collisions not in (0, 1)
    or duration_ms not between 1 and 300000 then
    raise exception 'invalid midnight snake result';
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

revoke all on function public.submit_daily_score(
  uuid, integer, integer, integer, integer
) from public, anon;
grant execute on function public.submit_daily_score(
  uuid, integer, integer, integer, integer
) to authenticated;

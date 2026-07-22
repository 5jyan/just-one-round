create or replace function public.submit_daily_score(
  attempt_id uuid,
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
  official_score bigint;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id
    and user_id = current_user_id
  for update;

  if active_attempt is null then
    raise exception 'attempt not found';
  end if;

  -- A client may lose the response after the score has already been written.
  -- Returning the existing daily result makes retrying this same attempt safe.
  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;

  if active_attempt.status <> 'issued' then
    raise exception 'active attempt not found';
  end if;

  select duration_seconds into scheduled_duration
  from public.games
  where id = active_attempt.game_id
    and version = active_attempt.game_version;

  if stars_collected not between 0 and 200
    or collisions not between 0 and 200 then
    raise exception 'invalid game counters';
  end if;

  if duration_ms < (scheduled_duration * 1000 - 2000)
    or duration_ms > (scheduled_duration * 1000 + 10000) then
    raise exception 'invalid game duration';
  end if;

  if now() < active_attempt.issued_at
      + make_interval(secs => greatest(1, scheduled_duration - 2)) then
    raise exception 'game finished too quickly';
  end if;

  if now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts set status = 'expired'
    where id = active_attempt.id;
    raise exception 'attempt expired';
  end if;

  official_score := greatest(
    0,
    stars_collected * 100
      + floor(duration_ms / 1000.0)::integer * 10
      - collisions * 50
  );

  insert into public.scores (
    attempt_id, user_id, play_date, game_id, game_version, raw_score,
    duration_ms, stars_collected, collisions
  ) values (
    active_attempt.id, current_user_id, active_attempt.play_date,
    active_attempt.game_id, active_attempt.game_version, official_score,
    duration_ms, stars_collected, collisions
  );

  update public.attempts
  set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;

  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

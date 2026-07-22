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
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select * into active_attempt from public.attempts
  where id = attempt_id and user_id = current_user_id for update;
  if active_attempt is null then raise exception 'attempt not found'; end if;
  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued' then raise exception 'active attempt not found'; end if;
  select duration_seconds into scheduled_duration from public.games
  where id = active_attempt.game_id and version = active_attempt.game_version;
  if stars_collected <> 0 or collisions not in (0, 1)
    or duration_ms not between 1 and scheduled_duration * 1000 then
    raise exception 'invalid survival result';
  end if;
  if now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts set status = 'expired' where id = active_attempt.id;
    raise exception 'attempt expired';
  end if;
  insert into public.scores (
    attempt_id, user_id, play_date, game_id, game_version, raw_score,
    duration_ms, stars_collected, collisions
  ) values (
    active_attempt.id, current_user_id, active_attempt.play_date,
    active_attempt.game_id, active_attempt.game_version, duration_ms,
    duration_ms, 0, collisions
  );
  update public.attempts set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;
  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

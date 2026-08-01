-- A completed game result may be delivered after a long offline period. The
-- attempt identity and per-game result contract are sufficient to validate an
-- issued attempt, so do not discard an otherwise valid score based on wall
-- clock time or because the game was deactivated after the attempt was issued.
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
  scheduled_duration integer;
  submitted_score integer := $2;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id and user_id = current_user_id
  for update;

  if active_attempt is null then raise exception 'attempt not found'; end if;
  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued' then raise exception 'active attempt not found'; end if;

  select duration_seconds into scheduled_duration
  from public.games
  where id = active_attempt.game_id
    and version = active_attempt.game_version;
  if scheduled_duration is null then raise exception 'game version not found'; end if;

  case active_attempt.game_id
    when 'dung_dodge_v2' then
      if submitted_score <> duration_ms or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid dung dodge v2 result';
      end if;
    when 'gravity_switch' then
      if submitted_score <> duration_ms or stars_collected <> 0
        or duration_ms not between 1 and scheduled_duration * 1000
        or not (
          collisions = 1
          or (collisions = 0 and duration_ms = scheduled_duration * 1000)
        ) then
        raise exception 'invalid gravity switch result';
      end if;
    when 'apple_game_v2' then
      if submitted_score not between 0 and 104 or stars_collected <> 0
        or collisions <> 0
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid apple game v2 result';
      end if;
    when 'number_rush' then
      if stars_collected <> 0
        or duration_ms not between 1 and scheduled_duration * 1000
        or not (
          (collisions = 0 and submitted_score = 3600000 - duration_ms
            and submitted_score between
              3600000 - scheduled_duration * 1000 and 3599999)
          or (collisions = 1 and submitted_score = 0
            and duration_ms = scheduled_duration * 1000)
        ) then
        raise exception 'invalid number rush result';
      end if;
    when 'mama_duck_trail' then
      if submitted_score not between 0 and 100000
        or stars_collected not between 0 and 100
        or collisions not between 0 and 3
        or duration_ms not between 1 and scheduled_duration * 1000
        or (stars_collected = 0 and submitted_score <> 0)
        or (stars_collected > 0 and submitted_score < 425) then
        raise exception 'invalid mama duck trail result';
      end if;
    when 'sausage_dachshund' then
      if submitted_score not between 0 and 131 or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid sausage dachshund result';
      end if;
    when 'midnight_snake' then
      if active_attempt.game_version <> 2
        or submitted_score not between 0 and 134
        or stars_collected <> 0 or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid midnight snake result';
      end if;
    when 'beat_the_dealer' then
      if active_attempt.game_version <> 3
        or submitted_score not between 0 and 925
        or submitted_score % 5 <> 0
        or stars_collected <> 0 or collisions <> 0
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid beat the dealer result';
      end if;
    else
      raise exception 'unsupported game result';
  end case;

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

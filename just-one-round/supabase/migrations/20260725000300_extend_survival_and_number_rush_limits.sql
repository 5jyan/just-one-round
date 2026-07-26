update public.games
set duration_seconds = 120
where id = 'dung_dodge_v2';

update public.games
set duration_seconds = 180
where id = 'number_rush';

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
  if active_attempt.status <> 'issued' then
    raise exception 'active attempt not found';
  end if;

  select duration_seconds into scheduled_duration
  from public.games
  where id = active_attempt.game_id and version = active_attempt.game_version;

  case active_attempt.game_id
    when 'dung_dodge' then
      if submitted_score <> duration_ms
        or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid dung dodge result';
      end if;
    when 'dung_dodge_v2' then
      if submitted_score <> duration_ms
        or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid dung dodge v2 result';
      end if;
    when 'gravity_switch' then
      if submitted_score <> duration_ms
        or stars_collected <> 0
        or collisions <> 1
        or duration_ms < 1 then
        raise exception 'invalid gravity switch result';
      end if;
    when 'failed_bakery' then
      if submitted_score not between 0 and 999
        or stars_collected not between 0 and submitted_score
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid failed bakery result';
      end if;
    when 'apple_game' then
      if submitted_score not between 0 and 77
        or stars_collected <> 0
        or collisions <> 0
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid apple game result';
      end if;
    when 'apple_game_v2' then
      if submitted_score not between 0 and 77
        or stars_collected <> 0
        or collisions <> 0
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid apple game v2 result';
      end if;
    when 'number_rush' then
      if submitted_score <> 3600000 - duration_ms
        or submitted_score not between
          3600000 - scheduled_duration * 1000 and 3599999
        or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid number rush result';
      end if;
    else
      raise exception 'unsupported game result';
  end case;

  if active_attempt.game_id <> 'gravity_switch'
    and now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts set status = 'expired' where id = active_attempt.id;
    raise exception 'attempt expired';
  end if;

  insert into public.scores (
    attempt_id,
    user_id,
    play_date,
    game_id,
    game_version,
    raw_score,
    duration_ms,
    stars_collected,
    collisions
  ) values (
    active_attempt.id,
    current_user_id,
    active_attempt.play_date,
    active_attempt.game_id,
    active_attempt.game_version,
    submitted_score,
    duration_ms,
    stars_collected,
    collisions
  );

  update public.attempts
  set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;

  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

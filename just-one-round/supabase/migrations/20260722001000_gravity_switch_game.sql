insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds,
  is_active
) values (
  'gravity_switch',
  1,
  '뒤집어! 공룡',
  '화면을 탭해 중력을 뒤집고 바닥과 천장의 장애물을 피해 오래 살아남으세요.',
  180,
  true
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  is_active = excluded.is_active;

alter table public.scores
  drop constraint scores_duration_range,
  add constraint scores_duration_range
    check (duration_ms between 0 and 600000);

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
      if stars_collected <> 0 or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid dung dodge result';
      end if;
    when 'gravity_switch' then
      if stars_collected <> 0 or collisions <> 1
        or duration_ms not between 1 and 600000 then
        raise exception 'invalid gravity switch result';
      end if;
    else
      raise exception 'unsupported game result';
  end case;

  if now() > active_attempt.issued_at + interval '10 minutes' then
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
    duration_ms,
    duration_ms,
    0,
    collisions
  );

  update public.attempts
  set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;

  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

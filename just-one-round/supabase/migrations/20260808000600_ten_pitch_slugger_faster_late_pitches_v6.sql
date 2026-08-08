insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds,
  is_active,
  minimum_app_build
) values (
  'ten_pitch_slugger',
  6,
  '딱! 10구',
  '점점 빨라지는 10구를 받아쳐 최대 비거리를 기록하세요. 뒤로 갈수록 같은 정타도 더 멀리 갑니다.',
  300,
  true,
  10
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  is_active = excluded.is_active,
  minimum_app_build = excluded.minimum_app_build;

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

  scheduled_duration := active_attempt.game_duration_seconds;
  if scheduled_duration is null then raise exception 'attempt game rules not found'; end if;

  perform public.assert_score_submission_elapsed(
    active_attempt.issued_at,
    duration_ms
  );

  case active_attempt.game_id
    when 'dung_dodge_v2' then
      if submitted_score <> duration_ms or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000
        or (collisions = 0 and duration_ms <> scheduled_duration * 1000) then
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
        or duration_ms < scheduled_duration * 1000 - 2000
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid apple game v2 result';
      end if;
    when 'number_rush' then
      if stars_collected <> 0
        or duration_ms not between 1 and scheduled_duration * 1000
        or not (
          (collisions = 0 and duration_ms >= 3000
            and submitted_score = 3600000 - duration_ms
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
        or (stars_collected > 0
          and submitted_score < public.minimum_mama_duck_score(stars_collected)) then
        raise exception 'invalid mama duck trail result';
      end if;
    when 'sausage_dachshund' then
      if submitted_score not between 0 and 131 or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid sausage dachshund result';
      end if;
    when 'midnight_snake' then
      if not (
          (active_attempt.game_version = 1 and submitted_score between 0 and 131)
          or (active_attempt.game_version = 2 and submitted_score between 0 and 134)
        )
        or stars_collected <> 0 or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid midnight snake result';
      end if;
    when 'beat_the_dealer' then
      if not (
          (active_attempt.game_version = 1 and submitted_score between 0 and 500)
          or (active_attempt.game_version = 2 and submitted_score between 0 and 700)
          or (active_attempt.game_version = 3 and submitted_score between 0 and 925)
        )
        or submitted_score % 5 <> 0
        or stars_collected <> 0 or collisions <> 0
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid beat the dealer result';
      end if;
    when 'ten_pitch_slugger' then
      if active_attempt.game_version not in (1, 2, 3, 4, 5, 6)
        or stars_collected not between 0 and 10
        or collisions not between 0 and 10
        or stars_collected + collisions <> 10
        or duration_ms not between 25000 and scheduled_duration * 1000
        or (stars_collected = 0 and submitted_score <> 0)
        or (
          active_attempt.game_version = 1
          and (
            submitted_score not between 0 and 127500
            or (stars_collected > 0
              and submitted_score < stars_collected * 3500)
          )
        )
        or (
          active_attempt.game_version in (2, 3, 4, 5, 6)
          and (
            submitted_score not between 0 and 15000
            or (stars_collected > 0 and submitted_score < 3500)
          )
        ) then
        raise exception 'invalid ten pitch slugger result';
      end if;
    when 'ramen_timer' then
      if active_attempt.game_version <> 1
        or scheduled_duration <> 45
        or stars_collected <> 0
        or collisions <> 0
        or not (
          (
            submitted_score = 0
            and duration_ms = 45000
          )
          or (
            submitted_score between 3525750 and 3600000
            and submitted_score % 10 = 0
            and duration_ms between 3700 and 45000
            and duration_ms % 10 = 0
            and 3600000 - submitted_score >= abs(duration_ms - 30000)
          )
        ) then
        raise exception 'invalid ramen timer result';
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

revoke all on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  from public, anon;
grant execute on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  to authenticated;

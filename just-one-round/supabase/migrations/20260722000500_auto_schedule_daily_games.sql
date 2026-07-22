-- The daily game row is a snapshot: once created, later game catalog changes
-- never alter the game that was played on that date.
create or replace function public.ensure_daily_game(target_date date default (now() at time zone 'Asia/Seoul')::date)
returns public.daily_games
language plpgsql
security definer set search_path = ''
as $$
declare
  existing_schedule public.daily_games;
  selected_game public.games;
  active_game_count integer;
begin
  select * into existing_schedule
  from public.daily_games
  where play_date = target_date;

  if existing_schedule is not null then
    return existing_schedule;
  end if;

  select count(*) into active_game_count
  from public.games
  where is_active;

  if active_game_count = 0 then
    raise exception 'no active games available';
  end if;

  select * into selected_game
  from public.games
  where is_active
  order by id
  offset mod(target_date - date '2026-01-01', active_game_count)
  limit 1;

  insert into public.daily_games (play_date, game_id, game_version)
  values (target_date, selected_game.id, selected_game.version)
  on conflict (play_date) do nothing
  returning * into existing_schedule;

  if existing_schedule is null then
    select * into existing_schedule
    from public.daily_games
    where play_date = target_date;
  end if;

  return existing_schedule;
end;
$$;

create or replace function public.claim_daily_attempt()
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  scheduled_game public.daily_games;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  scheduled_game := public.ensure_daily_game(seoul_date);

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type
  ) values (
    current_user_id, seoul_date, scheduled_game.game_id,
    scheduled_game.game_version, 1, 'daily'
  )
  on conflict (user_id, play_date, ordinal)
  do update set user_id = excluded.user_id
  returning * into claimed_attempt;

  return claimed_attempt;
end;
$$;

create or replace function public.claim_rewarded_attempt()
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  first_attempt public.attempts;
  scheduled_game public.daily_games;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into first_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = seoul_date
    and ordinal = 1;

  if first_attempt is null or first_attempt.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;

  scheduled_game := public.ensure_daily_game(seoul_date);

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type
  ) values (
    current_user_id, seoul_date, scheduled_game.game_id,
    scheduled_game.game_version, 2, 'rewarded_ad'
  )
  on conflict (user_id, play_date, ordinal)
  do update set user_id = excluded.user_id
  returning * into claimed_attempt;

  return claimed_attempt;
end;
$$;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
begin
  perform public.ensure_daily_game(seoul_date);

  return (
    with scheduled as (
      select dg.play_date, g.*
      from public.daily_games dg
      join public.games g on g.id = dg.game_id
      where dg.play_date = seoul_date
    ),
    my_attempts as (
      select * from public.attempts
      where user_id = (select auth.uid())
        and play_date = seoul_date
    )
    select jsonb_build_object(
      'play_date', seoul_date,
      'game', (select jsonb_build_object(
        'id', id,
        'version', version,
        'display_name', display_name,
        'description', description,
        'duration_seconds', duration_seconds
      ) from scheduled),
      'attempts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'ordinal', ordinal,
        'status', status,
        'grant_type', grant_type
      ) order by ordinal) from my_attempts), '[]'::jsonb),
      'ad_attempt_available',
        exists (select 1 from my_attempts where ordinal = 1 and status <> 'issued')
        and not exists (select 1 from my_attempts where ordinal = 2),
      'result', public.get_my_daily_result(seoul_date)
    )
  );
end;
$$;

revoke all on function public.ensure_daily_game(date) from public;
grant execute on function public.claim_daily_attempt() to authenticated;
grant execute on function public.claim_rewarded_attempt() to authenticated;
grant execute on function public.get_today_state() to authenticated;

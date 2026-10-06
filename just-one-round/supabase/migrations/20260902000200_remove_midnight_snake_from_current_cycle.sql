-- ensure_daily_game adds newly missing active games to the end of an
-- unfinished cycle. The preceding schedule override intentionally materialized
-- the remaining dates, so remove the snake once more after that materializing
-- step to keep it out of this cycle entirely. It will be eligible again when a
-- new cycle is created.
do $$
declare
  current_cycle_no bigint;
  affected_rows integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('public.ensure_daily_game.rotation')
  );

  if not exists (
    select 1
    from public.daily_games daily
    where daily.play_date = date '2026-09-02'
      and daily.game_id = 'net_boat'
      and daily.game_version = 2
  ) then
    raise exception 'expected net_boat v2 on 2026-09-02';
  end if;

  select state.current_cycle
  into current_cycle_no
  from public.daily_game_rotation_state state
  where state.id
  for update;

  if current_cycle_no is null then
    raise exception 'daily game rotation state is missing';
  end if;

  if exists (
    select 1
    from public.daily_game_rotation_entries entry
    where entry.cycle_no = current_cycle_no
      and entry.game_id = 'midnight_snake'
      and entry.scheduled_date is not null
  ) then
    raise exception
      'midnight_snake is already scheduled in current cycle %',
      current_cycle_no;
  end if;

  delete from public.daily_game_rotation_entries entry
  where entry.cycle_no = current_cycle_no
    and entry.game_id = 'midnight_snake'
    and entry.scheduled_date is null;

  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception
      'expected one pending midnight_snake entry in current cycle %, found %',
      current_cycle_no,
      affected_rows;
  end if;

  if exists (
    select 1
    from public.daily_game_rotation_entries entry
    where entry.cycle_no = current_cycle_no
      and entry.game_id = 'midnight_snake'
  ) then
    raise exception 'midnight_snake remains in current cycle %', current_cycle_no;
  end if;

  if not exists (
    select 1 from public.daily_games
    where play_date = date '2026-09-03'
      and game_id = 'number_rush'
      and game_version = 1
  ) or not exists (
    select 1 from public.daily_games
    where play_date = date '2026-09-04'
      and game_id = 'ramen_timer'
      and game_version = 3
  ) or not exists (
    select 1 from public.daily_games
    where play_date = date '2026-09-05'
      and game_id = 'ten_pitch_slugger'
      and game_version = 7
  ) then
    raise exception 'current-cycle follow-up schedule is incomplete';
  end if;
end;
$$;

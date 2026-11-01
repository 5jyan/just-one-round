-- Start each newly-created cycle with the games whose latest real schedule is
-- oldest. Future schedules are ignored so backfills cannot change the order
-- chosen for an already-known play date.
create or replace function public.ensure_daily_game(
  target_date date default public.current_play_date()
)
returns public.daily_games
language plpgsql
security definer set search_path = ''
as $$
declare
  existing_schedule public.daily_games;
  selected_game public.games;
  selected_entry public.daily_game_rotation_entries;
  current_cycle_no bigint;
  next_position integer;
  minimum_build integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('public.ensure_daily_game.rotation')
  );

  select * into existing_schedule
  from public.daily_games
  where play_date = target_date;

  if existing_schedule is not null then
    return existing_schedule;
  end if;

  select coalesce(config.minimum_supported_build, 1)
  into minimum_build
  from public.app_runtime_config config
  where config.id;
  minimum_build := coalesce(minimum_build, 1);

  if not exists (
    select 1
    from public.games game
    where game.is_active
      and game.minimum_app_build <= minimum_build
  ) then
    raise exception 'no compatible active games available';
  end if;

  select state.current_cycle
  into current_cycle_no
  from public.daily_game_rotation_state state
  where state.id
  for update;

  if current_cycle_no is null then
    raise exception 'daily game rotation state is missing';
  end if;

  -- A newly compatible game joins the end of the unfinished current cycle.
  -- An explicitly skipped entry already exists, so it is not re-added.
  select coalesce(max(entry.position), 0)
  into next_position
  from public.daily_game_rotation_entries entry
  where entry.cycle_no = current_cycle_no;

  insert into public.daily_game_rotation_entries (
    cycle_no,
    game_id,
    position
  )
  select
    current_cycle_no,
    game.id,
    next_position + row_number() over (order by game.id)
  from public.games game
  where game.is_active
    and game.minimum_app_build <= minimum_build
    and not exists (
      select 1
      from public.daily_game_rotation_entries entry
      where entry.cycle_no = current_cycle_no
        and entry.game_id = game.id
    )
  order by game.id;

  select entry.* into selected_entry
  from public.daily_game_rotation_entries entry
  join public.games game on game.id = entry.game_id
  where entry.cycle_no = current_cycle_no
    and entry.scheduled_date is null
    and not entry.is_skipped
    and game.is_active
    and game.minimum_app_build <= minimum_build
  order by entry.position
  limit 1;

  if selected_entry is null then
    current_cycle_no := current_cycle_no + 1;

    update public.daily_game_rotation_state
    set current_cycle = current_cycle_no,
        updated_at = now()
    where id;

    -- Re-sort only at a cycle boundary. Oldest latest appearance goes first;
    -- never-scheduled games come first, with id as the deterministic tie-break.
    insert into public.daily_game_rotation_entries (
      cycle_no,
      game_id,
      position
    )
    select
      current_cycle_no,
      game.id,
      row_number() over (
        order by latest.last_play_date nulls first, game.id
      )
    from public.games game
    left join (
      select daily.game_id, max(daily.play_date) as last_play_date
      from public.daily_games daily
      where daily.play_date < target_date
      group by daily.game_id
    ) latest on latest.game_id = game.id
    where game.is_active
      and game.minimum_app_build <= minimum_build;

    select entry.* into selected_entry
    from public.daily_game_rotation_entries entry
    where entry.cycle_no = current_cycle_no
    order by entry.position
    limit 1;
  end if;

  select * into selected_game
  from public.games
  where id = selected_entry.game_id;

  insert into public.daily_games (play_date, game_id, game_version)
  values (target_date, selected_game.id, selected_game.version)
  returning * into existing_schedule;

  update public.daily_game_rotation_entries
  set scheduled_date = target_date
  where cycle_no = selected_entry.cycle_no
    and game_id = selected_entry.game_id;

  return existing_schedule;
end;
$$;

revoke all on function public.ensure_daily_game(date) from public;

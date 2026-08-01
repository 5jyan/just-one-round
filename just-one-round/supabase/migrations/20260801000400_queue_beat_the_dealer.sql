-- Stage the dealer game in the persisted rotation queue.
--
-- The game keeps minimum_app_build = 8, so the scheduler will not select it
-- until the build-8 release is allowed by app_runtime_config. Keeping the
-- entry in the queue now preserves the fair rotation order and lets the
-- release gate make it eligible without another data migration.
do $$
declare
  current_cycle_no bigint;
  next_position integer;
begin
  select state.current_cycle
  into current_cycle_no
  from public.daily_game_rotation_state state
  where state.id
  for update;

  if current_cycle_no is null then
    raise exception 'daily game rotation state is missing';
  end if;

  if not exists (
    select 1
    from public.games game
    where game.id = 'beat_the_dealer'
      and game.version = 3
      and game.is_active
  ) then
    raise exception 'beat_the_dealer v3 is not an active game';
  end if;

  if not exists (
    select 1
    from public.daily_game_rotation_entries entry
    where entry.game_id = 'beat_the_dealer'
  ) then
    select coalesce(max(entry.position), 0) + 1
    into next_position
    from public.daily_game_rotation_entries entry
    where entry.cycle_no = current_cycle_no;

    insert into public.daily_game_rotation_entries (
      cycle_no,
      game_id,
      position
    ) values (
      current_cycle_no,
      'beat_the_dealer',
      next_position
    );
  end if;
end;
$$;

-- Move blackjack behind Tap 50 in the unfinished current rotation cycle.
-- The allocator and this migration share the same advisory lock so a daily
-- game cannot be assigned while the pending positions are being rewritten.
do $$
declare
  current_cycle_no bigint;
  expected_games constant text[] := array[
    'dung_dodge_v2',
    'gravity_switch',
    'mama_duck_trail',
    'midnight_snake',
    'number_rush',
    'beat_the_dealer',
    'ramen_timer',
    'ten_pitch_slugger'
  ];
  pending_game_count integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('public.ensure_daily_game.rotation')
  );

  select state.current_cycle
  into current_cycle_no
  from public.daily_game_rotation_state state
  where state.id
  for update;

  if current_cycle_no is null then
    raise exception 'daily game rotation state is missing';
  end if;

  select count(*)
  into pending_game_count
  from public.daily_game_rotation_entries entry
  where entry.cycle_no = current_cycle_no
    and entry.game_id = any(expected_games)
    and entry.scheduled_date is null;

  if pending_game_count <> cardinality(expected_games) then
    raise exception 'cannot reorder cycle %: expected % pending games, found %',
      current_cycle_no,
      cardinality(expected_games),
      pending_game_count;
  end if;

  if exists (
    select 1
    from public.daily_game_rotation_entries entry
    where entry.cycle_no = current_cycle_no
      and entry.position >= 1000
  ) then
    raise exception 'cannot reserve temporary rotation positions in cycle %',
      current_cycle_no;
  end if;

  update public.daily_game_rotation_entries
  set position = position + 1000
  where cycle_no = current_cycle_no
    and game_id = any(expected_games);

  update public.daily_game_rotation_entries entry
  set position = desired.position
  from (
    values
      ('dung_dodge_v2'::text, 2),
      ('gravity_switch'::text, 3),
      ('mama_duck_trail'::text, 4),
      ('midnight_snake'::text, 5),
      ('number_rush'::text, 6),
      ('beat_the_dealer'::text, 7),
      ('ramen_timer'::text, 8),
      ('ten_pitch_slugger'::text, 9)
  ) as desired(game_id, position)
  where entry.cycle_no = current_cycle_no
    and entry.game_id = desired.game_id;
end;
$$;

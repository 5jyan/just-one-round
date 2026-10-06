-- Replace the already-created upcoming operating slot with net_boat.
--
-- The operating day changes at 06:00 Asia/Seoul. At the time this migration
-- is created, 2026-09-02 is the next operating slot and has already been
-- previewed by a small number of users. Existing preview sessions are kept
-- with their original game; only the production schedule is changed.
do $$
declare
  target_play_date constant date := date '2026-09-02';
  current_cycle_no bigint;
  midnight_position integer;
  minimum_build integer;
  affected_rows integer;
  scheduled_game public.daily_games;
begin
  -- Coordinate with ensure_daily_game so no allocator can consume the queue
  -- while the current cycle is being edited.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('public.ensure_daily_game.rotation')
  );

  if public.current_play_date() >= target_play_date then
    raise exception
      'refusing to replace an operating slot that has already started: %',
      target_play_date;
  end if;

  if not exists (
    select 1
    from public.daily_games daily
    where daily.play_date = target_play_date
      and daily.game_id = 'midnight_snake'
      and daily.game_version = 2
  ) then
    raise exception
      'expected midnight_snake v2 to be scheduled for %',
      target_play_date;
  end if;

  if exists (
    select 1
    from public.attempts attempt
    where attempt.play_date = target_play_date
  ) or exists (
    select 1
    from public.scores score
    where score.play_date = target_play_date
  ) or exists (
    select 1
    from public.device_daily_claims claim
    where claim.play_date = target_play_date
  ) or exists (
    select 1
    from public.rewarded_ad_grants grant_row
    where grant_row.play_date = target_play_date
  ) then
    raise exception
      'refusing to replace daily game after player activity: %',
      target_play_date;
  end if;

  select state.current_cycle
  into current_cycle_no
  from public.daily_game_rotation_state state
  where state.id
  for update;

  if current_cycle_no is null then
    raise exception 'daily game rotation state is missing';
  end if;

  select entry.position
  into midnight_position
  from public.daily_game_rotation_entries entry
  where entry.cycle_no = current_cycle_no
    and entry.game_id = 'midnight_snake'
    and entry.scheduled_date = target_play_date;

  if midnight_position is null then
    raise exception
      'midnight_snake is not assigned to % in current cycle %',
      target_play_date,
      current_cycle_no;
  end if;

  select coalesce(config.minimum_supported_build, 1)
  into minimum_build
  from public.app_runtime_config config
  where config.id;
  minimum_build := coalesce(minimum_build, 1);

  if not exists (
    select 1
    from public.games game
    where game.id = 'net_boat'
      and game.version = 2
      and game.is_active
      and game.minimum_app_build <= minimum_build
  ) then
    raise exception 'active compatible net_boat v2 is missing';
  end if;

  if not exists (
    select 1
    from public.game_rule_versions versioned
    where versioned.game_id = 'net_boat'
      and versioned.version = 2
  ) then
    raise exception 'net_boat v2 rule metadata is missing';
  end if;

  if not exists (
    select 1
    from public.daily_game_rotation_entries entry
    where entry.cycle_no = current_cycle_no
      and entry.game_id = 'net_boat'
      and entry.scheduled_date is null
      and entry.position > midnight_position
  ) then
    raise exception
      'pending net_boat is not after midnight_snake in current cycle %',
      current_cycle_no;
  end if;

  if exists (
    select 1
    from public.daily_game_rotation_entries entry
    where entry.cycle_no = current_cycle_no
      and entry.position >= 1000
  ) then
    raise exception
      'cannot reserve temporary rotation positions in cycle %',
      current_cycle_no;
  end if;

  -- Remove the snake from this cycle entirely. Simply clearing its date would
  -- make it the next game selected after the replacement.
  delete from public.daily_game_rotation_entries entry
  where entry.cycle_no = current_cycle_no
    and entry.game_id = 'midnight_snake'
    and entry.scheduled_date = target_play_date;

  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'failed to remove midnight_snake from current cycle';
  end if;

  -- Compact the tail without violating unique (cycle_no, position).
  update public.daily_game_rotation_entries entry
  set position = entry.position + 1000
  where entry.cycle_no = current_cycle_no
    and entry.position > midnight_position;

  update public.daily_game_rotation_entries entry
  set position = entry.position - 1001
  where entry.cycle_no = current_cycle_no
    and entry.position >= 1000;

  update public.daily_game_rotation_entries entry
  set scheduled_date = target_play_date
  where entry.cycle_no = current_cycle_no
    and entry.game_id = 'net_boat'
    and entry.scheduled_date is null;

  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'failed to assign net_boat to %', target_play_date;
  end if;

  update public.daily_games daily
  set
    game_id = 'net_boat',
    game_version = 2,
    created_at = now()
  where daily.play_date = target_play_date;

  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'failed to update daily game for %', target_play_date;
  end if;

  -- Any pre-generated NPCs belong to the old game and must not leak into the
  -- replacement game's leaderboard. Existing preview practice sessions are
  -- deliberately not touched.
  delete from public.daily_rank_npcs
  where play_date = target_play_date;

  -- Materialize the remainder of this cycle now so the requested order is
  -- explicit and does not depend on a later preview request.
  scheduled_game := public.ensure_daily_game(target_play_date + 1);
  if scheduled_game.game_id <> 'number_rush'
    or scheduled_game.game_version <> 1 then
    raise exception 'expected number_rush v1 after net_boat';
  end if;

  scheduled_game := public.ensure_daily_game(target_play_date + 2);
  if scheduled_game.game_id <> 'ramen_timer'
    or scheduled_game.game_version <> 3 then
    raise exception 'expected ramen_timer v3 after number_rush';
  end if;

  scheduled_game := public.ensure_daily_game(target_play_date + 3);
  if scheduled_game.game_id <> 'ten_pitch_slugger'
    or scheduled_game.game_version <> 7 then
    raise exception 'expected ten_pitch_slugger v7 after ramen_timer';
  end if;
end;
$$;

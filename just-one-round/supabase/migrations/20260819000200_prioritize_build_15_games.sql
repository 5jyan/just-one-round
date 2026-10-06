-- Put the three games introduced by build 15 at the front of the remaining
-- cycle. The migration is intentionally limited to the 2026-08-19 play day
-- and aborts if any real player activity already exists for that day.

do $$
declare
  target_play_date constant date := date '2026-08-19';
  current_cycle_no bigint;
  affected_entries integer;
begin
  if public.current_play_date() <> target_play_date then
    raise exception 'refusing to change a non-current play day';
  end if;

  if exists (
    select 1 from public.attempts where play_date = target_play_date
  ) or exists (
    select 1 from public.scores where play_date = target_play_date
  ) or exists (
    select 1 from public.device_daily_claims where play_date = target_play_date
  ) or exists (
    select 1 from public.rewarded_ad_grants where play_date = target_play_date
  ) then
    raise exception 'refusing to replace a daily game after player activity';
  end if;

  select state.current_cycle
  into current_cycle_no
  from public.daily_game_rotation_state state
  where state.id
  for update;

  if current_cycle_no is null then
    raise exception 'daily game rotation state is missing';
  end if;

  -- Clear the previous date assignment and move the affected positions out of
  -- the way before assigning their final order. This avoids both unique
  -- constraints while the rows are being rearranged.
  update public.daily_game_rotation_entries
  set
    position = position + 100,
    scheduled_date = null
  where cycle_no = current_cycle_no
    and game_id in (
      'net_boat',
      'bathhouse_sort',
      'lily_frog',
      'number_rush',
      'beat_the_dealer',
      'ramen_timer',
      'ten_pitch_slugger'
    );

  get diagnostics affected_entries = row_count;
  if affected_entries <> 7 then
    raise exception 'unexpected remaining rotation size: %', affected_entries;
  end if;

  update public.daily_game_rotation_entries
  set
    position = case game_id
      when 'net_boat' then 6
      when 'bathhouse_sort' then 7
      when 'lily_frog' then 8
      when 'number_rush' then 9
      when 'beat_the_dealer' then 10
      when 'ramen_timer' then 11
      when 'ten_pitch_slugger' then 12
    end,
    scheduled_date = case
      when game_id = 'net_boat' then target_play_date
      else null
    end
  where cycle_no = current_cycle_no
    and game_id in (
      'net_boat',
      'bathhouse_sort',
      'lily_frog',
      'number_rush',
      'beat_the_dealer',
      'ramen_timer',
      'ten_pitch_slugger'
    );

  insert into public.daily_games (play_date, game_id, game_version)
  select target_play_date, game.id, game.version
  from public.games game
  where game.id = 'net_boat'
    and game.is_active
  on conflict (play_date) do update
  set
    game_id = excluded.game_id,
    game_version = excluded.game_version,
    created_at = now();

  if not found then
    raise exception 'active net_boat game is missing';
  end if;

  delete from public.daily_rank_npcs
  where play_date = target_play_date;
end;
$$;

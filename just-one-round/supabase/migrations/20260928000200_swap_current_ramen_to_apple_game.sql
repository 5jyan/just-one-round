-- Switch only today's schedule when the deployed schedule is the Android-safe
-- ramen_timer v3. Existing attempts, scores, sessions, and rotation entries
-- remain untouched because this migration changes only the daily_games pointer.
--
-- Manual rollback path (no automatic rollback is performed): for the affected
-- play_date, restore daily_games to ('ramen_timer', 3) only after confirming
-- that new apple_game_v2 attempts should no longer be issued. Never rewrite or
-- delete attempts, scores, sessions, or daily_game_rotation_entries.
do $$
declare
  play_day date := public.current_play_date();
  scheduled_game public.daily_games;
  target_game public.games;
begin
  select *
  into scheduled_game
  from public.daily_games
  where play_date = play_day
  for update;

  if not found then
    raise exception 'no daily game scheduled for current play date';
  end if;

  -- Validate the replacement even when this migration is being retried. That
  -- keeps a stale or partially-installed catalog from being accepted silently.
  select *
  into target_game
  from public.games
  where id = 'apple_game_v2'
  for update;

  if not found
    or not target_game.is_active
    or target_game.version is distinct from 1 then
    raise exception
      'apple_game_v2 v1 must be active before changing today''s game';
  end if;

  if not exists (
    select 1
    from public.game_rule_versions
    where game_id = 'apple_game_v2'
      and version = 1
  ) then
    raise exception 'apple_game_v2 v1 rule snapshot is missing';
  end if;

  -- Retry-safe no-op after the replacement has already been applied.
  if scheduled_game.game_id = 'apple_game_v2'
    and scheduled_game.game_version = 1 then
    return;
  end if;

  if scheduled_game.game_id is distinct from 'ramen_timer'
    or scheduled_game.game_version is distinct from 3 then
    raise exception
      'current daily game is not ramen_timer v3; refusing to overwrite it';
  end if;

  update public.daily_games
  set game_id = 'apple_game_v2',
      game_version = 1
  where play_date = play_day
    and game_id = 'ramen_timer'
    and game_version = 3;

  if not found then
    raise exception 'today''s ramen_timer v3 schedule changed before update';
  end if;
end;
$$;

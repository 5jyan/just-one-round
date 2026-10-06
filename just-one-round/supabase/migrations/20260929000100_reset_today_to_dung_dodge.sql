-- Explicit one-time reset requested for the current play day.
--
-- This removes today's play-state rows (attempts, scores, sessions, ad
-- grants, device claims, acknowledgements, duel opponents, and synthetic
-- rank rows) so every player can start the replacement game afresh. Wallet
-- and experience transactions are intentionally preserved; they are not
-- play-state rows and deleting them would make player balances inconsistent.
--
-- The data deletion is intentionally irreversible. A safe schedule-only
-- rollback is to restore today's daily_games row to ten_pitch_slugger v8
-- before any new dung_dodge_v2 v1 attempts are issued; deleted rows cannot be
-- reconstructed by this migration.
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

  select *
  into target_game
  from public.games
  where id = 'dung_dodge_v2'
  for update;

  if not found
    or not target_game.is_active
    or target_game.version is distinct from 1
    or not exists (
      select 1
      from public.game_rule_versions
      where game_id = 'dung_dodge_v2'
        and version = 1
    ) then
    raise exception 'dung_dodge_v2 v1 must be active with a rule snapshot';
  end if;

  -- Retry-safe no-op after the switch has already been applied. This also
  -- avoids deleting a newly started dung_dodge_v2 day if the migration is
  -- retried after a successful commit.
  if scheduled_game.game_id = 'dung_dodge_v2'
    and scheduled_game.game_version = 1 then
    return;
  end if;

  if scheduled_game.game_id is distinct from 'ten_pitch_slugger'
    or scheduled_game.game_version is distinct from 8 then
    raise exception
      'current daily game is not ten_pitch_slugger v8; refusing to overwrite it';
  end if;

  -- Sessions can have no attempt (practice), so remove them explicitly.
  -- Their duel-opponent rows cascade from the session foreign key.
  delete from public.daily_play_sessions
  where play_date = play_day;

  -- Scores cascade from attempts. Any sessions linked to an attempt were
  -- already removed above, so this is safe for both ranked and practice play.
  delete from public.attempts
  where play_date = play_day;

  -- Reset ad/challenge state and the device-level daily lock for the new game.
  delete from public.rewarded_ad_grants
  where play_date = play_day;

  delete from public.device_daily_claims
  where play_date = play_day;

  delete from public.daily_result_acknowledgements
  where play_date = play_day;

  -- These are synthetic ranking rows, not player balances; regenerate them
  -- for dung_dodge_v2 when the first result is requested.
  delete from public.daily_rank_npcs
  where play_date = play_day;

  -- Keep this orphan-safe in case a legacy row was not linked to a session.
  delete from public.western_duel_opponents
  where play_date = play_day;

  update public.daily_games
  set game_id = 'dung_dodge_v2',
      game_version = 1
  where play_date = play_day
    and game_id = 'ten_pitch_slugger'
    and game_version = 8;

  if not found then
    raise exception 'today''s ten_pitch_slugger v8 schedule changed before update';
  end if;
end;
$$;

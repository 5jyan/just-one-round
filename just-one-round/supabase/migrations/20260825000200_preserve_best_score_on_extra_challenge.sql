-- Extra ranked challenges are retries, not score replacements. Keep every
-- submitted score so the authoritative leaderboard queries can retain the
-- highest score for each user and daily game.

drop trigger if exists daily_play_sessions_replace_score_before_extra_insert
  on public.daily_play_sessions;

-- The trigger is no longer part of the score contract. Remove its helper too
-- so a future migration cannot accidentally re-enable the destructive path.
drop function if exists public.discard_previous_daily_challenge_score();

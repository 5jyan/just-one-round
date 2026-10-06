-- A daily_games row is an immutable snapshot once its play date has started.
-- Future rows, however, must follow a game rule-version rollout before they
-- become playable so the client and server do not disagree at daily reset.
update public.daily_games as scheduled
set game_version = catalog.version
from public.games as catalog
where scheduled.play_date > public.current_play_date()
  and scheduled.game_id = catalog.id
  and scheduled.game_version is distinct from catalog.version
  and catalog.is_active;

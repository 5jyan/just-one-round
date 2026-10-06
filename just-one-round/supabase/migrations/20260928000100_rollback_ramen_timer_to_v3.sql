-- Android Alpha still serves build 22, whose registry supports ramen_timer v3.
-- V4 changed feedback only; scoring is unchanged. Preserve completed v4
-- attempts and scores, but issue today's remaining and future attempts as v3.

update public.games
set
  version = 3,
  description =
    '처음 3초로 박자를 익힌 뒤, 증기 사이로 두 번 희미하게 비치는 시계를 참고해 10초, 20초, 30초를 맞추세요.'
where id = 'ramen_timer'
  and version = 4;

update public.daily_games
set game_version = 3
where game_id = 'ramen_timer'
  and game_version = 4
  and play_date >= public.current_play_date();

insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds
) values (
  'star_dodge',
  1,
  '별빛 피하기',
  '장애물을 피하고 별을 모아 최고 점수에 도전하세요.',
  60
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds;

insert into public.daily_games (play_date, game_id, game_version)
values (
  (now() at time zone 'Asia/Seoul')::date,
  'star_dodge',
  1
)
on conflict (play_date) do update set
  game_id = excluded.game_id,
  game_version = excluded.game_version;

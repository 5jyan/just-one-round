insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds
) values (
  'dung_dodge',
  1,
  '똥 피하기',
  '떨어지는 똥을 피해 최대 60초까지 버텨 보세요. 생존 시간은 0.01초까지 기록됩니다.',
  60
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds;

insert into public.daily_games (play_date, game_id, game_version)
values (
  (now() at time zone 'Asia/Seoul')::date,
  'dung_dodge',
  1
)
on conflict (play_date) do update set
  game_id = excluded.game_id,
  game_version = excluded.game_version;

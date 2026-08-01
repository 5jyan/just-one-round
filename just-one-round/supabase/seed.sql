insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds
) values (
  'gravity_switch',
  1,
  '중력 스위치',
  '탭으로 중력을 뒤집어 위아래로 이어지는 입체 기둥 미로를 돌파하세요.',
  300
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds;

insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds,
  minimum_app_build
) values (
  'midnight_snake',
  2,
  '야식털이 뱀',
  '밤에 탈출한 애완뱀을 조종해 야식과 한 번뿐인 황금 소시지·쥐를 노리고 벽과 자기 몸을 피하세요.',
  300,
  7
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  minimum_app_build = excluded.minimum_app_build;

insert into public.daily_games (play_date, game_id, game_version)
values (
  public.current_play_date(),
  'midnight_snake',
  2
)
on conflict (play_date) do update set
  game_id = excluded.game_id,
  game_version = excluded.game_version;

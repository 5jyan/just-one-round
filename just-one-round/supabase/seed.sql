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

insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds
) values (
  'failed_bakery',
  1,
  '대충 케이크',
  '움직이는 못난이 케이크를 탭해 쌓으세요. 어긋난 부분은 잘리고 3연속 퍼펙트면 크기가 회복됩니다.',
  180
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
  duration_seconds
) values (
  'gravity_switch',
  1,
  '중력 스위치',
  '탭으로 중력을 뒤집어 위아래로 이어지는 입체 기둥 미로를 돌파하세요.',
  180
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
  duration_seconds
) values (
  'apple_game',
  1,
  '사과게임',
  '드래그한 사과 숫자의 합을 10으로 만들어 제한 시간 안에 최대한 많이 지우세요.',
  120
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds;

insert into public.daily_games (play_date, game_id, game_version)
values (
  public.current_play_date(),
  'dung_dodge_v2',
  1
)
on conflict (play_date) do update set
  game_id = excluded.game_id,
  game_version = excluded.game_version;

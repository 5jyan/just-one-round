insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds,
  is_active,
  minimum_app_build
) values (
  'ramen_timer',
  2,
  '10·20·30! 컵라면',
  '처음 3초 뒤 증기가 시계를 가립니다. 12~13초와 22~23초에 희미하게 비치는 시간을 참고해 10초·20초·30초의 총 오차를 겨루세요.',
  45,
  true,
  10
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  is_active = excluded.is_active,
  minimum_app_build = excluded.minimum_app_build;

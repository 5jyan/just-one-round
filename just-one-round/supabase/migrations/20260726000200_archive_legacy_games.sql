-- Keep historical scores and attempts intact while removing superseded games
-- from scheduling and the developer game picker.
update public.games
set is_active = false
where id in ('star_dodge', 'dung_dodge', 'failed_bakery', 'apple_game');

update public.profiles
set test_game_id = null,
    updated_at = now()
where test_game_id in ('star_dodge', 'dung_dodge', 'failed_bakery', 'apple_game');

update public.daily_games
set game_id = 'dung_dodge_v2',
    game_version = (
      select version
      from public.games
      where id = 'dung_dodge_v2'
    )
where play_date >= (now() at time zone 'Asia/Seoul')::date
  and game_id in ('star_dodge', 'dung_dodge', 'failed_bakery', 'apple_game');

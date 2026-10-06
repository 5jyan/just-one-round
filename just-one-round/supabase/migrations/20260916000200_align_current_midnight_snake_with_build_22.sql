-- The released build 22 contains midnight_snake v3. The current daily
-- snapshot was materialized as v2 before that release migration was applied.
-- Do not rewrite a started day after an attempt exists.

do $$
begin
  if exists (
    select 1
    from public.attempts
    where play_date = public.current_play_date()
      and game_id = 'midnight_snake'
  ) or exists (
    select 1
    from public.scores
    where play_date = public.current_play_date()
      and game_id = 'midnight_snake'
  ) then
    raise exception
      'cannot upgrade the current midnight_snake snapshot after play has started';
  end if;
end;
$$;

update public.daily_games
set game_version = 3
where play_date = public.current_play_date()
  and game_id = 'midnight_snake'
  and game_version = 2;

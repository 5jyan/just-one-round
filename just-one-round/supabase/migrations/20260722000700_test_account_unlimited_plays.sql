alter table public.profiles
  add column is_test_account boolean not null default false;

alter table public.attempts
  drop constraint attempts_ordinal_range,
  drop constraint attempts_grant_matches_ordinal;

alter table public.attempts
  add constraint attempts_ordinal_positive check (ordinal >= 1);

create or replace function public.claim_daily_attempt()
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  scheduled_game public.daily_games;
  claimed_attempt public.attempts;
  is_test boolean := false;
  next_ordinal smallint := 1;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select p.is_test_account into is_test from public.profiles p where p.id = current_user_id;
  scheduled_game := public.ensure_daily_game(seoul_date);
  if is_test then
    select coalesce(max(ordinal), 0) + 1 into next_ordinal from public.attempts
    where user_id = current_user_id and play_date = seoul_date;
    insert into public.attempts (user_id, play_date, game_id, game_version, ordinal, grant_type)
    values (current_user_id, seoul_date, scheduled_game.game_id, scheduled_game.game_version, next_ordinal, 'daily')
    returning * into claimed_attempt;
  else
    insert into public.attempts (user_id, play_date, game_id, game_version, ordinal, grant_type)
    values (current_user_id, seoul_date, scheduled_game.game_id, scheduled_game.game_version, 1, 'daily')
    on conflict (user_id, play_date, ordinal) do update set user_id = excluded.user_id
    returning * into claimed_attempt;
  end if;
  return claimed_attempt;
end;
$$;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  is_test boolean := false;
begin
  perform public.ensure_daily_game(seoul_date);
  select p.is_test_account into is_test from public.profiles p where p.id = (select auth.uid());
  return (
    with scheduled as (
      select dg.play_date, g.* from public.daily_games dg join public.games g on g.id = dg.game_id where dg.play_date = seoul_date
    ), my_attempts as (
      select * from public.attempts where user_id = (select auth.uid()) and play_date = seoul_date
    ) select jsonb_build_object(
      'play_date', seoul_date,
      'game', (select jsonb_build_object('id', id, 'version', version, 'display_name', display_name, 'description', description, 'duration_seconds', duration_seconds) from scheduled),
      'attempts', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ordinal', ordinal, 'status', status, 'grant_type', grant_type) order by ordinal) from my_attempts), '[]'::jsonb),
      'test_mode', coalesce(is_test, false),
      'ad_attempt_available', false,
      'result', public.get_my_daily_result(seoul_date)
    )
  );
end;
$$;

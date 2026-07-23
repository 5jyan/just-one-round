alter table public.profiles
  add column test_game_id text references public.games (id);

create or replace function public.claim_daily_attempt()
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  scheduled_game public.daily_games;
  selected_game public.games;
  claimed_attempt public.attempts;
  is_test boolean := false;
  selected_test_game_id text;
  next_ordinal smallint := 1;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select p.is_test_account, p.test_game_id
  into is_test, selected_test_game_id
  from public.profiles p
  where p.id = current_user_id;

  scheduled_game := public.ensure_daily_game(seoul_date);

  if coalesce(is_test, false) and selected_test_game_id is not null then
    select * into selected_game
    from public.games
    where id = selected_test_game_id and is_active;
  end if;

  if selected_game is null then
    select * into selected_game
    from public.games
    where id = scheduled_game.game_id and version = scheduled_game.game_version;
  end if;

  if coalesce(is_test, false) then
    select coalesce(max(ordinal), 0) + 1 into next_ordinal
    from public.attempts
    where user_id = current_user_id and play_date = seoul_date;

    insert into public.attempts (
      user_id, play_date, game_id, game_version, ordinal, grant_type
    ) values (
      current_user_id, seoul_date, selected_game.id,
      selected_game.version, next_ordinal, 'daily'
    ) returning * into claimed_attempt;
  else
    insert into public.attempts (
      user_id, play_date, game_id, game_version, ordinal, grant_type
    ) values (
      current_user_id, seoul_date, selected_game.id,
      selected_game.version, 1, 'daily'
    )
    on conflict (user_id, play_date, ordinal)
    do update set user_id = excluded.user_id
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
  scheduled_game public.daily_games;
  selected_game public.games;
  is_test boolean := false;
  selected_test_game_id text;
begin
  scheduled_game := public.ensure_daily_game(seoul_date);

  select p.is_test_account, p.test_game_id
  into is_test, selected_test_game_id
  from public.profiles p
  where p.id = (select auth.uid());

  if coalesce(is_test, false) and selected_test_game_id is not null then
    select * into selected_game
    from public.games
    where id = selected_test_game_id and is_active;
  end if;

  if selected_game is null then
    select * into selected_game
    from public.games
    where id = scheduled_game.game_id and version = scheduled_game.game_version;
  end if;

  return (
    with my_attempts as (
      select *
      from public.attempts
      where user_id = (select auth.uid()) and play_date = seoul_date
    ), my_profile as (
      select nickname, birth_year, birth_month, gender
      from public.profiles
      where id = (select auth.uid())
    )
    select jsonb_build_object(
      'play_date', seoul_date,
      'game', jsonb_build_object(
        'id', selected_game.id,
        'version', selected_game.version,
        'display_name', selected_game.display_name,
        'description', selected_game.description,
        'duration_seconds', selected_game.duration_seconds
      ),
      'profile', (select jsonb_build_object(
        'nickname', nickname,
        'birth_year', birth_year,
        'birth_month', birth_month,
        'gender', gender
      ) from my_profile),
      'attempts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'ordinal', ordinal,
        'status', status,
        'grant_type', grant_type,
        'game_id', game_id
      ) order by ordinal) from my_attempts), '[]'::jsonb),
      'test_mode', coalesce(is_test, false),
      'ad_attempt_available', case
        when coalesce(is_test, false) then false
        else exists (
          select 1 from my_attempts where ordinal = 1 and status <> 'issued'
        ) and not exists (
          select 1 from my_attempts where ordinal = 2
        )
      end,
      'result', public.get_my_daily_result(seoul_date)
    )
  );
end;
$$;

create function public.get_developer_games()
returns jsonb
language plpgsql
security definer set search_path = ''
stable
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_test_account
  ) then
    raise exception 'test account required';
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', id,
      'version', version,
      'display_name', display_name
    ) order by display_name, id), '[]'::jsonb)
    from public.games
    where is_active
  );
end;
$$;

create function public.reset_developer_daily_progress()
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_test_account
  ) then
    raise exception 'test account required';
  end if;

  delete from public.attempts
  where user_id = (select auth.uid())
    and play_date = (now() at time zone 'Asia/Seoul')::date;
end;
$$;

create function public.set_developer_game(selected_game_id text)
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_test_account
  ) then
    raise exception 'test account required';
  end if;

  if not exists (
    select 1 from public.games where id = selected_game_id and is_active
  ) then
    raise exception 'active game not found';
  end if;

  update public.profiles
  set test_game_id = selected_game_id, updated_at = now()
  where id = (select auth.uid());

  delete from public.attempts
  where user_id = (select auth.uid())
    and play_date = (now() at time zone 'Asia/Seoul')::date;
end;
$$;

revoke all on function public.get_developer_games() from public;
revoke all on function public.reset_developer_daily_progress() from public;
revoke all on function public.set_developer_game(text) from public;

grant execute on function public.get_developer_games() to authenticated;
grant execute on function public.reset_developer_daily_progress() to authenticated;
grant execute on function public.set_developer_game(text) to authenticated;

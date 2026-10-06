-- Keep test-account attempts compatible with the confirmed-start state
-- machine after the extra-challenge wrapper is installed.
create or replace function public.claim_test_daily_attempt_with_session(
  expected_play_date date
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  claimed_attempt public.attempts;
  scheduled_game public.daily_games;
  selected_version public.game_rule_versions;
  test_game_id text;
  selected_game_id text;
  selected_game_version integer;
  next_ordinal smallint;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text), hashtext(play_day::text)
  );

  select attempt.*
  into claimed_attempt
  from public.daily_play_sessions session
  join public.attempts attempt on attempt.id = session.attempt_id
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.play_mode = 'challenge'
    and (session.started_at is null or attempt.status = 'issued')
  order by session.created_at desc, session.id desc
  limit 1;

  if claimed_attempt.id is null then
    select attempt.*
    into claimed_attempt
    from public.attempts attempt
    where attempt.user_id = current_user_id
      and attempt.play_date = play_day
      and attempt.status = 'issued'
      and not exists (
        select 1
        from public.daily_play_sessions session
        where session.attempt_id = attempt.id
          or (
            session.user_id = current_user_id
            and session.play_date = play_day
            and session.ordinal = attempt.ordinal
          )
      )
    order by attempt.ordinal desc, attempt.issued_at desc
    limit 1;
  end if;

  if claimed_attempt.id is null then
    select profile.test_game_id
    into test_game_id
    from public.profiles profile
    where profile.id = current_user_id;

    if test_game_id is not null then
      select game.id, game.version
      into selected_game_id, selected_game_version
      from public.games game
      where game.id = test_game_id
        and game.is_active;
    end if;

    if selected_game_id is null then
      scheduled_game := public.ensure_daily_game(play_day);
      selected_game_id := scheduled_game.game_id;
      selected_game_version := scheduled_game.game_version;
    end if;

    next_ordinal := greatest(
      coalesce((
        select max(attempt.ordinal)
        from public.attempts attempt
        where attempt.user_id = current_user_id
          and attempt.play_date = play_day
      ), 0),
      coalesce((
        select max(session.ordinal)
        from public.daily_play_sessions session
        where session.user_id = current_user_id
          and session.play_date = play_day
      ), 0)
    ) + 1;

    insert into public.attempts (
      user_id, play_date, game_id, game_version, ordinal, grant_type, issued_at
    ) values (
      current_user_id, play_day, selected_game_id, selected_game_version,
      next_ordinal, 'daily', now()
    ) returning * into claimed_attempt;
  end if;

  select *
  into selected_version
  from public.game_rule_versions versioned
  where versioned.game_id = claimed_attempt.game_id
    and versioned.version = claimed_attempt.game_version;
  if selected_version.game_id is null then
    raise exception 'game version not found';
  end if;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode, attempt_id, game_id,
    game_version, game_duration_seconds, created_at
  ) values (
    current_user_id, play_day, claimed_attempt.ordinal, 'challenge',
    claimed_attempt.id, claimed_attempt.game_id, claimed_attempt.game_version,
    selected_version.duration_seconds, claimed_attempt.issued_at
  ) on conflict (attempt_id) do nothing;

  return claimed_attempt;
end;
$$;

create or replace function public.claim_daily_attempt(
  expected_play_date date
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  choice_state jsonb;
  is_test boolean := false;
  live_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  select coalesce(profile.is_test_account, false)
  into is_test
  from public.profiles profile
  where profile.id = current_user_id;

  if is_test then
    return public.claim_test_daily_attempt_with_session(expected_play_date);
  end if;

  select attempt.*
  into live_attempt
  from public.daily_play_sessions session
  join public.attempts attempt on attempt.id = session.attempt_id
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.play_mode = 'challenge'
    and (session.started_at is null or attempt.status = 'issued')
  order by session.ordinal desc
  limit 1;
  if live_attempt.id is not null then
    return live_attempt;
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if coalesce((choice_state->>'challenge_session_count')::integer, 0) <> 0 then
    raise exception 'extra challenge choice required';
  end if;
  return public.claim_daily_attempt_before_extra_choice(expected_play_date);
end;
$$;

revoke all on function public.claim_daily_attempt(date) from public;
revoke all on function public.claim_test_daily_attempt_with_session(date)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_daily_attempt(date) to authenticated;

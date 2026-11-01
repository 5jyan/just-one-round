-- Temple Run v1 is staged for local/test-account play first. It stays out of
-- daily rotation until an operator explicitly activates it and schedules it.
insert into public.games (
  id, version, display_name, description, duration_seconds,
  is_active, minimum_app_build
) values (
  'temple_run', 1, '유적 질주',
  '세 줄의 유적길을 달리며 스와이프로 장애물을 피하고 유물 코인을 모으세요.',
  300, false, 31
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  -- Publishing and daily scheduling remain an explicit operator decision.
  is_active = false,
  minimum_app_build = excluded.minimum_app_build;

-- Temple Run records coins in the shared stars_collected column. The existing
-- 0..200 bound predates this game's longer route; widening it preserves every
-- existing value while allowing the deterministic course's bounded coin cap.
alter table public.scores drop constraint if exists scores_stars_range;
alter table public.scores
  add constraint scores_stars_range check (stars_collected between 0 and 1000);

-- The normal developer list contains active games. Keep this staged game
-- selectable for test accounts without making it public or schedulable.
create or replace function public.get_developer_games()
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
    where is_active or id in ('wind_darts', 'temple_run')
  );
end;
$$;

create or replace function public.set_developer_game(selected_game_id text)
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
    select 1
    from public.games
    where id = selected_game_id
      and (is_active or id in ('wind_darts', 'temple_run'))
  ) then
    raise exception 'active game not found';
  end if;

  update public.profiles
  set test_game_id = selected_game_id, updated_at = now()
  where id = (select auth.uid());

  delete from public.attempts
  where user_id = (select auth.uid())
    and play_date = public.current_play_date();
end;
$$;

revoke all on function public.get_developer_games() from public;
revoke all on function public.set_developer_game(text) from public;
grant execute on function public.get_developer_games() to authenticated;
grant execute on function public.set_developer_game(text) to authenticated;

-- Route a selected staged game to a test account while preserving all existing
-- claim behavior and the immutable daily schedule for every other account.
create or replace function public.claim_test_temple_run_attempt_v1(
  expected_play_date date
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  selected_game public.game_rule_versions;
  existing_attempt public.attempts;
  claimed_attempt public.attempts;
  next_ordinal smallint;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if not exists (
    select 1 from public.profiles profile
    where profile.id = current_user_id
      and profile.is_test_account
      and profile.test_game_id = 'temple_run'
  ) then
    raise exception 'temple run test selection required';
  end if;

  select versioned.*
  into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = 'temple_run'
    and versioned.version = 1;
  if selected_game.game_id is null then
    raise exception 'temple run catalog entry not found';
  end if;

  select attempt.*
  into existing_attempt
  from public.attempts attempt
  where attempt.user_id = current_user_id
    and attempt.play_date = play_day
    and attempt.game_id = 'temple_run'
    and attempt.game_version = 1
    and attempt.status = 'issued'
  order by attempt.ordinal desc, attempt.issued_at desc
  limit 1;
  if existing_attempt.id is not null then
    insert into public.daily_play_sessions (
      user_id, play_date, ordinal, play_mode, attempt_id, game_id,
      game_version, game_duration_seconds, created_at
    ) values (
      current_user_id, play_day, existing_attempt.ordinal, 'challenge',
      existing_attempt.id, selected_game.game_id, selected_game.version,
      selected_game.duration_seconds, existing_attempt.issued_at
    ) on conflict (attempt_id) do nothing;
    return existing_attempt;
  end if;

  select (coalesce(max(attempt.ordinal), 0) + 1)::smallint
  into next_ordinal
  from public.attempts attempt
  where attempt.user_id = current_user_id
    and attempt.play_date = play_day;

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type, issued_at
  ) values (
    current_user_id, play_day, selected_game.game_id, selected_game.version,
    next_ordinal, 'daily', now()
  ) returning * into claimed_attempt;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode, attempt_id, game_id,
    game_version, game_duration_seconds, created_at
  ) values (
    current_user_id, play_day, claimed_attempt.ordinal, 'challenge',
    claimed_attempt.id, selected_game.game_id, selected_game.version,
    selected_game.duration_seconds, claimed_attempt.issued_at
  ) on conflict (attempt_id) do nothing;
  return claimed_attempt;
end;
$$;

revoke all on function public.claim_test_temple_run_attempt_v1(date)
  from public, anon, authenticated, service_role;

alter function public.claim_daily_attempt(date)
rename to claim_daily_attempt_before_temple_run;

create function public.claim_daily_attempt(
  expected_play_date date
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  selected_test_game_id text;
  is_test boolean := false;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  select coalesce(profile.is_test_account, false), profile.test_game_id
  into is_test, selected_test_game_id
  from public.profiles profile
  where profile.id = current_user_id;

  if is_test and selected_test_game_id = 'temple_run' then
    perform pg_advisory_xact_lock(
      hashtext(current_user_id::text), hashtext(play_day::text)
    );
    return public.claim_test_temple_run_attempt_v1(expected_play_date);
  end if;

  return public.claim_daily_attempt_before_temple_run(expected_play_date);
end;
$$;

revoke all on function public.claim_daily_attempt_before_temple_run(date)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_daily_attempt(date) from public;
grant execute on function public.claim_daily_attempt(date) to authenticated;

-- Expose the staged game to a selected test account while leaving the normal
-- daily state and schedule untouched.
alter function public.get_today_state()
rename to get_today_state_before_temple_run;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  state jsonb;
  selected_game public.game_rule_versions;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  state := public.get_today_state_before_temple_run();
  select versioned.*
  into selected_game
  from public.game_rule_versions versioned
  join public.games game
    on game.id = versioned.game_id and game.version = versioned.version
  join public.profiles profile on profile.id = current_user_id
  where profile.is_test_account
    and profile.test_game_id = 'temple_run'
    and versioned.game_id = 'temple_run'
    and versioned.version = 1;

  if selected_game.game_id is not null then
    state := jsonb_set(
      state,
      '{game}',
      jsonb_build_object(
        'id', selected_game.game_id,
        'version', selected_game.version,
        'display_name', selected_game.display_name,
        'description', selected_game.description,
        'duration_seconds', selected_game.duration_seconds
      ),
      true
    );
  end if;
  return state;
end;
$$;

revoke all on function public.get_today_state_before_temple_run()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public, anon, service_role;
grant execute on function public.get_today_state() to authenticated;

-- Temple Run uses the shared score RPC. This outer wrapper keeps the previous
-- validator chain intact and enforces only its versioned bounds.
alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
rename to submit_daily_score_before_temple_run;

revoke all on function public.submit_daily_score_before_temple_run(
  uuid, integer, integer, integer, integer
) from public, anon, authenticated;

create function public.submit_daily_score(
  attempt_id uuid,
  raw_score integer,
  stars_collected integer,
  collisions integer,
  duration_ms integer
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  active_attempt public.attempts;
  distance_component integer;
  minimum_distance integer;
  maximum_distance integer;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id and user_id = current_user_id
  for update;
  if active_attempt is null then
    raise exception 'attempt not found';
  end if;

  if active_attempt.game_id is distinct from 'temple_run'
    or active_attempt.game_version is distinct from 1 then
    return public.submit_daily_score_before_temple_run(
      attempt_id, raw_score, stars_collected, collisions, duration_ms
    );
  end if;

  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued' then
    raise exception 'active attempt not found';
  end if;

  distance_component := raw_score - stars_collected * 10;
  -- The client accelerates to 42m/s and can briefly boost to 55.44m/s, but
  -- its integrated five-minute route (including all three scheduled boosts)
  -- remains below this conservative 24m/s average envelope. Allow two metres
  -- for frame and integer rounding at either end of the distance component.
  minimum_distance := floor(duration_ms / 1000.0 * 8.0)::integer - 2;
  maximum_distance := ceil(duration_ms / 1000.0 * 24.0)::integer + 2;

  if active_attempt.game_duration_seconds is null
    or active_attempt.game_duration_seconds <> 300
    or raw_score is null
    or stars_collected is null
    or collisions is null
    or duration_ms is null
    or raw_score not between 0 and 100000
    -- Runtime maps collected coins to the shared stars_collected field.
    or stars_collected not between 0 and 1000
    -- The runtime can only consume a bounded number of contacts: a shield
    -- absorbs one solid hit and a later unshielded hit terminates the run.
    -- Keep the shared scores table bound as a defensive upper limit; the
    -- tighter route cadence does not change the exactly-once terminal path.
    or collisions not between 0 and 200
    or duration_ms not between 4000 and 300000
    or distance_component < 0
    or (minimum_distance > 0 and distance_component < minimum_distance)
    or distance_component > maximum_distance then
    raise exception 'invalid temple run result';
  end if;

  perform public.assert_score_submission_elapsed(
    active_attempt.issued_at, duration_ms
  );

  if now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts set status = 'expired' where id = active_attempt.id;
    raise exception 'attempt expired';
  end if;

  insert into public.scores (
    attempt_id, user_id, play_date, game_id, game_version, raw_score,
    duration_ms, stars_collected, collisions
  ) values (
    active_attempt.id, current_user_id, active_attempt.play_date,
    active_attempt.game_id, active_attempt.game_version, raw_score, duration_ms,
    stars_collected, collisions
  );

  update public.attempts
  set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;

  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

revoke all on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  from public, anon;
grant execute on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  to authenticated;

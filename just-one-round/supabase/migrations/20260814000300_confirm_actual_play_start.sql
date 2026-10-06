-- Issuing a server-side play record is not proof that the game loaded. Build
-- 12 confirms the start only after the guide is dismissed and the runtime is
-- ready. Older supported clients keep their established issue-is-start
-- behavior until they are upgraded.

alter table public.daily_play_sessions
  add column started_at timestamptz;

update public.daily_play_sessions
set started_at = created_at
where started_at is null;

create function public.default_legacy_play_started_at()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  if new.started_at is null
    and coalesce(public.request_app_build(), 0) < 12 then
    new.started_at := coalesce(new.created_at, now());
  end if;
  return new;
end;
$$;

create trigger daily_play_sessions_legacy_started_before_insert
before insert on public.daily_play_sessions
for each row execute function public.default_legacy_play_started_at();

revoke all on function public.default_legacy_play_started_at()
  from public, anon, authenticated, service_role;

create or replace function public.daily_play_choice_state(
  target_user_id uuid,
  target_play_date date
)
returns jsonb
language sql
stable
security definer set search_path = ''
as $$
  with play_summary as (
    select
      count(*) filter (where session.started_at is not null)::integer
        as play_count,
      count(*) filter (
        where session.play_mode = 'practice'
          and session.started_at is not null
      )::integer as practice_count,
      coalesce(bool_or(
        session.play_mode = 'challenge'
          and session.started_at is not null
      ), false) as challenge_played,
      coalesce(bool_or(
        session.play_mode = 'challenge'
          and session.started_at is not null
          and attempt.status = 'issued'
      ), false) as challenge_in_progress,
      coalesce(bool_or(
        session.play_mode = 'challenge'
          and session.started_at is null
      ), false) as challenge_pending,
      coalesce(bool_or(
        session.play_mode = 'practice'
          and session.started_at is null
      ), false) as practice_pending
    from public.daily_play_sessions session
    left join public.attempts attempt on attempt.id = session.attempt_id
    where session.user_id = target_user_id
      and session.play_date = target_play_date
  ), ad_summary as (
    select exists (
      select 1
      from public.rewarded_ad_grants grant_row
      where grant_row.user_id = target_user_id
        and grant_row.play_date = target_play_date
        and grant_row.status in ('verified', 'consumed')
    ) as ad_watched
  ), availability as (
    select
      play_summary.*,
      ad_summary.ad_watched,
      play_summary.challenge_pending
        or (
          not play_summary.practice_pending
          and not play_summary.challenge_played
          and not play_summary.challenge_in_progress
          and play_summary.play_count < 3
        ) as challenge_available,
      play_summary.practice_pending
        or (
          not play_summary.challenge_pending
          and not play_summary.challenge_in_progress
          and (
            play_summary.play_count = 0
            or play_summary.challenge_played
            or play_summary.play_count < 2
          )
        ) as practice_available
    from play_summary
    cross join ad_summary
  )
  select jsonb_build_object(
    'play_count', availability.play_count,
    'practice_count', availability.practice_count,
    'challenge_played', availability.challenge_played,
    'challenge_in_progress', availability.challenge_in_progress,
    'challenge_pending', availability.challenge_pending,
    'practice_pending', availability.practice_pending,
    'play_pending',
      availability.challenge_pending or availability.practice_pending,
    'ad_watched', availability.ad_watched,
    'challenge_available', availability.challenge_available,
    'practice_available', availability.practice_available,
    'challenge_requires_ad',
      availability.challenge_available
      and not availability.challenge_pending
      and availability.practice_count > 0
      and not availability.ad_watched,
    'practice_requires_ad',
      availability.practice_available
      and not availability.practice_pending
      and availability.challenge_played
      and availability.practice_count = 0
      and not availability.ad_watched,
    'next_play_requires_ad',
      (
        availability.challenge_available
        and not availability.challenge_pending
        and availability.practice_count > 0
        and not availability.ad_watched
      ) or (
        availability.practice_available
        and not availability.practice_pending
        and availability.challenge_played
        and availability.practice_count = 0
        and not availability.ad_watched
      )
  )
  from availability;
$$;

create or replace function public.claim_daily_practice_internal(
  expected_play_date date,
  play_request_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  is_test boolean := false;
  choice_state jsonb;
  play_count integer;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  existing_session public.daily_play_sessions;
  verified_grant public.rewarded_ad_grants;
  claimed_session public.daily_play_sessions;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if play_request_id is null then
    raise exception 'play request id required';
  end if;

  select coalesce(profile.is_test_account, false)
  into is_test
  from public.profiles profile
  where profile.id = current_user_id;
  if coalesce(is_test, false) then
    raise exception 'practice unavailable in test mode';
  end if;
  if public.kakao_required_for_daily_play(play_day) then
    raise exception 'kakao account required for daily play';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select * into existing_session
  from public.daily_play_sessions session
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.client_request_id = play_request_id;

  -- App deletion also deletes local request IDs. Recover the one unstarted
  -- practice session instead of allocating another ordinal.
  if existing_session.id is null then
    select * into existing_session
    from public.daily_play_sessions session
    where session.user_id = current_user_id
      and session.play_date = play_day
      and session.play_mode = 'practice'
      and session.started_at is null
    order by session.created_at, session.id
    limit 1
    for update;

    if existing_session.id is not null
      and existing_session.client_request_id is distinct from play_request_id then
      update public.daily_play_sessions
      set client_request_id = play_request_id
      where id = existing_session.id
      returning * into existing_session;
    end if;
  end if;

  if existing_session.id is not null then
    return jsonb_build_object(
      'id', existing_session.id,
      'ordinal', existing_session.ordinal,
      'status', 'practice',
      'grant_type', case
        when existing_session.reward_grant_id is null then 'practice_daily'
        else 'practice_ad'
      end,
      'game_id', existing_session.game_id,
      'game_version', existing_session.game_version,
      'game_duration_seconds', existing_session.game_duration_seconds,
      'play_date', existing_session.play_date,
      'issued_at', existing_session.created_at,
      'client_request_id', existing_session.client_request_id
    );
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'practice_available')::boolean, false) then
    raise exception 'practice is not available';
  end if;
  if coalesce((choice_state->>'practice_requires_ad')::boolean, false) then
    raise exception 'practice requires rewarded ad';
  end if;

  select * into verified_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
    and grant_row.status = 'verified'
  order by grant_row.prepared_at desc
  limit 1
  for update;

  play_count := coalesce((choice_state->>'play_count')::integer, 0);
  if play_count = 0 then
    perform public.claim_first_device_play(current_user_id, play_day);
  end if;

  scheduled_game := public.ensure_daily_game(play_day);
  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;
  if selected_game.game_id is null then
    raise exception 'game version not found';
  end if;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode, reward_grant_id,
    game_id, game_version, game_duration_seconds, created_at,
    client_request_id
  ) values (
    current_user_id,
    play_day,
    (play_count + 1)::smallint,
    'practice',
    verified_grant.id,
    selected_game.game_id,
    selected_game.version,
    selected_game.duration_seconds,
    coalesce(verified_grant.prepared_at, now()),
    play_request_id
  )
  returning * into claimed_session;

  if verified_grant.id is not null then
    update public.rewarded_ad_grants
    set status = 'consumed', consumed_at = now()
    where id = verified_grant.id;
  end if;

  return jsonb_build_object(
    'id', claimed_session.id,
    'ordinal', claimed_session.ordinal,
    'status', 'practice',
    'grant_type', case
      when verified_grant.id is null then 'practice_daily'
      else 'practice_ad'
    end,
    'game_id', claimed_session.game_id,
    'game_version', claimed_session.game_version,
    'game_duration_seconds', claimed_session.game_duration_seconds,
    'play_date', claimed_session.play_date,
    'issued_at', claimed_session.created_at,
    'client_request_id', claimed_session.client_request_id
  );
end;
$$;

create function public.confirm_daily_play_started(play_reference_id uuid)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  target_session public.daily_play_sessions;
  target_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select * into target_session
  from public.daily_play_sessions session
  where session.user_id = current_user_id
    and session.play_date = play_day
    and (session.id = play_reference_id or session.attempt_id = play_reference_id)
  for update;

  if target_session.id is null then
    raise exception 'play session not found';
  end if;

  if target_session.attempt_id is not null then
    select * into target_attempt
    from public.attempts attempt
    where attempt.id = target_session.attempt_id
      and attempt.user_id = current_user_id
    for update;
    if target_attempt.id is null or target_attempt.status <> 'issued' then
      raise exception 'active attempt not found';
    end if;
  end if;

  update public.daily_play_sessions
  set started_at = coalesce(started_at, now())
  where id = target_session.id
  returning * into target_session;

  return jsonb_build_object(
    'id', target_session.id,
    'play_mode', target_session.play_mode,
    'started_at', target_session.started_at
  );
end;
$$;

revoke all on function public.confirm_daily_play_started(uuid) from public;
grant execute on function public.confirm_daily_play_started(uuid)
  to authenticated;

create or replace function public.expire_attempt(attempt_id uuid)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  expired_attempt public.attempts;
  attempt_started boolean := false;
begin
  select session.started_at is not null
  into attempt_started
  from public.daily_play_sessions session
  where session.attempt_id = $1
    and session.user_id = (select auth.uid());

  if not coalesce(attempt_started, false) then
    select * into expired_attempt
    from public.attempts attempt
    where attempt.id = $1
      and attempt.user_id = (select auth.uid())
      and attempt.status = 'issued';
    if expired_attempt.id is null then
      raise exception 'active attempt not found';
    end if;
    return expired_attempt;
  end if;

  update public.attempts
  set status = 'expired'
  where id = $1
    and user_id = (select auth.uid())
    and status = 'issued'
  returning * into expired_attempt;

  if expired_attempt.id is null then
    raise exception 'active attempt not found';
  end if;
  return expired_attempt;
end;
$$;

create function public.mark_scored_play_started()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  update public.daily_play_sessions
  set started_at = coalesce(started_at, now())
  where attempt_id = new.attempt_id;
  return new;
end;
$$;

create trigger scores_mark_play_started_before_insert
before insert on public.scores
for each row execute function public.mark_scored_play_started();

revoke all on function public.mark_scored_play_started()
  from public, anon, authenticated, service_role;

alter function public.get_today_state()
rename to get_today_state_before_confirmed_start;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_confirmed_start();
  current_user_id uuid := (select auth.uid());
  play_day date := (state->>'play_date')::date;
  choice_state jsonb := public.daily_play_choice_state(
    current_user_id,
    play_day
  );
  challenge_pending boolean := coalesce(
    (choice_state->>'challenge_pending')::boolean,
    false
  );
  practice_pending boolean := coalesce(
    (choice_state->>'practice_pending')::boolean,
    false
  );
begin
  state := state || jsonb_build_object(
    'challenge_pending', challenge_pending,
    'practice_pending', practice_pending,
    'practice_play_count',
      coalesce((choice_state->>'practice_count')::integer, 0)
  );

  if challenge_pending or practice_pending then
    return state || jsonb_build_object(
      'challenge_available',
        coalesce((choice_state->>'challenge_available')::boolean, false),
      'practice_available',
        coalesce((choice_state->>'practice_available')::boolean, false),
      'challenge_requires_ad', false,
      'practice_requires_ad', false,
      'next_play_requires_ad', false,
      'device_daily_limit_reached', false
    );
  end if;

  return state;
end;
$$;

revoke all on function public.get_today_state_before_confirmed_start()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

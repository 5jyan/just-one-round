-- Make every start boundary retry-safe and authoritative. Clients refresh
-- before starting, but the RPCs still defend against a response race, a lost
-- response, or an app terminated between ad verification and grant claim.

alter table public.daily_play_sessions
  add column client_request_id uuid;

create unique index daily_play_sessions_client_request_idx
  on public.daily_play_sessions (user_id, play_date, client_request_id)
  where client_request_id is not null;

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
  is_test boolean := false;
  choice_state jsonb;
  play_count integer;
  next_ordinal smallint;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  existing_attempt public.attempts;
  verified_grant public.rewarded_ad_grants;
  claimed_attempt public.attempts;
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

  if coalesce(is_test, false) then
    return public.claim_daily_attempt_without_kakao(expected_play_date);
  end if;
  if public.kakao_required_for_daily_play(play_day) then
    raise exception 'kakao account required for daily play';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select attempt.*
  into existing_attempt
  from public.daily_play_sessions session
  join public.attempts attempt on attempt.id = session.attempt_id
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.play_mode = 'challenge'
  order by session.ordinal
  limit 1;

  -- Retrying a request whose response was lost must return the same live
  -- challenge. A stale client must never replay a completed/expired attempt.
  if existing_attempt.id is not null then
    if existing_attempt.status = 'issued' then
      return existing_attempt;
    end if;
    raise exception 'challenge is not available';
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'challenge_available')::boolean, false) then
    raise exception 'challenge is not available';
  end if;
  if coalesce((choice_state->>'challenge_requires_ad')::boolean, false) then
    raise exception 'challenge requires rewarded ad';
  end if;

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

  -- If the app closed after SSV verification, finish consuming that same ad
  -- when the refreshed client starts the challenge without another ad view.
  select * into verified_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'ranked_extra'
    and grant_row.status = 'verified'
  order by grant_row.prepared_at desc
  limit 1
  for update;

  next_ordinal := (play_count + 1)::smallint;
  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type, issued_at
  ) values (
    current_user_id,
    play_day,
    selected_game.game_id,
    selected_game.version,
    next_ordinal,
    (
      case
        when verified_grant.id is null then 'daily'
        else 'rewarded_ad'
      end
    )::public.attempt_grant_type,
    coalesce(verified_grant.prepared_at, now())
  )
  returning * into claimed_attempt;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode, attempt_id, reward_grant_id,
    game_id, game_version, game_duration_seconds, created_at
  ) values (
    current_user_id,
    play_day,
    next_ordinal,
    'challenge',
    claimed_attempt.id,
    verified_grant.id,
    selected_game.game_id,
    selected_game.version,
    selected_game.duration_seconds,
    claimed_attempt.issued_at
  );

  if verified_grant.id is not null then
    update public.rewarded_ad_grants
    set status = 'consumed', consumed_at = now()
    where id = verified_grant.id;
  end if;

  return claimed_attempt;
end;
$$;

create function public.claim_daily_practice_internal(
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
      'issued_at', existing_session.created_at
    );
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'practice_available')::boolean, false) then
    raise exception 'practice is not available';
  end if;
  if coalesce((choice_state->>'practice_requires_ad')::boolean, false) then
    raise exception 'practice requires rewarded ad';
  end if;

  -- If the process stopped after SSV verification but before
  -- claim_practice_attempt, attach and consume the verified grant here.
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
    'issued_at', claimed_session.created_at
  );
end;
$$;

create or replace function public.claim_daily_practice(
  expected_play_date date
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
begin
  return public.claim_daily_practice_internal(
    expected_play_date,
    gen_random_uuid()
  );
end;
$$;

create function public.claim_daily_practice_v2(
  expected_play_date date,
  play_request_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
begin
  return public.claim_daily_practice_internal(
    expected_play_date,
    play_request_id
  );
end;
$$;

revoke all on function public.claim_daily_practice_internal(date, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_daily_practice(date) from public;
revoke all on function public.claim_daily_practice_v2(date, uuid) from public;
grant execute on function public.claim_daily_practice(date) to authenticated;
grant execute on function public.claim_daily_practice_v2(date, uuid)
  to authenticated;

-- The legacy base state knows about a device claim, while the newer
-- play-choice fields are calculated from account sessions. Reconcile both so
-- the home screen never presents a start button that the device guard must
-- reject.
alter function public.get_today_state()
rename to get_today_state_before_start_state_hardening;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_start_state_hardening();
  is_test boolean := coalesce((state->>'test_mode')::boolean, false);
  play_count integer := coalesce((state->>'play_count')::integer, 0);
  device_limit_reached boolean :=
    not is_test
    and play_count = 0
    and coalesce((state->>'daily_claimed')::boolean, false);
begin
  if device_limit_reached then
    return state || jsonb_build_object(
      'challenge_available', false,
      'practice_available', false,
      'challenge_requires_ad', false,
      'practice_requires_ad', false,
      'next_play_requires_ad', false,
      'device_daily_limit_reached', true
    );
  end if;

  return state || jsonb_build_object(
    'device_daily_limit_reached', false
  );
end;
$$;

revoke all on function public.get_today_state_before_start_state_hardening()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

-- PostgreSQL composite rows with nullable columns are neither wholly NULL nor
-- wholly NOT NULL. Check the primary key so a consumed practice grant is
-- reliably returned instead of attempting to create a second daily ad.
create or replace function public.prepare_practice_ad(
  expected_play_date date
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  choice_state jsonb;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  active_grant public.rewarded_ad_grants;
  is_test boolean := false;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if not public.rewarded_ads_enabled() then
    raise exception 'rewarded ads disabled';
  end if;

  select coalesce(profile.is_test_account, false)
  into is_test
  from public.profiles profile
  where profile.id = current_user_id;
  if coalesce(is_test, false) then
    raise exception 'practice unavailable in test mode';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'practice_available')::boolean, false)
    or (choice_state->>'play_count')::integer = 0 then
    raise exception 'practice is not available';
  end if;

  select grant_row.* into active_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
    and grant_row.status = 'consumed'
    and exists (
      select 1
      from public.daily_play_sessions session
      where session.reward_grant_id = grant_row.id
        and session.user_id = current_user_id
        and session.play_date = play_day
        and session.play_mode = 'practice'
    )
  order by grant_row.consumed_at desc
  limit 1;

  if active_grant.id is not null then
    return jsonb_build_object(
      'id', active_grant.id,
      'user_id', active_grant.user_id,
      'status', active_grant.status,
      'expires_at', active_grant.expires_at
    );
  end if;

  scheduled_game := public.ensure_daily_game(play_day);
  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;
  if selected_game.game_id is null then
    raise exception 'game version not found';
  end if;

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and status in ('prepared', 'verified')
    and expires_at <= now();

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and grant_purpose <> 'practice'
    and status = 'prepared';

  select * into active_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
    and grant_row.status in ('prepared', 'verified')
    and grant_row.expires_at > now()
  order by grant_row.prepared_at desc
  limit 1
  for update;

  if active_grant.id is null and exists (
    select 1 from public.rewarded_ad_grants grant_row
    where grant_row.user_id = current_user_id
      and grant_row.play_date = play_day
      and grant_row.status in ('prepared', 'verified')
  ) then
    raise exception 'another reward is pending';
  end if;

  if active_grant.id is null then
    insert into public.rewarded_ad_grants (
      user_id,
      play_date,
      grant_purpose,
      game_id,
      game_version,
      game_duration_seconds,
      expires_at
    ) values (
      current_user_id,
      play_day,
      'practice',
      selected_game.game_id,
      selected_game.version,
      selected_game.duration_seconds,
      public.next_daily_reset_at(play_day)
    )
    returning * into active_grant;
  end if;

  return jsonb_build_object(
    'id', active_grant.id,
    'user_id', active_grant.user_id,
    'status', active_grant.status,
    'expires_at', active_grant.expires_at
  );
end;
$$;

-- Keep the grant-claim RPCs idempotent after a response is lost. Use primary
-- keys for composite-row presence checks because sessions and attempts contain
-- nullable columns.
create or replace function public.claim_rewarded_attempt_without_kakao(
  reward_session_id uuid
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  target_grant public.rewarded_ad_grants;
  existing_session public.daily_play_sessions;
  existing_attempt public.attempts;
  choice_state jsonb;
  next_ordinal smallint;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select * into target_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.id = reward_session_id
    and grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'ranked_extra'
  for update;

  if target_grant.id is null then
    raise exception 'daily game changed';
  end if;

  if target_grant.status = 'consumed' then
    select * into existing_session
    from public.daily_play_sessions session
    where session.reward_grant_id = reward_session_id;

    if existing_session.id is not null then
      select * into existing_attempt
      from public.attempts attempt
      where attempt.id = existing_session.attempt_id;
      if existing_attempt.id is not null then
        if existing_attempt.status = 'issued' then
          return existing_attempt;
        end if;
        raise exception 'challenge is not available';
      end if;
    end if;
  end if;

  if target_grant.status <> 'verified' then
    raise exception 'reward verification pending';
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'challenge_available')::boolean, false)
    or (choice_state->>'play_count')::integer = 0 then
    raise exception 'challenge is not available';
  end if;

  next_ordinal := ((choice_state->>'play_count')::integer + 1)::smallint;
  scheduled_game := public.ensure_daily_game(play_day);

  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;

  if selected_game.game_id is null then
    raise exception 'game version not found';
  end if;

  insert into public.attempts (
    user_id,
    play_date,
    game_id,
    game_version,
    ordinal,
    grant_type,
    issued_at
  ) values (
    current_user_id,
    play_day,
    selected_game.game_id,
    selected_game.version,
    next_ordinal,
    'rewarded_ad',
    target_grant.prepared_at
  )
  returning * into claimed_attempt;

  insert into public.daily_play_sessions (
    user_id,
    play_date,
    ordinal,
    play_mode,
    attempt_id,
    reward_grant_id,
    game_id,
    game_version,
    game_duration_seconds,
    created_at
  ) values (
    current_user_id,
    play_day,
    next_ordinal,
    'challenge',
    claimed_attempt.id,
    target_grant.id,
    selected_game.game_id,
    selected_game.version,
    selected_game.duration_seconds,
    target_grant.prepared_at
  );

  update public.rewarded_ad_grants
  set status = 'consumed', consumed_at = now()
  where id = reward_session_id;

  return claimed_attempt;
end;
$$;

create or replace function public.claim_practice_attempt(
  reward_session_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  target_grant public.rewarded_ad_grants;
  existing_session public.daily_play_sessions;
  choice_state jsonb;
  next_ordinal smallint;
  claimed_session public.daily_play_sessions;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select * into target_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.id = reward_session_id
    and grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
  for update;

  if target_grant.id is null then
    raise exception 'practice session not found';
  end if;

  if target_grant.status = 'consumed' then
    select * into existing_session
    from public.daily_play_sessions session
    where session.reward_grant_id = reward_session_id;
    if existing_session.id is not null then
      return jsonb_build_object(
        'id', existing_session.id,
        'ordinal', existing_session.ordinal,
        'status', 'practice',
        'grant_type', 'practice_ad',
        'game_id', existing_session.game_id,
        'game_version', existing_session.game_version,
        'game_duration_seconds', existing_session.game_duration_seconds,
        'play_date', existing_session.play_date,
        'issued_at', existing_session.created_at
      );
    end if;
  end if;

  if target_grant.status <> 'verified' then
    raise exception 'reward verification pending';
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'practice_available')::boolean, false)
    or (choice_state->>'play_count')::integer = 0 then
    raise exception 'practice is not available';
  end if;

  next_ordinal := ((choice_state->>'play_count')::integer + 1)::smallint;

  insert into public.daily_play_sessions (
    user_id,
    play_date,
    ordinal,
    play_mode,
    reward_grant_id,
    game_id,
    game_version,
    game_duration_seconds,
    created_at
  ) values (
    current_user_id,
    play_day,
    next_ordinal,
    'practice',
    target_grant.id,
    target_grant.game_id,
    target_grant.game_version,
    target_grant.game_duration_seconds,
    target_grant.prepared_at
  )
  returning * into claimed_session;

  update public.rewarded_ad_grants
  set status = 'consumed', consumed_at = now()
  where id = reward_session_id;

  return jsonb_build_object(
    'id', claimed_session.id,
    'ordinal', claimed_session.ordinal,
    'status', 'practice',
    'grant_type', 'practice_ad',
    'game_id', claimed_session.game_id,
    'game_version', claimed_session.game_version,
    'game_duration_seconds', claimed_session.game_duration_seconds,
    'play_date', claimed_session.play_date,
    'issued_at', claimed_session.created_at
  );
end;
$$;

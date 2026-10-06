-- The second ranked challenge is a single choice: rewarded ad or one
-- purchased challenge ticket. Once that choice starts a challenge, no third
-- ranked challenge is available on the same play date.

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
      count(*) filter (where session.play_mode = 'practice')::integer
        as practice_session_count,
      count(*) filter (
        where session.play_mode = 'practice'
          and session.started_at is not null
      )::integer as practice_count,
      count(*) filter (where session.play_mode = 'challenge')::integer
        as challenge_session_count,
      count(*) filter (
        where session.play_mode = 'challenge'
          and session.entitlement_source = 'store_ticket'
      )::integer as store_challenge_session_count,
      count(*) filter (
        where session.play_mode = 'challenge'
          and session.started_at is not null
      )::integer as challenge_count,
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
    select
      count(*) filter (
        where grant_row.grant_purpose = 'practice'
          and grant_row.status in ('verified', 'consumed')
      )::integer as practice_reward_count,
      coalesce(bool_or(
        grant_row.grant_purpose = 'ranked_extra'
          and grant_row.status in ('verified', 'consumed')
      ), false) as ranked_reward_earned,
      coalesce(bool_or(
        grant_row.grant_purpose = 'ranked_extra'
          and grant_row.status = 'consumed'
      ), false) as ranked_reward_consumed
    from public.rewarded_ad_grants grant_row
    where grant_row.user_id = target_user_id
      and grant_row.play_date = target_play_date
  ), inventory as (
    select
      coalesce(profile.store_practice_tickets, 0)::integer
        as store_practice_tickets,
      coalesce(profile.store_challenge_tickets, 0)::integer
        as store_challenge_tickets
    from public.profiles profile
    where profile.id = target_user_id
  ), entitlement as (
    select
      play_summary.*,
      ad_summary.*,
      inventory.*,
      1 + (ad_summary.practice_reward_count * 2)
        as daily_practice_capacity
    from play_summary
    cross join ad_summary
    cross join inventory
  ), availability as (
    select
      entitlement.*,
      greatest(
        0,
        entitlement.daily_practice_capacity
          - entitlement.practice_session_count
      ) + entitlement.store_practice_tickets
        as practice_tickets_remaining,
      entitlement.challenge_pending or (
        not entitlement.practice_pending
        and not entitlement.challenge_in_progress
        and (
          entitlement.challenge_session_count = 0
          or (
            entitlement.challenge_session_count = 1
            and (
              not entitlement.ranked_reward_consumed
              or (
                entitlement.store_challenge_tickets > 0
                and entitlement.store_challenge_session_count = 0
              )
            )
          )
        )
      ) as challenge_available,
      entitlement.challenge_session_count = 1
        and not entitlement.practice_pending
        and not entitlement.challenge_in_progress
        and (
          not entitlement.ranked_reward_consumed
          or (
            entitlement.store_challenge_tickets > 0
            and entitlement.store_challenge_session_count = 0
          )
        ) as extra_challenge_available,
      entitlement.challenge_session_count = 1
        and not entitlement.practice_pending
        and not entitlement.challenge_in_progress
        and not entitlement.ranked_reward_earned
        and entitlement.store_challenge_tickets > 0
        and entitlement.store_challenge_session_count = 0
        as challenge_ticket_available
    from entitlement
  )
  select jsonb_build_object(
    'play_count', availability.play_count,
    'practice_count', availability.practice_count,
    'practice_session_count', availability.practice_session_count,
    'challenge_count', availability.challenge_count,
    'challenge_session_count', availability.challenge_session_count,
    'challenge_played', availability.challenge_count > 0,
    'challenge_in_progress', availability.challenge_in_progress,
    'challenge_pending', availability.challenge_pending,
    'practice_pending', availability.practice_pending,
    'play_pending',
      availability.challenge_pending or availability.practice_pending,
    'ad_watched', availability.practice_reward_count > 0,
    'ranked_ad_attempt_used', availability.ranked_reward_consumed,
    'practice_reward_count', availability.practice_reward_count,
    'practice_reward_earned', availability.practice_reward_count > 0,
    'practice_reward_available',
      availability.practice_count > 0
      and availability.practice_tickets_remaining = 0,
    'practice_ticket_capacity',
      availability.daily_practice_capacity
        + availability.store_practice_tickets,
    'practice_tickets_remaining', availability.practice_tickets_remaining,
    'store_practice_tickets', availability.store_practice_tickets,
    'store_challenge_tickets', availability.store_challenge_tickets,
    'store_challenge_used_today',
      availability.store_challenge_session_count > 0,
    'challenge_available', availability.challenge_available,
    'extra_challenge_available', availability.extra_challenge_available,
    'challenge_ticket_available', availability.challenge_ticket_available,
    'practice_available',
      availability.practice_pending or (
        not availability.challenge_pending
        and not availability.challenge_in_progress
        and availability.practice_tickets_remaining > 0
      ),
    'challenge_requires_ad', false,
    'practice_requires_ad', false,
    'next_play_requires_ad', false
  )
  from availability;
$$;

-- Test accounts still use unlimited attempts, but build 12 requires every
-- issued attempt to have a matching pending session before the game starts.
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

-- Keep the first challenge RPC free-only. The old implementation could fall
-- through to a store ticket after one challenge, which bypassed the choice UI.
alter function public.claim_daily_attempt(date)
rename to claim_daily_attempt_before_extra_choice;

create function public.claim_daily_attempt(expected_play_date date)
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
  if current_user_id is null then raise exception 'authentication required'; end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  select coalesce(profile.is_test_account, false) into is_test
  from public.profiles profile
  where profile.id = current_user_id;
  if is_test then
    return public.claim_test_daily_attempt_with_session(expected_play_date);
  end if;

  select attempt.* into live_attempt
  from public.daily_play_sessions session
  join public.attempts attempt on attempt.id = session.attempt_id
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.play_mode = 'challenge'
    and (session.started_at is null or attempt.status = 'issued')
  order by session.ordinal desc
  limit 1;
  if live_attempt.id is not null then return live_attempt; end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if coalesce((choice_state->>'challenge_session_count')::integer, 0) <> 0 then
    raise exception 'extra challenge choice required';
  end if;
  return public.claim_daily_attempt_before_extra_choice(expected_play_date);
end;
$$;

create function public.claim_challenge_ticket_attempt(
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
  live_attempt public.attempts;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  next_ordinal smallint;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text), hashtext(play_day::text)
  );

  select attempt.* into live_attempt
  from public.daily_play_sessions session
  join public.attempts attempt on attempt.id = session.attempt_id
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.play_mode = 'challenge'
    and (session.started_at is null or attempt.status = 'issued')
  order by session.ordinal desc
  limit 1;
  if live_attempt.id is not null then return live_attempt; end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'challenge_ticket_available')::boolean, false)
  then
    raise exception 'challenge ticket is not available';
  end if;

  update public.profiles profile
  set store_challenge_tickets = profile.store_challenge_tickets - 1,
      updated_at = now()
  where profile.id = current_user_id
    and profile.store_challenge_tickets > 0;
  if not found then raise exception 'challenge ticket is not available'; end if;

  scheduled_game := public.ensure_daily_game(play_day);
  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;
  next_ordinal := (
    select (coalesce(max(session.ordinal), 0) + 1)::smallint
    from public.daily_play_sessions session
    where session.user_id = current_user_id
      and session.play_date = play_day
  );

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type, issued_at
  ) values (
    current_user_id, play_day, selected_game.game_id, selected_game.version,
    next_ordinal, 'store_ticket', now()
  ) returning * into claimed_attempt;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode, attempt_id,
    game_id, game_version, game_duration_seconds, created_at,
    entitlement_source
  ) values (
    current_user_id, play_day, next_ordinal, 'challenge', claimed_attempt.id,
    selected_game.game_id, selected_game.version, selected_game.duration_seconds,
    claimed_attempt.issued_at, 'store_ticket'
  );
  return claimed_attempt;
end;
$$;

alter function public.get_today_state()
rename to get_today_state_before_extra_challenge_choice;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_extra_challenge_choice();
  current_user_id uuid := (select auth.uid());
  play_day date := (state->>'play_date')::date;
  choice_state jsonb := public.daily_play_choice_state(current_user_id, play_day);
  device_limited boolean := coalesce(
    (state->>'device_daily_limit_reached')::boolean, false
  );
  ads_enabled boolean := public.rewarded_ads_enabled();
  extra_available boolean :=
    coalesce((choice_state->>'extra_challenge_available')::boolean, false)
    and (ads_enabled or coalesce(
      (choice_state->>'challenge_ticket_available')::boolean, false
    ));
begin
  if coalesce((state->>'test_mode')::boolean, false) then return state; end if;
  return state || jsonb_build_object(
    'play_count', coalesce((choice_state->>'play_count')::integer, 0),
    'practice_play_count',
      coalesce((choice_state->>'practice_count')::integer, 0),
    'challenge_pending',
      coalesce((choice_state->>'challenge_pending')::boolean, false),
    'practice_pending',
      coalesce((choice_state->>'practice_pending')::boolean, false),
    'challenge_available',
      not device_limited
      and (
        coalesce((choice_state->>'challenge_pending')::boolean, false)
        or (
          coalesce((choice_state->>'challenge_available')::boolean, false)
          and (
            coalesce((choice_state->>'challenge_session_count')::integer, 0) = 0
            or extra_available
          )
        )
      ),
    'extra_challenge_available', not device_limited and extra_available,
    'challenge_ticket_available', not device_limited and coalesce(
      (choice_state->>'challenge_ticket_available')::boolean, false
    ),
    'practice_available',
      not device_limited
      and coalesce((choice_state->>'practice_available')::boolean, false),
    'challenge_requires_ad', false,
    'practice_requires_ad', false,
    'next_play_requires_ad', false,
    'practice_ticket_capacity',
      coalesce((choice_state->>'practice_ticket_capacity')::integer, 1),
    'practice_tickets_remaining', case when device_limited then 0 else
      coalesce((choice_state->>'practice_tickets_remaining')::integer, 0) end,
    'practice_reward_available',
      not device_limited and public.rewarded_ads_enabled()
      and coalesce((choice_state->>'practice_reward_available')::boolean, false),
    'store_practice_tickets',
      coalesce((choice_state->>'store_practice_tickets')::integer, 0),
    'store_challenge_tickets',
      coalesce((choice_state->>'store_challenge_tickets')::integer, 0),
    'ranked_ad_attempt_used',
      coalesce((choice_state->>'ranked_ad_attempt_used')::boolean, false),
    'ad_attempt_available', not device_limited and extra_available and ads_enabled
  );
end;
$$;

revoke all on function public.claim_daily_attempt_before_extra_choice(date)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_test_daily_attempt_with_session(date)
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state_before_extra_challenge_choice()
  from public, anon, authenticated, service_role;
revoke all on function public.claim_challenge_ticket_attempt(date)
  from public, anon;
revoke all on function public.claim_daily_attempt(date) from public;
revoke all on function public.get_today_state() from public;
grant execute on function public.claim_daily_attempt(date) to authenticated;
grant execute on function public.claim_challenge_ticket_attempt(date)
  to authenticated;
grant execute on function public.get_today_state() to authenticated;

comment on function public.claim_challenge_ticket_attempt(date) is
  'Consumes one challenge ticket for the single optional extra daily challenge.';

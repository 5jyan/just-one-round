-- Let players refill practice tickets whenever their balance reaches zero.
-- Each explicitly opted-in rewarded ad grants two tickets. Rewards cannot be
-- stockpiled while tickets remain, and each SSV session remains idempotent.

drop trigger if exists rewarded_ad_grants_one_per_day_before_insert
  on public.rewarded_ad_grants;
drop function if exists public.enforce_one_daily_rewarded_ad();

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
    select count(*) filter (
      where grant_row.grant_purpose = 'practice'
        and grant_row.status in ('verified', 'consumed')
    )::integer as practice_reward_count
    from public.rewarded_ad_grants grant_row
    where grant_row.user_id = target_user_id
      and grant_row.play_date = target_play_date
  ), entitlement as (
    select
      play_summary.*,
      ad_summary.practice_reward_count,
      1 + (ad_summary.practice_reward_count * 2)
        as practice_ticket_capacity
    from play_summary
    cross join ad_summary
  ), availability as (
    select
      entitlement.*,
      greatest(
        0,
        entitlement.practice_ticket_capacity
          - entitlement.practice_session_count
      )::integer as practice_tickets_remaining
    from entitlement
  )
  select jsonb_build_object(
    'play_count', availability.play_count,
    'practice_count', availability.practice_count,
    'practice_session_count', availability.practice_session_count,
    'challenge_played', availability.challenge_played,
    'challenge_in_progress', availability.challenge_in_progress,
    'challenge_pending', availability.challenge_pending,
    'practice_pending', availability.practice_pending,
    'play_pending',
      availability.challenge_pending or availability.practice_pending,
    'ad_watched', availability.practice_reward_count > 0,
    'practice_reward_count', availability.practice_reward_count,
    'practice_reward_earned', availability.practice_reward_count > 0,
    'practice_reward_available',
      availability.practice_count > 0
      and availability.practice_tickets_remaining = 0,
    'practice_ticket_capacity', availability.practice_ticket_capacity,
    'practice_tickets_remaining', availability.practice_tickets_remaining,
    'challenge_available',
      availability.challenge_pending
      or (
        not availability.practice_pending
        and not availability.challenge_played
        and not availability.challenge_in_progress
      ),
    'practice_available',
      availability.practice_pending
      or (
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

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and grant_purpose = 'practice'
    and status in ('prepared', 'verified')
    and expires_at <= now();

  -- Reuse an unfinished session so a lost response, delayed SSV callback, or
  -- repeated tap can recover without showing or granting a duplicate ad.
  select grant_row.* into active_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
    and grant_row.status in ('prepared', 'verified')
    and grant_row.expires_at > now()
  order by grant_row.prepared_at desc
  limit 1
  for update;

  if active_grant.id is null then
    choice_state := public.daily_play_choice_state(current_user_id, play_day);
    if coalesce((choice_state->>'practice_count')::integer, 0) = 0 then
      raise exception 'free practice ticket must be used first';
    end if;
    if coalesce(
      (choice_state->>'practice_tickets_remaining')::integer,
      0
    ) > 0 then
      raise exception 'practice tickets remain';
    end if;

    scheduled_game := public.ensure_daily_game(play_day);
    select * into selected_game
    from public.game_rule_versions versioned
    where versioned.game_id = scheduled_game.game_id
      and versioned.version = scheduled_game.game_version;
    if selected_game.game_id is null then
      raise exception 'game version not found';
    end if;

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

comment on function public.prepare_practice_ad(date) is
  'Prepares one two-ticket practice refill only when the current balance is zero.';

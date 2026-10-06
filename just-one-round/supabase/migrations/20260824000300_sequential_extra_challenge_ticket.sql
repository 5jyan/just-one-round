-- Extra ranked challenges are sequential: the rewarded-ad challenge must be
-- used first, then one purchased challenge ticket may be used afterward.
-- Keep the already-applied choice migration intact and replace its functions
-- in a follow-up migration.

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
          and session.entitlement_source = 'rewarded_ad'
      )::integer as rewarded_challenge_session_count,
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
      entitlement.challenge_session_count = 1
        and not entitlement.practice_pending
        and not entitlement.challenge_pending
        and not entitlement.challenge_in_progress
        and not entitlement.ranked_reward_consumed
        as ad_challenge_available,
      entitlement.challenge_session_count = 2
        and entitlement.rewarded_challenge_session_count = 1
        and entitlement.ranked_reward_consumed
        and not entitlement.practice_pending
        and not entitlement.challenge_pending
        and not entitlement.challenge_in_progress
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
    'challenge_available',
      availability.challenge_pending or (
        not availability.practice_pending
        and not availability.challenge_in_progress
        and (
          availability.challenge_session_count = 0
          or availability.ad_challenge_available
          or availability.challenge_ticket_available
        )
      ),
    'ad_challenge_available', availability.ad_challenge_available,
    'extra_challenge_available',
      availability.ad_challenge_available
      or availability.challenge_ticket_available,
    'challenge_ticket_available', availability.challenge_ticket_available,
    'practice_available',
      availability.practice_pending or (
        not availability.challenge_pending
        and not availability.challenge_in_progress
        and availability.practice_tickets_remaining > 0
      ),
    'challenge_requires_ad', availability.ad_challenge_available,
    'practice_requires_ad', false,
    'next_play_requires_ad', availability.ad_challenge_available
  )
  from availability;
$$;

create or replace function public.get_today_state()
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
  ad_challenge_available boolean := not device_limited
    and ads_enabled
    and coalesce(
      (choice_state->>'ad_challenge_available')::boolean, false
    );
  challenge_ticket_available boolean := not device_limited
    and coalesce(
      (choice_state->>'challenge_ticket_available')::boolean, false
    );
  extra_challenge_available boolean :=
    ad_challenge_available or challenge_ticket_available;
  challenge_session_count integer := coalesce(
    (choice_state->>'challenge_session_count')::integer, 0
  );
  challenge_pending boolean := coalesce(
    (choice_state->>'challenge_pending')::boolean, false
  );
begin
  if coalesce((state->>'test_mode')::boolean, false) then return state; end if;
  return state || jsonb_build_object(
    'play_count', coalesce((choice_state->>'play_count')::integer, 0),
    'practice_play_count',
      coalesce((choice_state->>'practice_count')::integer, 0),
    'challenge_pending', challenge_pending,
    'practice_pending', coalesce(
      (choice_state->>'practice_pending')::boolean, false
    ),
    'challenge_available',
      not device_limited
      and coalesce((choice_state->>'challenge_available')::boolean, false)
      and (
        challenge_pending
        or challenge_session_count = 0
        or extra_challenge_available
      ),
    'ad_challenge_available', ad_challenge_available,
    'extra_challenge_available', extra_challenge_available,
    'challenge_ticket_available', challenge_ticket_available,
    'practice_available', not device_limited and coalesce(
      (choice_state->>'practice_available')::boolean, false
    ),
    'challenge_requires_ad', ad_challenge_available,
    'practice_requires_ad', false,
    'next_play_requires_ad', ad_challenge_available,
    'practice_ticket_capacity', coalesce(
      (choice_state->>'practice_ticket_capacity')::integer, 1
    ),
    'practice_tickets_remaining', case when device_limited then 0 else
      coalesce((choice_state->>'practice_tickets_remaining')::integer, 0)
      end,
    'practice_reward_available',
      not device_limited and public.rewarded_ads_enabled()
      and coalesce((choice_state->>'practice_reward_available')::boolean, false),
    'store_practice_tickets', coalesce(
      (choice_state->>'store_practice_tickets')::integer, 0
    ),
    'store_challenge_tickets', coalesce(
      (choice_state->>'store_challenge_tickets')::integer, 0
    ),
    'ranked_ad_attempt_used', coalesce(
      (choice_state->>'ranked_ad_attempt_used')::boolean, false
    ),
    'ad_attempt_available', ad_challenge_available
  );
end;
$$;

comment on function public.get_today_state() is
  'Exposes the sequential free, rewarded-ad, and challenge-ticket play state.';

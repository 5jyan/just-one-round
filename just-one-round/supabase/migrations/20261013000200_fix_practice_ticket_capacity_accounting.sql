-- Store-funded practice has already consumed inventory; do not deduct it
-- again from daily/ad capacity. Keep total play statistics unchanged.

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
          and session.entitlement_source <> 'store_ticket'
      )::integer as daily_practice_session_count,
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
          - entitlement.daily_practice_session_count
      ) + entitlement.store_practice_tickets
        as practice_tickets_remaining,
      entitlement.challenge_session_count = 1
        and not entitlement.practice_pending
        and not entitlement.challenge_pending
        and not entitlement.challenge_in_progress
        and not entitlement.ranked_reward_consumed
        as ad_challenge_available,
      -- Once the rewarded-ad challenge has been consumed, every remaining
      -- store ticket is eligible. Do not count store sessions here: the
      -- persistent inventory balance is the only limit for this path.
      entitlement.challenge_session_count >= 2
        and entitlement.rewarded_challenge_session_count >= 1
        and entitlement.ranked_reward_consumed
        and not entitlement.practice_pending
        and not entitlement.challenge_pending
        and not entitlement.challenge_in_progress
        and entitlement.store_challenge_tickets > 0
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

create or replace function public.consume_store_practice_ticket()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  base_capacity integer;
  existing_practice_sessions integer;
begin
  if new.play_mode <> 'practice' then
    return new;
  end if;

  select 1 + count(*) * 2 into base_capacity
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = new.user_id
    and grant_row.play_date = new.play_date
    and grant_row.grant_purpose = 'practice'
    and grant_row.status in ('verified', 'consumed');

  select count(*) into existing_practice_sessions
  from public.daily_play_sessions session
  where session.user_id = new.user_id
    and session.play_date = new.play_date
    and session.play_mode = 'practice'
    and session.entitlement_source <> 'store_ticket';

  if existing_practice_sessions >= base_capacity then
    update public.profiles profile
    set store_practice_tickets = profile.store_practice_tickets - 1,
        updated_at = now()
    where profile.id = new.user_id
      and profile.store_practice_tickets > 0;
    if not found then
      raise exception 'practice ticket is not available';
    end if;
    new.entitlement_source := 'store_ticket';
  elsif new.reward_grant_id is not null then
    new.entitlement_source := 'rewarded_ad';
  else
    new.entitlement_source := 'daily';
  end if;
  return new;
end;
$$;

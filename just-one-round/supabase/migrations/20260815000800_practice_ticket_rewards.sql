-- Keep the single daily ranked challenge free for every player. Practice uses
-- one free daily ticket, and one explicitly opted-in rewarded ad grants two
-- additional practice tickets. Challenge and practice remain mutually
-- exclusive while a play is pending or in progress.

-- Preserve value for a player who already watched today's ranked ad before
-- this migration: convert the consumed grant into today's practice reward.
-- Unfinished ranked grants are expired because challenge is now always free.
update public.rewarded_ad_grants grant_row
set
  grant_purpose = 'practice',
  game_id = scheduled_game.game_id,
  game_version = scheduled_game.game_version,
  game_duration_seconds = selected_version.duration_seconds
from public.daily_games scheduled_game
join public.game_rule_versions selected_version
  on selected_version.game_id = scheduled_game.game_id
 and selected_version.version = scheduled_game.game_version
where grant_row.grant_purpose = 'ranked_extra'
  and grant_row.status = 'consumed'
  and scheduled_game.play_date = grant_row.play_date;

update public.rewarded_ad_grants
set status = 'expired'
where grant_purpose = 'ranked_extra'
  and status in ('prepared', 'verified');

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
    select exists (
      select 1
      from public.rewarded_ad_grants grant_row
      where grant_row.user_id = target_user_id
        and grant_row.play_date = target_play_date
        and grant_row.grant_purpose = 'practice'
        and grant_row.status in ('verified', 'consumed')
    ) as practice_reward_earned
  ), entitlement as (
    select
      play_summary.*,
      ad_summary.practice_reward_earned,
      1 + case when ad_summary.practice_reward_earned then 2 else 0 end
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
    'ad_watched', availability.practice_reward_earned,
    'practice_reward_earned', availability.practice_reward_earned,
    'practice_reward_available',
      availability.practice_count > 0
      and not availability.practice_reward_earned,
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

-- The ad is prepared only after the free practice ticket has been claimed.
-- This creates a natural value exchange and prevents a player from watching
-- an ad before the device-level free-play guard has succeeded.
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
  if coalesce((choice_state->>'practice_count')::integer, 0) = 0 then
    raise exception 'free practice ticket must be used first';
  end if;

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and status in ('prepared', 'verified')
    and expires_at <= now();

  select grant_row.* into active_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
    and grant_row.status in ('prepared', 'verified', 'consumed')
  order by grant_row.prepared_at desc
  limit 1
  for update;

  if active_grant.id is null then
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

-- SSV verification earns two reusable practice tickets without immediately
-- starting or consuming a practice session. Ticket balance is derived from
-- this one daily grant and the number of claimed practice sessions.
create function public.claim_practice_ticket_reward(
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
  choice_state jsonb;
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
    raise exception 'practice reward session not found';
  end if;
  if target_grant.status not in ('verified', 'consumed') then
    raise exception 'reward verification pending';
  end if;
  if not exists (
    select 1
    from public.daily_play_sessions session
    where session.user_id = current_user_id
      and session.play_date = play_day
      and session.play_mode = 'practice'
      and session.started_at is not null
  ) then
    raise exception 'free practice ticket must be used first';
  end if;

  if target_grant.status = 'verified' then
    update public.rewarded_ad_grants
    set status = 'consumed', consumed_at = now()
    where id = target_grant.id;
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  return jsonb_build_object(
    'tickets_granted', 2,
    'practice_tickets_remaining',
      coalesce((choice_state->>'practice_tickets_remaining')::integer, 0)
  );
end;
$$;

revoke all on function public.claim_practice_ticket_reward(uuid) from public;
grant execute on function public.claim_practice_ticket_reward(uuid)
  to authenticated;

alter function public.get_today_state()
rename to get_today_state_before_practice_tickets;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_practice_tickets();
  current_user_id uuid := (select auth.uid());
  play_day date := (state->>'play_date')::date;
  is_test boolean := coalesce((state->>'test_mode')::boolean, false);
  device_limited boolean := coalesce(
    (state->>'device_daily_limit_reached')::boolean,
    false
  );
  choice_state jsonb := public.daily_play_choice_state(
    current_user_id,
    play_day
  );
  ads_enabled boolean := public.rewarded_ads_enabled();
begin
  if is_test then
    return state || jsonb_build_object(
      'practice_ticket_capacity', 0,
      'practice_tickets_remaining', 0,
      'practice_reward_available', false,
      'practice_reward_earned', false,
      'challenge_requires_ad', false,
      'practice_requires_ad', false,
      'next_play_requires_ad', false
    );
  end if;

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
      and coalesce((choice_state->>'challenge_available')::boolean, false),
    'practice_available',
      not device_limited
      and coalesce((choice_state->>'practice_available')::boolean, false),
    'practice_ticket_capacity',
      coalesce((choice_state->>'practice_ticket_capacity')::integer, 1),
    'practice_tickets_remaining',
      case
        when device_limited then 0
        else coalesce(
          (choice_state->>'practice_tickets_remaining')::integer,
          0
        )
      end,
    'practice_reward_available',
      not device_limited
      and ads_enabled
      and coalesce(
        (choice_state->>'practice_reward_available')::boolean,
        false
      ),
    'practice_reward_earned',
      coalesce((choice_state->>'practice_reward_earned')::boolean, false),
    'challenge_requires_ad', false,
    'practice_requires_ad', false,
    'next_play_requires_ad', false,
    'ad_attempt_available', false
  );
end;
$$;

revoke all on function public.get_today_state_before_practice_tickets()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

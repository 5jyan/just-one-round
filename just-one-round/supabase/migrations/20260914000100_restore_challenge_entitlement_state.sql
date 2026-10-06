-- Restore the sequential ranked challenge state after the nickname-ticket
-- wrapper replaced get_today_state with the pre-sequential state function.
-- Keep automatic result settlement and the nickname-change inventory in the
-- public response while deriving the ad and store-ticket entitlements from
-- the latest daily_play_choice_state implementation.

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb;
  current_user_id uuid := (select auth.uid());
  play_day date;
  choice_state jsonb;
  device_limited boolean;
  ads_enabled boolean;
  ad_challenge_available boolean;
  challenge_ticket_available boolean;
  extra_challenge_available boolean;
  challenge_session_count integer;
  challenge_pending boolean;
  nickname_change_tickets integer;
begin
  perform public.auto_claim_expired_daily_result_rewards();

  -- This is the state body that was superseded by the nickname-ticket
  -- wrapper. It already contains the established home-state fields and
  -- tomorrow preview; the choice overlay below restores the sequential
  -- rewarded-ad-then-store-ticket contract.
  state := public.get_today_state_before_extra_challenge_choice();
  play_day := (state->>'play_date')::date;
  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  device_limited := coalesce(
    (state->>'device_daily_limit_reached')::boolean, false
  );
  ads_enabled := public.rewarded_ads_enabled();
  ad_challenge_available := not device_limited
    and ads_enabled
    and coalesce(
      (choice_state->>'ad_challenge_available')::boolean, false
    );
  challenge_ticket_available := not device_limited
    and coalesce(
      (choice_state->>'challenge_ticket_available')::boolean, false
    );
  extra_challenge_available :=
    ad_challenge_available or challenge_ticket_available;
  challenge_session_count := coalesce(
    (choice_state->>'challenge_session_count')::integer, 0
  );
  challenge_pending := coalesce(
    (choice_state->>'challenge_pending')::boolean, false
  );
  select profile.store_nickname_change_tickets
  into nickname_change_tickets
  from public.profiles profile
  where profile.id = current_user_id;

  if coalesce((state->>'test_mode')::boolean, false) then
    return state || jsonb_build_object(
      'store_nickname_change_tickets',
      coalesce(nickname_change_tickets, 0)
    );
  end if;

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
    'ad_attempt_available', ad_challenge_available,
    'store_nickname_change_tickets', coalesce(
      nickname_change_tickets, 0
    )
  );
end;
$$;

revoke all on function public.get_today_state() from public, anon;
grant execute on function public.get_today_state() to authenticated;

comment on function public.get_today_state() is
  'Exposes sequential challenge entitlements with automatic result settlement.';

-- Add persistent soft-currency tickets. Ranked play order is deliberately:
-- free daily challenge -> one rewarded-ad challenge -> purchased tickets.

alter table public.profiles
  add column store_practice_tickets integer not null default 0,
  add column store_challenge_tickets integer not null default 0,
  add constraint profiles_store_practice_tickets_range
    check (store_practice_tickets between 0 and 9999),
  add constraint profiles_store_challenge_tickets_range
    check (store_challenge_tickets between 0 and 9999);

alter table public.daily_play_sessions
  add column entitlement_source text not null default 'daily'
    check (entitlement_source in ('daily', 'rewarded_ad', 'store_ticket'));

create table public.shop_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  request_id uuid not null,
  item_id text not null check (
    item_id in ('practice_ticket', 'challenge_ticket')
  ),
  quantity integer not null default 1 check (quantity = 1),
  coins_spent integer not null check (coins_spent > 0),
  created_at timestamptz not null default now(),
  unique (user_id, request_id)
);

alter table public.shop_purchases enable row level security;
revoke all on table public.shop_purchases from public, anon, authenticated;

create function public.purchase_shop_item(
  item_id text,
  purchase_request_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  price integer;
  existing_purchase public.shop_purchases;
  transaction_result jsonb;
  ticket_profile public.profiles;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if purchase_request_id is null then
    raise exception 'purchase request id required';
  end if;

  price := case item_id
    when 'practice_ticket' then 100
    when 'challenge_ticket' then 250
    else null
  end;
  if price is null then
    raise exception 'unknown shop item';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext('ticket-shop')
  );

  select * into existing_purchase
  from public.shop_purchases purchase
  where purchase.user_id = current_user_id
    and purchase.request_id = purchase_request_id;

  if existing_purchase.id is not null then
    if existing_purchase.item_id <> item_id then
      raise exception 'purchase request mismatch';
    end if;
    select * into ticket_profile
    from public.profiles profile
    where profile.id = current_user_id;
    return public.build_player_economy_json(
      ticket_profile.coin_balance,
      ticket_profile.experience_points
    ) || jsonb_build_object(
      'item_id', existing_purchase.item_id,
      'quantity', existing_purchase.quantity,
      'coins_spent', existing_purchase.coins_spent,
      'practice_tickets', ticket_profile.store_practice_tickets,
      'challenge_tickets', ticket_profile.store_challenge_tickets
    );
  end if;

  transaction_result := public.apply_coin_transaction(
    current_user_id,
    -price,
    0,
    'shop_purchase',
    'shop:' || purchase_request_id::text,
    null,
    null,
    jsonb_build_object('item_id', item_id, 'quantity', 1)
  );

  update public.profiles profile
  set
    store_practice_tickets = profile.store_practice_tickets
      + case when item_id = 'practice_ticket' then 1 else 0 end,
    store_challenge_tickets = profile.store_challenge_tickets
      + case when item_id = 'challenge_ticket' then 1 else 0 end,
    updated_at = now()
  where profile.id = current_user_id
  returning * into ticket_profile;

  insert into public.shop_purchases (
    user_id, request_id, item_id, quantity, coins_spent
  ) values (
    current_user_id, purchase_request_id, item_id, 1, price
  );

  return transaction_result || jsonb_build_object(
    'item_id', item_id,
    'quantity', 1,
    'coins_spent', price,
    'practice_tickets', ticket_profile.store_practice_tickets,
    'challenge_tickets', ticket_profile.store_challenge_tickets
  );
end;
$$;

revoke all on function public.purchase_shop_item(text, uuid) from public, anon;
grant execute on function public.purchase_shop_item(text, uuid)
  to authenticated;

create function public.verify_local_ranked_ad_for_development(
  reward_session_id uuid
)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  target_grant public.rewarded_ad_grants;
  bypass_enabled boolean := false;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select config.local_test_ad_verification_enabled into bypass_enabled
  from public.app_runtime_config config where config.id;
  if not coalesce(bypass_enabled, false) then
    raise exception 'local test ad verification disabled';
  end if;
  select * into target_grant from public.rewarded_ad_grants grant_row
  where grant_row.id = reward_session_id
    and grant_row.user_id = current_user_id
    and grant_row.play_date = public.current_play_date()
    and grant_row.grant_purpose = 'ranked_extra'
  for update;
  if target_grant.id is null then
    raise exception 'ranked reward session not found';
  end if;
  if target_grant.status in ('verified', 'consumed') then return; end if;
  if target_grant.status <> 'prepared' or target_grant.expires_at <= now() then
    raise exception 'ranked reward session unavailable';
  end if;
  update public.rewarded_ad_grants
  set status = 'verified',
      provider_transaction_id = coalesce(
        provider_transaction_id, 'local-ranked-test-' || id::text
      ),
      reward_item = 'challenge_attempt', reward_amount = 1,
      verified_at = coalesce(verified_at, now())
  where id = target_grant.id;
end;
$$;

revoke all on function public.verify_local_ranked_ad_for_development(uuid)
  from public, anon;
grant execute on function public.verify_local_ranked_ad_for_development(uuid)
  to authenticated;

-- Purchased practice tickets are spent only after the daily free/ad balance.
-- Keeping this at the insert boundary also covers tomorrow-preview practice.
create function public.consume_store_practice_ticket()
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
    and session.play_mode = 'practice';

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

create trigger daily_play_sessions_consume_store_practice_before_insert
before insert on public.daily_play_sessions
for each row execute function public.consume_store_practice_ticket();

revoke all on function public.consume_store_practice_ticket()
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
            and not entitlement.ranked_reward_consumed
          )
          or (
            entitlement.ranked_reward_consumed
            and entitlement.store_challenge_tickets > 0
            and entitlement.store_challenge_session_count = 0
          )
        )
      ) as challenge_available
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
    'practice_available',
      availability.practice_pending or (
        not availability.challenge_pending
        and not availability.challenge_in_progress
        and availability.practice_tickets_remaining > 0
      ),
    'challenge_requires_ad',
      availability.challenge_available
      and not availability.challenge_pending
      and availability.challenge_session_count = 1
      and not availability.ranked_reward_earned,
    'practice_requires_ad', false,
    'next_play_requires_ad',
      availability.challenge_available
      and not availability.challenge_pending
      and availability.challenge_session_count = 1
      and not availability.ranked_reward_earned
  )
  from availability;
$$;

create or replace function public.prepare_rewarded_ad_without_kakao(
  expected_play_date date
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  first_challenge public.attempts;
  active_grant public.rewarded_ad_grants;
  is_test boolean := false;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if not public.rewarded_ads_enabled() then
    raise exception 'rewarded ads disabled';
  end if;

  select coalesce(profile.is_test_account, false) into is_test
  from public.profiles profile where profile.id = current_user_id;
  if is_test then raise exception 'rewarded attempt unavailable in test mode'; end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text), hashtext(play_day::text)
  );

  select attempt.* into first_challenge
  from public.daily_play_sessions session
  join public.attempts attempt on attempt.id = session.attempt_id
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.play_mode = 'challenge'
  order by session.ordinal
  limit 1;

  if first_challenge.id is null or first_challenge.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;
  if (select count(*) from public.daily_play_sessions session
      where session.user_id = current_user_id
        and session.play_date = play_day
        and session.play_mode = 'challenge') <> 1 then
    raise exception 'rewarded attempt already claimed';
  end if;

  update public.rewarded_ad_grants set status = 'expired'
  where user_id = current_user_id and play_date = play_day
    and status in ('prepared', 'verified') and expires_at <= now();

  select * into active_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'ranked_extra'
    and grant_row.status in ('prepared', 'verified')
    and grant_row.expires_at > now()
  order by grant_row.prepared_at desc limit 1 for update;

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
      user_id, play_date, grant_purpose, expires_at
    ) values (
      current_user_id, play_day, 'ranked_extra',
      public.next_daily_reset_at(play_day)
    ) returning * into active_grant;
  end if;

  return jsonb_build_object(
    'id', active_grant.id, 'user_id', active_grant.user_id,
    'status', active_grant.status, 'expires_at', active_grant.expires_at
  );
end;
$$;

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
  existing_attempt public.attempts;
  choice_state jsonb;
  next_ordinal smallint;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text), hashtext(play_day::text)
  );

  select * into target_grant from public.rewarded_ad_grants grant_row
  where grant_row.id = reward_session_id
    and grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'ranked_extra'
  for update;
  if target_grant.id is null then raise exception 'daily game changed'; end if;

  if target_grant.status = 'consumed' then
    select attempt.* into existing_attempt
    from public.daily_play_sessions session
    join public.attempts attempt on attempt.id = session.attempt_id
    where session.reward_grant_id = reward_session_id;
    if existing_attempt.id is not null then return existing_attempt; end if;
  end if;
  if target_grant.status <> 'verified' then
    raise exception 'reward verification pending';
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if coalesce((choice_state->>'challenge_session_count')::integer, 0) <> 1
    or coalesce((choice_state->>'challenge_in_progress')::boolean, false) then
    raise exception 'challenge is not available';
  end if;

  next_ordinal := (
    select (coalesce(max(session.ordinal), 0) + 1)::smallint
    from public.daily_play_sessions session
    where session.user_id = current_user_id and session.play_date = play_day
  );
  scheduled_game := public.ensure_daily_game(play_day);
  select * into selected_game from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type, issued_at
  ) values (
    current_user_id, play_day, selected_game.game_id, selected_game.version,
    next_ordinal, 'rewarded_ad', target_grant.prepared_at
  ) returning * into claimed_attempt;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode, attempt_id, reward_grant_id,
    game_id, game_version, game_duration_seconds, created_at,
    entitlement_source
  ) values (
    current_user_id, play_day, next_ordinal, 'challenge', claimed_attempt.id,
    target_grant.id, selected_game.game_id, selected_game.version,
    selected_game.duration_seconds, target_grant.prepared_at, 'rewarded_ad'
  );
  update public.rewarded_ad_grants
  set status = 'consumed', consumed_at = now() where id = reward_session_id;
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
  is_test boolean := false;
  choice_state jsonb;
  play_count integer;
  challenge_session_count integer;
  next_ordinal smallint;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  live_attempt public.attempts;
  verified_grant public.rewarded_ad_grants;
  claimed_attempt public.attempts;
  selected_grant public.attempt_grant_type;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  select coalesce(profile.is_test_account, false) into is_test
  from public.profiles profile where profile.id = current_user_id;
  if is_test then
    return public.claim_daily_attempt_without_kakao(expected_play_date);
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
  order by session.ordinal desc limit 1;
  if live_attempt.id is not null then return live_attempt; end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'challenge_available')::boolean, false) then
    raise exception 'challenge is not available';
  end if;
  if coalesce((choice_state->>'challenge_requires_ad')::boolean, false) then
    raise exception 'challenge requires rewarded ad';
  end if;

  play_count := coalesce((choice_state->>'play_count')::integer, 0);
  challenge_session_count := coalesce(
    (choice_state->>'challenge_session_count')::integer, 0
  );
  if play_count = 0 then
    perform public.claim_first_device_play(current_user_id, play_day);
  end if;

  select * into verified_grant from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'ranked_extra'
    and grant_row.status = 'verified'
  order by grant_row.prepared_at desc limit 1 for update;

  selected_grant := case
    when challenge_session_count = 0 then 'daily'
    when verified_grant.id is not null then 'rewarded_ad'
    else 'store_ticket'
  end;
  if selected_grant = 'store_ticket' then
    if exists (
      select 1 from public.daily_play_sessions session
      where session.user_id = current_user_id
        and session.play_date = play_day
        and session.play_mode = 'challenge'
        and session.entitlement_source = 'store_ticket'
    ) then
      raise exception 'daily store challenge ticket already used';
    end if;
    update public.profiles profile
    set store_challenge_tickets = profile.store_challenge_tickets - 1,
        updated_at = now()
    where profile.id = current_user_id
      and profile.store_challenge_tickets > 0;
    if not found then raise exception 'challenge ticket is not available'; end if;
  end if;

  scheduled_game := public.ensure_daily_game(play_day);
  select * into selected_game from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;
  next_ordinal := (
    select (coalesce(max(session.ordinal), 0) + 1)::smallint
    from public.daily_play_sessions session
    where session.user_id = current_user_id and session.play_date = play_day
  );

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type, issued_at
  ) values (
    current_user_id, play_day, selected_game.game_id, selected_game.version,
    next_ordinal, selected_grant, coalesce(verified_grant.prepared_at, now())
  ) returning * into claimed_attempt;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode, attempt_id, reward_grant_id,
    game_id, game_version, game_duration_seconds, created_at,
    entitlement_source
  ) values (
    current_user_id, play_day, next_ordinal, 'challenge', claimed_attempt.id,
    verified_grant.id, selected_game.game_id, selected_game.version,
    selected_game.duration_seconds, claimed_attempt.issued_at,
    case selected_grant
      when 'rewarded_ad' then 'rewarded_ad'
      when 'store_ticket' then 'store_ticket'
      else 'daily'
    end
  );
  if verified_grant.id is not null then
    update public.rewarded_ad_grants set status = 'consumed', consumed_at = now()
    where id = verified_grant.id;
  end if;
  return claimed_attempt;
end;
$$;

-- The latest state wrapper already contains tomorrow preview data. Add the
-- authoritative shop inventory and restored ranked-ad flags on top.
alter function public.get_today_state()
rename to get_today_state_before_ticket_shop;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_ticket_shop();
  current_user_id uuid := (select auth.uid());
  play_day date := (state->>'play_date')::date;
  choice_state jsonb := public.daily_play_choice_state(current_user_id, play_day);
  device_limited boolean := coalesce(
    (state->>'device_daily_limit_reached')::boolean, false
  );
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
      and coalesce((choice_state->>'challenge_available')::boolean, false),
    'practice_available',
      not device_limited
      and coalesce((choice_state->>'practice_available')::boolean, false),
    'challenge_requires_ad',
      coalesce((choice_state->>'challenge_requires_ad')::boolean, false),
    'practice_requires_ad', false,
    'next_play_requires_ad',
      coalesce((choice_state->>'challenge_requires_ad')::boolean, false),
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
    'ad_attempt_available',
      not device_limited
      and coalesce((choice_state->>'challenge_requires_ad')::boolean, false)
  );
end;
$$;

revoke all on function public.get_today_state_before_ticket_shop()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

comment on function public.purchase_shop_item(text, uuid) is
  'Atomically spends coins and grants one persistent practice or challenge ticket.';

-- Monthly challenge-ticket reward for opting into push notifications.
-- The prompt reservation and claim are account-scoped and retry-safe.

create table public.push_opt_in_rewards (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  last_prompted_at timestamptz,
  accepted_at timestamptz,
  claimed_at timestamptz
);

alter table public.push_opt_in_rewards enable row level security;
revoke all on table public.push_opt_in_rewards from public, anon, authenticated;

create function public.get_push_opt_in_reward_status()
returns jsonb
language plpgsql
stable
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  reward public.push_opt_in_rewards;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into reward
  from public.push_opt_in_rewards
  where user_id = current_user_id;

  return jsonb_build_object(
    'should_show', reward.claimed_at is null
      and (reward.last_prompted_at is null
        or reward.last_prompted_at <= now() - interval '30 days'),
    'accepted', reward.accepted_at is not null,
    'claimed', reward.claimed_at is not null
  );
end;
$$;

create function public.record_push_opt_in_reward_prompt(
  accepted boolean default false
)
returns jsonb
language plpgsql
volatile
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_profile public.profiles;
  reward public.push_opt_in_rewards;
  reserved boolean := false;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  -- Keep the lock order identical to the claim function so prompt and claim
  -- requests for the same account cannot observe a partial enrollment.
  select * into current_profile
  from public.profiles
  where id = current_user_id
  for update;

  if current_profile.id is null then
    raise exception 'profile is not ready';
  end if;

  insert into public.push_opt_in_rewards (user_id)
  values (current_user_id)
  on conflict (user_id) do nothing;

  select * into reward
  from public.push_opt_in_rewards
  where user_id = current_user_id
  for update;

  if accepted then
    -- Acceptance is valid only for an offer that was previously reserved.
    -- Repeating acceptance remains an idempotent acknowledgement.
    if reward.claimed_at is null
      and reward.last_prompted_at is not null
      and reward.accepted_at is null then
      update public.push_opt_in_rewards
      set accepted_at = now()
      where user_id = current_user_id
      returning * into reward;
    end if;
  elsif reward.claimed_at is null
    and (reward.last_prompted_at is null
      or reward.last_prompted_at <= now() - interval '30 days') then
    update public.push_opt_in_rewards
    set last_prompted_at = now()
    where user_id = current_user_id
    returning * into reward;
    reserved := true;
  end if;

  return jsonb_build_object(
    'should_show', reserved,
    'accepted', reward.accepted_at is not null,
    'claimed', reward.claimed_at is not null
  );
end;
$$;

create function public.claim_push_opt_in_reward()
returns jsonb
language plpgsql
volatile
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_profile public.profiles;
  reward public.push_opt_in_rewards;
  updated_profile public.profiles;
  granted boolean := false;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  -- Lock profile before reward row in both mutating RPCs. This serializes the
  -- ticket increment with other account-scoped balance changes.
  select * into current_profile
  from public.profiles
  where id = current_user_id
  for update;

  if current_profile.id is null then
    raise exception 'profile is not ready';
  end if;

  select * into reward
  from public.push_opt_in_rewards
  where user_id = current_user_id
  for update;

  if reward.claimed_at is not null then
    return jsonb_build_object(
      'claimed', true,
      'granted', false,
      'tickets_granted', 0,
      'challenge_tickets', current_profile.store_challenge_tickets
    );
  end if;

  if reward.accepted_at is null
    or not coalesce(current_profile.social_notifications_enabled, false)
    or not exists (
      select 1
      from public.push_device_tokens token
      where token.user_id = current_user_id
        and token.enabled
        and token.updated_at >= reward.accepted_at
    )
    or current_profile.store_challenge_tickets >= 9999 then
    return jsonb_build_object(
      'claimed', false,
      'granted', false,
      'tickets_granted', 0,
      'challenge_tickets', current_profile.store_challenge_tickets
    );
  end if;

  update public.profiles
  set store_challenge_tickets = store_challenge_tickets + 1,
      updated_at = now()
  where id = current_user_id
    and store_challenge_tickets < 9999
  returning * into updated_profile;

  if updated_profile.id is null then
    return jsonb_build_object(
      'claimed', false,
      'granted', false,
      'tickets_granted', 0,
      'challenge_tickets', current_profile.store_challenge_tickets
    );
  end if;

  update public.push_opt_in_rewards
  set claimed_at = now()
  where user_id = current_user_id
    and claimed_at is null;

  granted := true;

  return jsonb_build_object(
    'claimed', true,
    'granted', granted,
    'tickets_granted', 1,
    'challenge_tickets', updated_profile.store_challenge_tickets
  );
end;
$$;

revoke all on function public.get_push_opt_in_reward_status() from public, anon;
revoke all on function public.record_push_opt_in_reward_prompt(boolean) from public, anon;
revoke all on function public.claim_push_opt_in_reward() from public, anon;
grant execute on function public.get_push_opt_in_reward_status() to authenticated;
grant execute on function public.record_push_opt_in_reward_prompt(boolean) to authenticated;
grant execute on function public.claim_push_opt_in_reward() to authenticated;

comment on table public.push_opt_in_rewards is
  'Account-scoped monthly push opt-in challenge-ticket reward state.';

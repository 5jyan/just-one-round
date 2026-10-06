-- Keep the forced-update reward disabled until an operator explicitly starts
-- a campaign. Once enabled, an existing player who crosses the configured
-- build receives one challenge ticket exactly once.

alter table public.app_runtime_config
  add column update_reward_enabled boolean not null default false,
  add column update_reward_campaign text not null default '',
  add column update_reward_target_build integer
    check (update_reward_target_build is null or update_reward_target_build > 0),
  add column update_reward_started_at timestamptz,
  add column update_reward_message text not null default
    '업데이트 감사 보상으로 도전권 1장을 드려요.';

alter table public.profiles
  add column last_seen_app_build integer
    check (last_seen_app_build is null or last_seen_app_build > 0),
  add column pending_update_from_build integer
    check (
      pending_update_from_build is null or pending_update_from_build > 0
    ),
  add column last_seen_app_platform text;

create table public.app_update_reward_claims (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  campaign_id text not null,
  from_build integer not null check (from_build > 0),
  to_build integer not null check (to_build > 0),
  platform text not null default 'unknown',
  tickets_granted integer not null default 1 check (tickets_granted = 1),
  created_at timestamptz not null default now(),
  unique (user_id, campaign_id)
);

alter table public.app_update_reward_claims enable row level security;
revoke all on table public.app_update_reward_claims from public, anon, authenticated;

-- This helper is called by get_client_compatibility() before the client has
-- necessarily signed in on a fresh install. A persisted authenticated session
-- is the server-side signal that the installation already existed. The first
-- observed build is recorded without creating a pending reward, so a new
-- installation can never qualify just because it opened the new release.
create function public.observe_client_build(
  observed_build integer,
  observed_platform text default null
)
returns void
language plpgsql
volatile
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_profile public.profiles;
begin
  if current_user_id is null or observed_build is null or observed_build <= 0 then
    return;
  end if;

  select * into current_profile
  from public.profiles profile
  where profile.id = current_user_id
  for update;

  if current_profile.id is null then
    return;
  end if;

  if current_profile.last_seen_app_build is null then
    update public.profiles
    set
      last_seen_app_build = observed_build,
      last_seen_app_platform = coalesce(nullif(trim(observed_platform), ''), 'unknown'),
      updated_at = now()
    where id = current_user_id;
    return;
  end if;

  if observed_build > current_profile.last_seen_app_build then
    update public.profiles
    set
      pending_update_from_build = coalesce(
        pending_update_from_build,
        last_seen_app_build
      ),
      last_seen_app_build = observed_build,
      last_seen_app_platform = coalesce(nullif(trim(observed_platform), ''), 'unknown'),
      updated_at = now()
    where id = current_user_id;
  end if;
end;
$$;

revoke all on function public.observe_client_build(integer, text)
  from public, anon, authenticated;

-- The compatibility endpoint is intentionally volatile because it also
-- records the build seen by an existing authenticated installation. That
-- observation happens before the minimum-build gate, allowing an old release
-- to mark itself before the operator raises the forced-update floor.
create or replace function public.get_client_compatibility()
returns jsonb
language plpgsql
volatile
security definer set search_path = ''
as $$
declare
  headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), ''),
    '{}'
  )::jsonb;
  raw_client_build integer := public.request_app_build();
  client_build integer := coalesce(raw_client_build, 1);
  client_platform text := lower(coalesce(headers ->> 'x-app-platform', 'unknown'));
  config public.app_runtime_config;
  minimum_build integer;
begin
  if raw_client_build is not null and (select auth.uid()) is not null then
    perform public.observe_client_build(raw_client_build, client_platform);
  end if;

  select * into config
  from public.app_runtime_config runtime_config
  where runtime_config.id;

  minimum_build := case client_platform
    when 'ios' then coalesce(
      config.ios_minimum_supported_build,
      config.minimum_supported_build,
      1
    )
    when 'android' then coalesce(
      config.android_minimum_supported_build,
      config.minimum_supported_build,
      1
    )
    else coalesce(config.minimum_supported_build, 1)
  end;

  return jsonb_build_object(
    'current_build', client_build,
    'minimum_supported_build', minimum_build,
    'update_required', client_build < minimum_build,
    'store_url', case client_platform
      when 'ios' then config.ios_store_url
      when 'android' then config.android_store_url
      else coalesce(config.ios_store_url, config.android_store_url)
    end
  );
end;
$$;

-- Claiming is atomic and idempotent. The client never supplies a user id,
-- campaign id, or build number; all of them come from the authenticated
-- session, request headers, and private runtime config.
create function public.claim_app_update_reward()
returns jsonb
language plpgsql
volatile
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), ''),
    '{}'
  )::jsonb;
  raw_client_build integer := public.request_app_build();
  client_platform text := lower(coalesce(headers ->> 'x-app-platform', 'unknown'));
  config public.app_runtime_config;
  current_profile public.profiles;
  inserted_claim public.app_update_reward_claims;
  target_build integer;
  reward_campaign_id text;
  reward_message text;
  existing_installation boolean;
  from_build integer;
begin
  if current_user_id is null or raw_client_build is null or raw_client_build <= 0 then
    return jsonb_build_object(
      'granted', false,
      'tickets_granted', 0
    );
  end if;

  perform public.observe_client_build(raw_client_build, client_platform);

  select * into config
  from public.app_runtime_config runtime_config
  where runtime_config.id;

  select * into current_profile
  from public.profiles profile
  where profile.id = current_user_id
  for update;

  reward_message := coalesce(
    nullif(trim(config.update_reward_message), ''),
    '업데이트 감사 보상으로 도전권 1장을 드려요.'
  );

  if current_profile.id is null
    or coalesce(current_profile.is_test_account, false)
    or not coalesce(config.update_reward_enabled, false)
    or nullif(trim(config.update_reward_campaign), '') is null
    or config.update_reward_target_build is null then
    return jsonb_build_object(
      'granted', false,
      'message', reward_message,
      'tickets_granted', 0,
      'challenge_tickets', coalesce(current_profile.store_challenge_tickets, 0)
    );
  end if;

  target_build := config.update_reward_target_build;
  reward_campaign_id := trim(config.update_reward_campaign);
  existing_installation := coalesce(
    current_profile.pending_update_from_build is not null,
    false
  ) or coalesce(
    config.update_reward_started_at is not null
      and current_profile.created_at < config.update_reward_started_at,
    false
  );
  from_build := coalesce(
    current_profile.pending_update_from_build,
    greatest(1, target_build - 1)
  );

  if raw_client_build < target_build
    or not existing_installation
    or (
      current_profile.pending_update_from_build is not null
      and current_profile.pending_update_from_build >= target_build
    ) then
    return jsonb_build_object(
      'granted', false,
      'campaign_id', reward_campaign_id,
      'message', reward_message,
      'tickets_granted', 0,
      'challenge_tickets', current_profile.store_challenge_tickets
    );
  end if;

  insert into public.app_update_reward_claims (
    user_id,
    campaign_id,
    from_build,
    to_build,
    platform
  ) values (
    current_user_id,
    reward_campaign_id,
    from_build,
    raw_client_build,
    client_platform
  )
  on conflict (user_id, campaign_id) do nothing
  returning * into inserted_claim;

  if inserted_claim.id is null then
    return jsonb_build_object(
      'granted', false,
      'campaign_id', reward_campaign_id,
      'message', reward_message,
      'tickets_granted', 0,
      'challenge_tickets', current_profile.store_challenge_tickets
    );
  end if;

  update public.profiles
  set
    store_challenge_tickets = least(9999, store_challenge_tickets + 1),
    pending_update_from_build = null,
    updated_at = now()
  where id = current_user_id
  returning * into current_profile;

  return jsonb_build_object(
    'granted', true,
    'campaign_id', reward_campaign_id,
    'message', reward_message,
    'tickets_granted', inserted_claim.tickets_granted,
    'challenge_tickets', current_profile.store_challenge_tickets
  );
end;
$$;

revoke all on function public.claim_app_update_reward() from public, anon;
grant execute on function public.claim_app_update_reward() to authenticated;

-- Operators can prepare a campaign without touching the client or granting
-- anything immediately. Keep enabled=false until the matching store release
-- is live and the platform minimum has been raised.
create function public.set_app_update_reward_campaign(
  enabled boolean,
  campaign text default null,
  target_build integer default null,
  message text default null
)
returns jsonb
language plpgsql
volatile
security definer set search_path = ''
as $$
declare
  updated_config public.app_runtime_config;
  next_campaign text;
  next_target_build integer;
begin
  next_campaign := coalesce(
    nullif(trim(campaign), ''),
    (select update_reward_campaign from public.app_runtime_config where id)
  );
  next_target_build := coalesce(
    target_build,
    (select update_reward_target_build from public.app_runtime_config where id)
  );

  if enabled and (next_campaign is null or next_campaign = '') then
    raise exception 'update reward campaign is required';
  end if;
  if enabled and (next_target_build is null or next_target_build <= 0) then
    raise exception 'update reward target build is required';
  end if;

  update public.app_runtime_config
  set
    update_reward_enabled = enabled,
    update_reward_campaign = coalesce(next_campaign, ''),
    update_reward_target_build = next_target_build,
    update_reward_started_at = case
      when enabled and not update_reward_enabled then now()
      else update_reward_started_at
    end,
    update_reward_message = case
      when message is null or trim(message) = '' then update_reward_message
      else trim(message)
    end,
    updated_at = now()
  where id
  returning * into updated_config;

  return jsonb_build_object(
    'enabled', updated_config.update_reward_enabled,
    'campaign_id', updated_config.update_reward_campaign,
    'target_build', updated_config.update_reward_target_build,
    'message', updated_config.update_reward_message,
    'updated_at', updated_config.updated_at
  );
end;
$$;

revoke all on function public.set_app_update_reward_campaign(boolean, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.set_app_update_reward_campaign(boolean, text, integer, text)
  to service_role;

comment on column public.app_runtime_config.update_reward_enabled is
  'Disabled by default. Enable only after the forced-update store release is live.';
comment on column public.app_runtime_config.update_reward_target_build is
  'Build at or above which an existing installation can receive the campaign ticket.';
comment on column public.app_runtime_config.update_reward_started_at is
  'Set when a disabled campaign is enabled; profiles created before it are existing installations.';
comment on column public.profiles.pending_update_from_build is
  'Previous build observed before a later build; consumed by one update reward claim.';

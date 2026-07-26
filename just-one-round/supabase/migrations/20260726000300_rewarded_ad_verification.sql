create table public.rewarded_ad_grants (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'admob',
  user_id uuid not null references auth.users (id) on delete cascade,
  play_date date not null,
  status text not null default 'prepared',
  ad_unit_id text,
  provider_transaction_id text unique,
  reward_amount integer,
  reward_item text,
  prepared_at timestamptz not null default now(),
  verified_at timestamptz,
  consumed_at timestamptz,
  expires_at timestamptz not null,
  constraint rewarded_ad_grants_provider check (provider = 'admob'),
  constraint rewarded_ad_grants_status check (
    status in ('prepared', 'verified', 'consumed', 'expired')
  ),
  constraint rewarded_ad_grants_reward_amount check (
    reward_amount is null or reward_amount >= 0
  )
);

create index rewarded_ad_grants_user_date_idx
  on public.rewarded_ad_grants (user_id, play_date, prepared_at desc);

alter table public.rewarded_ad_grants enable row level security;

create function public.prepare_rewarded_ad()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  first_attempt public.attempts;
  active_grant public.rewarded_ad_grants;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(seoul_date::text)
  );

  select * into first_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = seoul_date
    and ordinal = 1;

  if first_attempt is null or first_attempt.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;

  if exists (
    select 1 from public.attempts
    where user_id = current_user_id
      and play_date = seoul_date
      and ordinal = 2
  ) then
    raise exception 'rewarded attempt already claimed';
  end if;

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = seoul_date
    and status in ('prepared', 'verified')
    and expires_at <= now();

  select * into active_grant
  from public.rewarded_ad_grants
  where user_id = current_user_id
    and play_date = seoul_date
    and status in ('prepared', 'verified')
    and expires_at > now()
  order by prepared_at desc
  limit 1
  for update;

  if active_grant is null then
    insert into public.rewarded_ad_grants (
      user_id,
      play_date,
      expires_at
    ) values (
      current_user_id,
      seoul_date,
      (seoul_date + 1)::timestamp at time zone 'Asia/Seoul'
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

create function public.verify_rewarded_ad_grant(
  reward_session_id uuid,
  reward_user_id uuid,
  transaction_id text,
  verified_ad_unit_id text,
  verified_reward_amount integer,
  verified_reward_item text
)
returns boolean
language plpgsql
security definer set search_path = ''
as $$
declare
  target_grant public.rewarded_ad_grants;
  transaction_owner uuid;
begin
  if transaction_id is null or length(transaction_id) = 0 then
    raise exception 'transaction id required';
  end if;

  select id into transaction_owner
  from public.rewarded_ad_grants
  where provider_transaction_id = transaction_id;

  if transaction_owner is not null then
    return transaction_owner = reward_session_id;
  end if;

  select * into target_grant
  from public.rewarded_ad_grants
  where id = reward_session_id
  for update;

  if target_grant is null or target_grant.user_id <> reward_user_id then
    raise exception 'reward session mismatch';
  end if;
  if target_grant.status = 'consumed' then
    return true;
  end if;
  if target_grant.status <> 'prepared' or target_grant.expires_at <= now() then
    raise exception 'reward session is not verifiable';
  end if;

  update public.rewarded_ad_grants
  set
    status = 'verified',
    ad_unit_id = verified_ad_unit_id,
    provider_transaction_id = transaction_id,
    reward_amount = verified_reward_amount,
    reward_item = verified_reward_item,
    verified_at = now()
  where id = reward_session_id;

  return true;
end;
$$;

drop function public.claim_rewarded_attempt();

create function public.claim_rewarded_attempt(reward_session_id uuid)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  first_attempt public.attempts;
  existing_attempt public.attempts;
  scheduled_game public.daily_games;
  target_grant public.rewarded_ad_grants;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into target_grant
  from public.rewarded_ad_grants
  where id = reward_session_id
    and user_id = current_user_id
    and play_date = seoul_date
  for update;

  if target_grant is null then
    raise exception 'reward session not found';
  end if;

  select * into existing_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = seoul_date
    and ordinal = 2;

  if target_grant.status = 'consumed' and existing_attempt is not null then
    return existing_attempt;
  end if;

  if target_grant.status <> 'verified' then
    raise exception 'reward verification pending';
  end if;

  select * into first_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = seoul_date
    and ordinal = 1;

  if first_attempt is null or first_attempt.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;

  scheduled_game := public.ensure_daily_game(seoul_date);

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type
  ) values (
    current_user_id, seoul_date, scheduled_game.game_id,
    scheduled_game.game_version, 2, 'rewarded_ad'
  )
  on conflict (user_id, play_date, ordinal) do nothing
  returning * into claimed_attempt;

  if claimed_attempt is null then
    select * into claimed_attempt
    from public.attempts
    where user_id = current_user_id
      and play_date = seoul_date
      and ordinal = 2;
  end if;

  update public.rewarded_ad_grants
  set status = 'consumed', consumed_at = now()
  where id = reward_session_id;

  return claimed_attempt;
end;
$$;

revoke all on table public.rewarded_ad_grants from public;
revoke all on function public.prepare_rewarded_ad() from public;
revoke all on function public.verify_rewarded_ad_grant(
  uuid, uuid, text, text, integer, text
) from public;
revoke all on function public.claim_rewarded_attempt(uuid) from public;

grant execute on function public.prepare_rewarded_ad() to authenticated;
grant execute on function public.claim_rewarded_attempt(uuid) to authenticated;
grant execute on function public.verify_rewarded_ad_grant(
  uuid, uuid, text, text, integer, text
) to service_role;

-- Referral links are accepted on the web while the invitee is still outside
-- the app.  The acceptance is attached to the Kakao-backed Supabase user and
-- the reward is granted only when a real play session is started.

create table public.referral_codes (
  user_id uuid primary key references auth.users (id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now(),
  constraint referral_codes_code_format
    check (code ~ '^[a-f0-9]{16}$')
);

create table public.referral_acceptances (
  id uuid primary key default gen_random_uuid(),
  inviter_user_id uuid references auth.users (id) on delete set null,
  invitee_user_id uuid references auth.users (id) on delete set null,
  -- This is a deterministic SHA-256 of the Kakao provider id.  It survives
  -- account deletion without retaining the provider id itself and prevents
  -- the same Kakao account from accepting a second referral later.
  invitee_identity_hash text not null unique,
  referral_code text references public.referral_codes (code)
    on delete set null,
  accepted_at timestamptz not null default now(),
  played_at timestamptz,
  completed_play_mode text,
  completed_session_id uuid references public.daily_play_sessions (id)
    on delete set null,
  reward_granted_at timestamptz,
  constraint referral_acceptances_distinct_users
    check (
      inviter_user_id is null
      or invitee_user_id is null
      or inviter_user_id <> invitee_user_id
    ),
  constraint referral_acceptances_identity_hash_format
    check (invitee_identity_hash ~ '^[a-f0-9]{64}$'),
  constraint referral_acceptances_play_mode
    check (completed_play_mode is null or completed_play_mode in ('practice', 'challenge')),
  unique (invitee_user_id)
);

create index referral_acceptances_inviter_idx
  on public.referral_acceptances (inviter_user_id, accepted_at desc);

alter table public.referral_codes enable row level security;
alter table public.referral_acceptances enable row level security;
revoke all on table public.referral_codes from public, anon, authenticated;
revoke all on table public.referral_acceptances from public, anon, authenticated;

create or replace function public.get_or_create_referral_code()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  existing_code text;
  candidate text;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select code into existing_code
  from public.referral_codes
  where user_id = current_user_id;
  if existing_code is not null then
    return jsonb_build_object('code', existing_code);
  end if;

  for attempt_number in 1..8 loop
    candidate := encode(extensions.gen_random_bytes(8), 'hex');
    begin
      insert into public.referral_codes (user_id, code)
      values (current_user_id, candidate)
      on conflict (user_id) do nothing;
      select code into existing_code
      from public.referral_codes
      where user_id = current_user_id;
      if existing_code is not null then
        return jsonb_build_object('code', existing_code);
      end if;
    exception when unique_violation then
      -- A random code collision is harmless; generate another one.
      null;
    end;
  end loop;

  raise exception 'could not create referral code';
end;
$$;

create or replace function public.get_referral_status()
returns jsonb
language sql
security definer set search_path = ''
stable
as $$
  with current_identity as (
    select (select auth.uid()) as user_id
  ), own_code as (
    select code
    from public.referral_codes
    where user_id = (select user_id from current_identity)
  ), received as (
    select
      acceptance.accepted_at,
      acceptance.played_at,
      acceptance.reward_granted_at
    from public.referral_acceptances acceptance
    where acceptance.invitee_user_id = (select user_id from current_identity)
  ), sent as (
    select
      count(*)::integer as invited_count,
      count(*) filter (where acceptance.reward_granted_at is not null)::integer
        as completed_count
    from public.referral_acceptances acceptance
    where acceptance.inviter_user_id = (select user_id from current_identity)
  )
  select jsonb_build_object(
    'code', (select code from own_code),
    'invited_count', sent.invited_count,
    'completed_count', sent.completed_count,
    'pending_count', sent.invited_count - sent.completed_count,
    'accepted', exists (select 1 from received),
    'played', exists (select 1 from received where played_at is not null),
    'reward_granted', exists (
      select 1 from received where reward_granted_at is not null
    )
  )
  from sent;
$$;

create or replace function public.accept_referral(referral_code text)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  is_anonymous boolean;
  kakao_provider_id text;
  kakao_identity_hash text;
  inviter_user_id uuid;
  existing_acceptance public.referral_acceptances;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  select coalesce(user_row.is_anonymous, false)
  into is_anonymous
  from auth.users user_row
  where user_row.id = current_user_id;
  if is_anonymous then
    raise exception 'kakao account required for referral';
  end if;
  select identity_row.provider_id
  into kakao_provider_id
  from auth.identities identity_row
  where identity_row.user_id = current_user_id
    and identity_row.provider = 'kakao'
  order by identity_row.created_at nulls last, identity_row.id
  limit 1;
  if kakao_provider_id is null or btrim(kakao_provider_id) = '' then
    raise exception 'kakao account required for referral';
  end if;
  kakao_identity_hash := encode(
    extensions.digest('kakao:' || btrim(kakao_provider_id), 'sha256'),
    'hex'
  );

  select code_row.user_id
  into inviter_user_id
  from public.referral_codes code_row
  where code_row.code = lower(btrim(referral_code));
  if inviter_user_id is null then
    raise exception 'referral code not found';
  end if;
  if inviter_user_id = current_user_id then
    raise exception 'cannot accept your own referral';
  end if;

  -- Check both durable identity and the current auth user.  The latter keeps
  -- one referral per Supabase account even if a provider ever rotates its
  -- identifier; the former survives an account deletion and recreation.
  select * into existing_acceptance
  from public.referral_acceptances acceptance
  where acceptance.invitee_identity_hash = kakao_identity_hash
     or acceptance.invitee_user_id = current_user_id
  for update;
  if existing_acceptance.id is not null then
    if existing_acceptance.invitee_user_id is distinct from current_user_id then
      raise exception 'referral identity already accepted';
    end if;
    if existing_acceptance.inviter_user_id is distinct from inviter_user_id then
      raise exception 'referral already accepted';
    end if;
    return jsonb_build_object(
      'accepted', true,
      'played', existing_acceptance.played_at is not null,
      'reward_granted', existing_acceptance.reward_granted_at is not null
    );
  end if;

  -- Two browser tabs can submit the same OAuth callback at once.  Let the
  -- unique identity/user constraints serialize that race, then read the row
  -- below and return the same idempotent result instead of surfacing a 23505.
  insert into public.referral_acceptances (
    inviter_user_id, invitee_user_id, invitee_identity_hash, referral_code
  ) values (
    inviter_user_id,
    current_user_id,
    kakao_identity_hash,
    lower(btrim(referral_code))
  ) on conflict do nothing;

  select * into existing_acceptance
  from public.referral_acceptances acceptance
  where acceptance.invitee_identity_hash = kakao_identity_hash
     or acceptance.invitee_user_id = current_user_id
  for update;
  if existing_acceptance.id is not null then
    if existing_acceptance.invitee_user_id is distinct from current_user_id then
      raise exception 'referral identity already accepted';
    end if;
    if existing_acceptance.inviter_user_id is distinct from inviter_user_id then
      raise exception 'referral already accepted';
    end if;
    return jsonb_build_object(
      'accepted', true,
      'played', existing_acceptance.played_at is not null,
      'reward_granted', existing_acceptance.reward_granted_at is not null
    );
  end if;

  return jsonb_build_object(
    'accepted', true,
    'played', false,
    'reward_granted', false
  );
end;
$$;

-- This function is called from the session-start trigger below.  The update
-- predicate is the idempotency key: retries and repeated lifecycle callbacks
-- can never grant a second challenge ticket.
create or replace function public.complete_referral_for_play(
  target_session_id uuid,
  target_user_id uuid,
  target_play_mode text,
  target_started_at timestamptz
)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  inviter_user_id uuid;
begin
  if exists (
    select 1 from public.profiles profile
    where profile.id = target_user_id
      and coalesce(profile.is_test_account, false)
  ) then
    return;
  end if;

  update public.referral_acceptances acceptance
  set
    played_at = coalesce(acceptance.played_at, target_started_at),
    completed_play_mode = coalesce(acceptance.completed_play_mode, target_play_mode),
    completed_session_id = coalesce(acceptance.completed_session_id, target_session_id),
    reward_granted_at = coalesce(acceptance.reward_granted_at, now())
  where acceptance.invitee_user_id = target_user_id
    and acceptance.played_at is null
  returning acceptance.inviter_user_id into inviter_user_id;

  if inviter_user_id is null then
    return;
  end if;

  update public.profiles profile
  set store_challenge_tickets = least(9999, profile.store_challenge_tickets + 1),
      updated_at = now()
  where profile.id = inviter_user_id;
end;
$$;

create or replace function public.complete_referral_on_play_start()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  -- Build 12+ clients insert a pending session and confirm the real start in
  -- a later update.  Older supported clients have the legacy before-insert
  -- trigger populate started_at immediately, so handle that insert too.
  if (
    (tg_op = 'INSERT' and new.started_at is not null)
    or (
      tg_op = 'UPDATE'
      and old.started_at is null
      and new.started_at is not null
    )
  ) then
    perform public.complete_referral_for_play(
      new.id,
      new.user_id,
      new.play_mode,
      new.started_at
    );
  end if;
  return new;
end;
$$;

create trigger daily_play_sessions_complete_referral_after_start
after insert or update of started_at on public.daily_play_sessions
for each row execute function public.complete_referral_on_play_start();

revoke all on function public.get_or_create_referral_code() from public, anon;
revoke all on function public.get_referral_status() from public, anon;
revoke all on function public.accept_referral(text) from public, anon;
revoke all on function public.complete_referral_for_play(uuid, uuid, text, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_referral_on_play_start()
  from public, anon, authenticated, service_role;
grant execute on function public.get_or_create_referral_code() to authenticated;
grant execute on function public.get_referral_status() to authenticated;
grant execute on function public.accept_referral(text) to authenticated;

-- One account-wide Chuseok gift for the 2026 event.
-- The server owns eligibility and the unique claim so retries and multiple
-- devices cannot grant more than one challenge ticket per account.

create table public.chuseok_gift_claims (
  event_id text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  tickets_granted integer not null default 1 check (tickets_granted = 1),
  claimed_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

alter table public.chuseok_gift_claims enable row level security;
revoke all on table public.chuseok_gift_claims from public, anon, authenticated;

create or replace function public.chuseok_event_active()
returns boolean
language sql
stable
security definer set search_path = ''
as $$
  select (now() at time zone 'Asia/Seoul')::date <= date '2026-09-25';
$$;

revoke all on function public.chuseok_event_active() from public, anon, authenticated;

create function public.get_chuseok_gift_status()
returns jsonb
language plpgsql
stable
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  event_key text := 'chuseok-2026';
  already_claimed boolean := false;
begin
  if current_user_id is not null then
    select exists (
      select 1
      from public.chuseok_gift_claims claim
      where claim.event_id = event_key
        and claim.user_id = current_user_id
    ) into already_claimed;
  end if;

  return jsonb_build_object(
    'event_id', event_key,
    'eligible', public.chuseok_event_active(),
    'claimed', already_claimed
  );
end;
$$;

revoke all on function public.get_chuseok_gift_status() from public, anon;
grant execute on function public.get_chuseok_gift_status() to authenticated;

create function public.claim_chuseok_gift()
returns jsonb
language plpgsql
volatile
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  event_key text := 'chuseok-2026';
  current_profile public.profiles;
  inserted_claim public.chuseok_gift_claims;
  existing_claim public.chuseok_gift_claims;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into current_profile
  from public.profiles profile
  where profile.id = current_user_id
  for update;

  if current_profile.id is null then
    raise exception 'profile is not ready';
  end if;

  -- Resolve an already committed claim before checking the cutoff. This
  -- makes a lost response safe to retry across the event boundary.
  select * into existing_claim
  from public.chuseok_gift_claims claim
  where claim.event_id = event_key
    and claim.user_id = current_user_id;

  if existing_claim.event_id is not null then
    return jsonb_build_object(
      'event_id', event_key,
      'eligible', public.chuseok_event_active(),
      'claimed', true,
      'granted', false,
      'tickets_granted', 0,
      'challenge_tickets', current_profile.store_challenge_tickets
    );
  end if;

  if not public.chuseok_event_active() then
    return jsonb_build_object(
      'event_id', event_key,
      'eligible', false,
      'claimed', false,
      'granted', false,
      'tickets_granted', 0
    );
  end if;

  insert into public.chuseok_gift_claims (
    event_id,
    user_id
  ) values (
    event_key,
    current_user_id
  )
  on conflict (event_id, user_id) do nothing
  returning * into inserted_claim;

  if inserted_claim.event_id is null then
    return jsonb_build_object(
      'event_id', event_key,
      'eligible', public.chuseok_event_active(),
      'claimed', true,
      'granted', false,
      'tickets_granted', 0,
      'challenge_tickets', current_profile.store_challenge_tickets
    );
  end if;

  update public.profiles
  set
    store_challenge_tickets = least(9999, store_challenge_tickets + 1),
    updated_at = now()
  where id = current_user_id
  returning * into current_profile;

  return jsonb_build_object(
    'event_id', event_key,
    'eligible', true,
    'claimed', true,
    'granted', true,
    'tickets_granted', inserted_claim.tickets_granted,
    'challenge_tickets', current_profile.store_challenge_tickets,
    'message', '추석 선물로 도전권 1장을 받았어요.'
  );
end;
$$;

revoke all on function public.claim_chuseok_gift() from public, anon;
grant execute on function public.claim_chuseok_gift() to authenticated;

comment on table public.chuseok_gift_claims is
  'One-time account-wide 2026 Chuseok challenge ticket gifts.';

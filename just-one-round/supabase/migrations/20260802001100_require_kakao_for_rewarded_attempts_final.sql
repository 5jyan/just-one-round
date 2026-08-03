-- The anonymous rewarded-attempt migration was added after the first Kakao
-- gate. Keep its implementation, but put the account-retention requirement
-- back in the public RPC entry points so later migrations cannot remove it.

alter function public.prepare_rewarded_ad(date)
rename to prepare_rewarded_ad_without_kakao;

alter function public.claim_rewarded_attempt(uuid)
rename to claim_rewarded_attempt_without_kakao;

create or replace function public.prepare_rewarded_ad(expected_play_date date)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if not exists (
    select 1
    from auth.identities identity_row
    where identity_row.user_id = current_user_id
      and identity_row.provider = 'kakao'
  ) then
    raise exception 'kakao account required for rewarded attempt';
  end if;

  return public.prepare_rewarded_ad_without_kakao(expected_play_date);
end;
$$;

create or replace function public.prepare_rewarded_ad()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if not exists (
    select 1
    from auth.identities identity_row
    where identity_row.user_id = current_user_id
      and identity_row.provider = 'kakao'
  ) then
    raise exception 'kakao account required for rewarded attempt';
  end if;

  return public.prepare_rewarded_ad(public.current_play_date());
end;
$$;

create or replace function public.claim_rewarded_attempt(
  reward_session_id uuid
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if not exists (
    select 1
    from auth.identities identity_row
    where identity_row.user_id = current_user_id
      and identity_row.provider = 'kakao'
  ) then
    raise exception 'kakao account required for rewarded attempt';
  end if;

  return public.claim_rewarded_attempt_without_kakao(reward_session_id);
end;
$$;

revoke all on function public.prepare_rewarded_ad_without_kakao(date)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_rewarded_attempt_without_kakao(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.prepare_rewarded_ad() from public;
revoke all on function public.prepare_rewarded_ad(date) from public;
revoke all on function public.claim_rewarded_attempt(uuid) from public;

grant execute on function public.prepare_rewarded_ad() to authenticated;
grant execute on function public.prepare_rewarded_ad(date) to authenticated;
grant execute on function public.claim_rewarded_attempt(uuid) to authenticated;

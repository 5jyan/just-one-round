-- Require Kakao only when an anonymous player who completed a game on the
-- previous play date tries to start the next day's daily game.
-- The daily game and rewarded extra play remain available to a fresh
-- anonymous account. Rewarded-attempt RPCs are restored to their anonymous
-- implementation because an older local migration temporarily gated them.

create or replace function public.kakao_required_for_daily_play(
  expected_play_date date
)
returns boolean
language sql
stable
security definer set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and not exists (
      select 1
      from public.profiles profile
      where profile.id = (select auth.uid())
        and coalesce(profile.is_test_account, false)
    )
    and not exists (
      select 1
      from auth.identities identity_row
      where identity_row.user_id = (select auth.uid())
        and identity_row.provider = 'kakao'
    )
    and exists (
      select 1
      from public.scores score
      where score.user_id = (select auth.uid())
        and score.play_date = expected_play_date - 1
    );
$$;

revoke all on function public.kakao_required_for_daily_play(date)
  from public, anon, authenticated, service_role;

-- Keep the latest immutable-game implementation, but add the account-retention
-- check at the daily-play boundary. The internal function remains unreachable
-- from the API roles and is called only by this security-definer wrapper.
alter function public.claim_daily_attempt(date)
rename to claim_daily_attempt_without_kakao;

create or replace function public.claim_daily_attempt(expected_play_date date)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  play_day date := public.current_play_date();
begin
  if public.kakao_required_for_daily_play(play_day) then
    raise exception 'kakao account required for daily play';
  end if;

  return public.claim_daily_attempt_without_kakao(expected_play_date);
end;
$$;

-- Preserve the legacy no-argument RPC for older clients.
create or replace function public.claim_daily_attempt()
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
begin
  return public.claim_daily_attempt(public.current_play_date());
end;
$$;

revoke all on function public.claim_daily_attempt_without_kakao(date)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_daily_attempt() from public;
revoke all on function public.claim_daily_attempt(date) from public;
grant execute on function public.claim_daily_attempt() to authenticated;
grant execute on function public.claim_daily_attempt(date) to authenticated;

-- Add the same server decision to the home-screen response so the client can
-- show a useful dialog before attempting the RPC.
alter function public.get_today_state()
rename to get_today_state_without_kakao_requirement;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_without_kakao_requirement();
  play_day date := (state->>'play_date')::date;
begin
  return state || jsonb_build_object(
    'requires_kakao_for_daily_play',
    public.kakao_required_for_daily_play(play_day)
  );
end;
$$;

revoke all on function public.get_today_state_without_kakao_requirement()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

-- An earlier local migration wrapped these RPCs with an unconditional Kakao
-- requirement. Restore the anonymous implementation while keeping its
-- server-side AdMob verification and daily attempt limits intact.
create or replace function public.prepare_rewarded_ad(expected_play_date date)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
begin
  return public.prepare_rewarded_ad_without_kakao(expected_play_date);
end;
$$;

create or replace function public.prepare_rewarded_ad()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
begin
  return public.prepare_rewarded_ad_without_kakao(public.current_play_date());
end;
$$;

create or replace function public.claim_rewarded_attempt(
  reward_session_id uuid
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
begin
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

-- Kakao linking is optional. Keep the compatibility function because current
-- and older RPC definitions call it, but make every play path return false.
create or replace function public.kakao_required_for_daily_play(
  expected_play_date date
)
returns boolean
language sql
stable
security definer set search_path = ''
as $$
  select false;
$$;

revoke all on function public.kakao_required_for_daily_play(date)
  from public, anon, authenticated, service_role;

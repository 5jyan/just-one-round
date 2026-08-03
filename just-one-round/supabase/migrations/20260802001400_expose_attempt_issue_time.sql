-- Include the server issue time in the home-screen attempt snapshot. The app
-- uses it to distinguish a genuinely abandoned attempt from a just-claimed
-- game while a rewarded-ad return refresh is still in flight.

alter function public.get_today_state_without_kakao_requirement()
rename to get_today_state_without_attempt_timestamps;

create or replace function public.get_today_state_without_kakao_requirement()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  state jsonb := public.get_today_state_without_attempt_timestamps();
  attempts_with_timestamps jsonb;
begin
  select coalesce(
    jsonb_agg(
      item || jsonb_build_object('issued_at', attempt.issued_at)
      order by (item->>'ordinal')::integer
    ),
    '[]'::jsonb
  )
  into attempts_with_timestamps
  from jsonb_array_elements(
    coalesce(state->'attempts', '[]'::jsonb)
  ) as item
  join public.attempts attempt
    on attempt.id = (item->>'id')::uuid
   and attempt.user_id = current_user_id;

  return jsonb_set(
    state,
    '{attempts}',
    coalesce(attempts_with_timestamps, '[]'::jsonb),
    true
  );
end;
$$;

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

revoke all on function public.get_today_state_without_attempt_timestamps()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state_without_kakao_requirement()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

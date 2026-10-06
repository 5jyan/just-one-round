-- Apple challenge boards are shared by date. Practice boards use a separate,
-- shared sequence (practice 1, practice 2, ...) independent of whether a user
-- chose challenge or practice first.

create function public.practice_ordinal_for_session(target_session_id uuid)
returns integer
language sql
stable
security definer set search_path = ''
as $$
  select count(*)::integer
  from public.daily_play_sessions candidate
  join public.daily_play_sessions target
    on target.id = target_session_id
   and candidate.user_id = target.user_id
   and candidate.play_date = target.play_date
  where candidate.play_mode = 'practice'
    and candidate.ordinal <= target.ordinal;
$$;

revoke all on function public.practice_ordinal_for_session(uuid)
  from public, anon, authenticated, service_role;

alter function public.claim_daily_practice_v2(date, uuid)
rename to claim_daily_practice_v2_before_apple_seed_slots;

create function public.claim_daily_practice_v2(
  expected_play_date date,
  play_request_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  claimed_session jsonb;
begin
  claimed_session := public.claim_daily_practice_v2_before_apple_seed_slots(
    expected_play_date,
    play_request_id
  );
  return claimed_session || jsonb_build_object(
    'practice_ordinal',
    public.practice_ordinal_for_session((claimed_session->>'id')::uuid)
  );
end;
$$;

revoke all on function public.claim_daily_practice_v2_before_apple_seed_slots(date, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_daily_practice_v2(date, uuid) from public;
grant execute on function public.claim_daily_practice_v2(date, uuid)
  to authenticated;

alter function public.claim_practice_attempt(uuid)
rename to claim_practice_attempt_before_apple_seed_slots;

create function public.claim_practice_attempt(reward_session_id uuid)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  claimed_session jsonb;
begin
  claimed_session := public.claim_practice_attempt_before_apple_seed_slots(
    reward_session_id
  );
  return claimed_session || jsonb_build_object(
    'practice_ordinal',
    public.practice_ordinal_for_session((claimed_session->>'id')::uuid)
  );
end;
$$;

revoke all on function public.claim_practice_attempt_before_apple_seed_slots(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_practice_attempt(uuid) from public;
grant execute on function public.claim_practice_attempt(uuid) to authenticated;

alter function public.get_today_state()
rename to get_today_state_before_apple_seed_slots;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_apple_seed_slots();
  current_user_id uuid := (select auth.uid());
  play_day date := (state->>'play_date')::date;
  practice_count integer;
begin
  select count(*)::integer into practice_count
  from public.daily_play_sessions session
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.play_mode = 'practice';

  return state || jsonb_build_object(
    'practice_play_count', coalesce(practice_count, 0)
  );
end;
$$;

revoke all on function public.get_today_state_before_apple_seed_slots()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

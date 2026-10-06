-- Test accounts use a legacy unlimited-attempt branch. Keep that behavior,
-- but make every issued challenge participate in the confirmed-start state
-- machine just like a normal account.

alter function public.claim_daily_attempt(date)
  rename to claim_daily_attempt_before_test_play_sessions;

revoke all on function public.claim_daily_attempt_before_test_play_sessions(date)
  from public, anon, authenticated, service_role;

create function public.claim_daily_attempt(expected_play_date date)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  is_test boolean := false;
  claimed_attempt public.attempts;
  selected_version public.game_rule_versions;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select coalesce(profile.is_test_account, false)
  into is_test
  from public.profiles profile
  where profile.id = current_user_id;

  if not coalesce(is_test, false) then
    return public.claim_daily_attempt_before_test_play_sessions(
      expected_play_date
    );
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  -- A lost claim response or repeated button tap returns the same unstarted
  -- test challenge instead of creating another ordinal.
  select attempt.* into claimed_attempt
  from public.daily_play_sessions session
  join public.attempts attempt on attempt.id = session.attempt_id
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.play_mode = 'challenge'
    and session.started_at is null
    and attempt.status = 'issued'
  order by session.created_at desc, session.id desc
  limit 1;

  if claimed_attempt.id is not null then
    return claimed_attempt;
  end if;

  -- Recover an attempt issued by the old test branch before this migration.
  select attempt.* into claimed_attempt
  from public.attempts attempt
  where attempt.user_id = current_user_id
    and attempt.play_date = play_day
    and attempt.status = 'issued'
    and not exists (
      select 1
      from public.daily_play_sessions session
      where session.attempt_id = attempt.id
    )
  order by attempt.ordinal desc, attempt.issued_at desc
  limit 1;

  if claimed_attempt.id is null then
    claimed_attempt := public.claim_daily_attempt_before_test_play_sessions(
      expected_play_date
    );
  end if;

  select * into selected_version
  from public.game_rule_versions versioned
  where versioned.game_id = claimed_attempt.game_id
    and versioned.version = claimed_attempt.game_version;
  if selected_version.game_id is null then
    raise exception 'game version not found';
  end if;

  insert into public.daily_play_sessions (
    user_id,
    play_date,
    ordinal,
    play_mode,
    attempt_id,
    game_id,
    game_version,
    game_duration_seconds,
    created_at
  ) values (
    current_user_id,
    play_day,
    claimed_attempt.ordinal,
    'challenge',
    claimed_attempt.id,
    claimed_attempt.game_id,
    claimed_attempt.game_version,
    selected_version.duration_seconds,
    claimed_attempt.issued_at
  ) on conflict (attempt_id) do nothing;

  return claimed_attempt;
end;
$$;

revoke all on function public.claim_daily_attempt(date) from public;
grant execute on function public.claim_daily_attempt(date) to authenticated;

-- Repair already-issued test attempts so an open game guide can be started
-- immediately after this migration is applied.
insert into public.daily_play_sessions (
  user_id,
  play_date,
  ordinal,
  play_mode,
  attempt_id,
  game_id,
  game_version,
  game_duration_seconds,
  created_at
)
select
  attempt.user_id,
  attempt.play_date,
  attempt.ordinal,
  'challenge',
  attempt.id,
  attempt.game_id,
  attempt.game_version,
  versioned.duration_seconds,
  attempt.issued_at
from public.attempts attempt
join public.profiles profile
  on profile.id = attempt.user_id and profile.is_test_account
join public.game_rule_versions versioned
  on versioned.game_id = attempt.game_id
 and versioned.version = attempt.game_version
where attempt.play_date = public.current_play_date()
  and attempt.status = 'issued'
  and not exists (
    select 1
    from public.daily_play_sessions session
    where session.attempt_id = attempt.id
  )
on conflict (attempt_id) do nothing;

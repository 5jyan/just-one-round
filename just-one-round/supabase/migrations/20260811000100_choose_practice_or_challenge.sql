-- Let a player choose practice or the single ranked challenge on plays one
-- and two. If both are practice, play three is the required challenge. After
-- the ranked challenge (and from play four onward), only practice is allowed.

create table public.daily_play_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  play_date date not null,
  ordinal smallint not null check (ordinal > 0),
  play_mode text not null check (play_mode in ('challenge', 'practice')),
  attempt_id uuid unique references public.attempts (id) on delete cascade,
  reward_grant_id uuid unique
    references public.rewarded_ad_grants (id) on delete cascade,
  game_id text not null references public.games (id),
  game_version integer not null check (game_version > 0),
  game_duration_seconds smallint not null check (game_duration_seconds > 0),
  created_at timestamptz not null default now(),
  unique (user_id, play_date, ordinal),
  constraint daily_play_sessions_mode_attempt_check check (
    (play_mode = 'challenge' and attempt_id is not null)
    or (play_mode = 'practice' and attempt_id is null)
  )
);

create index daily_play_sessions_user_date_idx
  on public.daily_play_sessions (user_id, play_date, ordinal);

alter table public.daily_play_sessions enable row level security;
revoke all on table public.daily_play_sessions
  from public, anon, authenticated;

-- Preserve today's and historical progress for players who used the previous
-- two-ranked-attempt flow. Existing ranked attempts remain valid, but any
-- further play follows the new practice-only rule.
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
  attempt.game_duration_seconds,
  attempt.issued_at
from public.attempts attempt
join public.profiles profile on profile.id = attempt.user_id
where not coalesce(profile.is_test_account, false)
on conflict do nothing;

with practice_grants as (
  select
    grant_row.*,
    row_number() over (
      partition by grant_row.user_id, grant_row.play_date
      order by grant_row.consumed_at, grant_row.id
    )::smallint as practice_number
  from public.rewarded_ad_grants grant_row
  join public.profiles profile on profile.id = grant_row.user_id
  where grant_row.grant_purpose = 'practice'
    and grant_row.status = 'consumed'
    and not coalesce(profile.is_test_account, false)
), ranked_counts as (
  select
    attempt.user_id,
    attempt.play_date,
    max(attempt.ordinal)::smallint as last_ordinal
  from public.attempts attempt
  group by attempt.user_id, attempt.play_date
)
insert into public.daily_play_sessions (
  user_id,
  play_date,
  ordinal,
  play_mode,
  reward_grant_id,
  game_id,
  game_version,
  game_duration_seconds,
  created_at
)
select
  grant_row.user_id,
  grant_row.play_date,
  coalesce(ranked.last_ordinal, 0) + grant_row.practice_number,
  'practice',
  grant_row.id,
  grant_row.game_id,
  grant_row.game_version,
  grant_row.game_duration_seconds,
  coalesce(grant_row.consumed_at, grant_row.prepared_at)
from practice_grants grant_row
left join ranked_counts ranked
  on ranked.user_id = grant_row.user_id
 and ranked.play_date = grant_row.play_date
on conflict do nothing;

create function public.daily_play_choice_state(
  target_user_id uuid,
  target_play_date date
)
returns jsonb
language sql
stable
security definer set search_path = ''
as $$
  with summary as (
    select
      count(*)::integer as play_count,
      coalesce(bool_or(session.play_mode = 'challenge'), false)
        as challenge_played,
      coalesce(bool_or(
        session.play_mode = 'challenge' and attempt.status = 'issued'
      ), false) as challenge_in_progress
    from public.daily_play_sessions session
    left join public.attempts attempt on attempt.id = session.attempt_id
    where session.user_id = target_user_id
      and session.play_date = target_play_date
  )
  select jsonb_build_object(
    'play_count', summary.play_count,
    'challenge_played', summary.challenge_played,
    'challenge_in_progress', summary.challenge_in_progress,
    'challenge_available',
      not summary.challenge_played
      and not summary.challenge_in_progress
      and summary.play_count < 3,
    'practice_available',
      not summary.challenge_in_progress
      and (
        summary.play_count = 0
        or summary.challenge_played
        or summary.play_count < 2
      ),
    'next_play_requires_ad', summary.play_count > 0
  )
  from summary;
$$;

create function public.claim_first_device_play(
  target_user_id uuid,
  target_play_date date
)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  headers_text text := current_setting('request.headers', true);
  headers jsonb := coalesce(nullif(headers_text, ''), '{}')::jsonb;
  request_build_header text := coalesce(headers ->> 'x-app-build', '');
  request_build integer := case
    when request_build_header ~ '^[0-9]+$' then request_build_header::integer
    else 0
  end;
  device_key text := public.current_device_hash();
  inserted_claim_count integer := 0;
begin
  if target_user_id is distinct from (select auth.uid()) then
    raise exception 'authentication required';
  end if;

  if device_key is null and request_build >= 7 then
    raise exception 'device registration required';
  end if;

  if device_key is null then
    return;
  end if;

  perform pg_advisory_xact_lock(
    hashtext(device_key),
    hashtext(target_play_date::text)
  );

  insert into public.device_daily_claims (device_hash, play_date)
  values (device_key, target_play_date)
  on conflict (device_hash, play_date) do nothing;
  get diagnostics inserted_claim_count = row_count;

  if inserted_claim_count = 0 and not exists (
    select 1
    from public.daily_play_sessions session
    where session.user_id = target_user_id
      and session.play_date = target_play_date
      and session.ordinal = 1
  ) then
    raise exception 'daily attempt already claimed on this device';
  end if;
end;
$$;

create or replace function public.claim_daily_attempt(
  expected_play_date date
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  is_test boolean := false;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  existing_attempt public.attempts;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  select coalesce(profile.is_test_account, false)
  into is_test
  from public.profiles profile
  where profile.id = current_user_id;

  if coalesce(is_test, false) then
    return public.claim_daily_attempt_without_kakao(expected_play_date);
  end if;

  if public.kakao_required_for_daily_play(play_day) then
    raise exception 'kakao account required for daily play';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select attempt.*
  into existing_attempt
  from public.daily_play_sessions session
  join public.attempts attempt on attempt.id = session.attempt_id
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.ordinal = 1
    and session.play_mode = 'challenge';

  if existing_attempt is not null then
    return existing_attempt;
  end if;

  if exists (
    select 1 from public.daily_play_sessions session
    where session.user_id = current_user_id
      and session.play_date = play_day
  ) then
    raise exception 'challenge requires rewarded ad';
  end if;

  perform public.claim_first_device_play(current_user_id, play_day);
  scheduled_game := public.ensure_daily_game(play_day);

  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;

  if selected_game is null then
    raise exception 'game version not found';
  end if;

  insert into public.attempts (
    user_id,
    play_date,
    game_id,
    game_version,
    ordinal,
    grant_type
  ) values (
    current_user_id,
    play_day,
    selected_game.game_id,
    selected_game.version,
    1,
    'daily'
  )
  returning * into claimed_attempt;

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
    1,
    'challenge',
    claimed_attempt.id,
    selected_game.game_id,
    selected_game.version,
    selected_game.duration_seconds,
    claimed_attempt.issued_at
  );

  return claimed_attempt;
end;
$$;

create or replace function public.claim_daily_practice(
  expected_play_date date
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  is_test boolean := false;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  existing_session public.daily_play_sessions;
  claimed_session public.daily_play_sessions;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  select coalesce(profile.is_test_account, false)
  into is_test
  from public.profiles profile
  where profile.id = current_user_id;

  if coalesce(is_test, false) then
    raise exception 'practice unavailable in test mode';
  end if;
  if public.kakao_required_for_daily_play(play_day) then
    raise exception 'kakao account required for daily play';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select * into existing_session
  from public.daily_play_sessions session
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.ordinal = 1
    and session.play_mode = 'practice';

  if existing_session is not null then
    return jsonb_build_object(
      'id', existing_session.id,
      'ordinal', existing_session.ordinal,
      'status', 'practice',
      'grant_type', 'practice_daily',
      'game_id', existing_session.game_id,
      'game_version', existing_session.game_version,
      'game_duration_seconds', existing_session.game_duration_seconds,
      'play_date', existing_session.play_date,
      'issued_at', existing_session.created_at
    );
  end if;

  if exists (
    select 1 from public.daily_play_sessions session
    where session.user_id = current_user_id
      and session.play_date = play_day
  ) then
    raise exception 'first free play already claimed';
  end if;

  perform public.claim_first_device_play(current_user_id, play_day);
  scheduled_game := public.ensure_daily_game(play_day);

  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;

  if selected_game is null then
    raise exception 'game version not found';
  end if;

  insert into public.daily_play_sessions (
    user_id,
    play_date,
    ordinal,
    play_mode,
    game_id,
    game_version,
    game_duration_seconds
  ) values (
    current_user_id,
    play_day,
    1,
    'practice',
    selected_game.game_id,
    selected_game.version,
    selected_game.duration_seconds
  )
  returning * into claimed_session;

  return jsonb_build_object(
    'id', claimed_session.id,
    'ordinal', claimed_session.ordinal,
    'status', 'practice',
    'grant_type', 'practice_daily',
    'game_id', claimed_session.game_id,
    'game_version', claimed_session.game_version,
    'game_duration_seconds', claimed_session.game_duration_seconds,
    'play_date', claimed_session.play_date,
    'issued_at', claimed_session.created_at
  );
end;
$$;

create or replace function public.prepare_rewarded_ad_without_kakao(
  expected_play_date date
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  choice_state jsonb;
  active_grant public.rewarded_ad_grants;
  is_test boolean := false;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if not public.rewarded_ads_enabled() then
    raise exception 'rewarded ads disabled';
  end if;

  select coalesce(profile.is_test_account, false)
  into is_test
  from public.profiles profile
  where profile.id = current_user_id;
  if coalesce(is_test, false) then
    raise exception 'rewarded attempt unavailable in test mode';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'challenge_available')::boolean, false)
    or (choice_state->>'play_count')::integer = 0 then
    raise exception 'challenge is not available';
  end if;

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and status in ('prepared', 'verified')
    and expires_at <= now();

  -- A prepared grant has not earned a reward yet, so the player may still
  -- switch their second-play choice without losing a verified reward.
  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and grant_purpose <> 'ranked_extra'
    and status = 'prepared';

  select * into active_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'ranked_extra'
    and grant_row.status in ('prepared', 'verified')
    and grant_row.expires_at > now()
  order by grant_row.prepared_at desc
  limit 1
  for update;

  if active_grant is null and exists (
    select 1 from public.rewarded_ad_grants grant_row
    where grant_row.user_id = current_user_id
      and grant_row.play_date = play_day
      and grant_row.status in ('prepared', 'verified')
  ) then
    raise exception 'another reward is pending';
  end if;

  if active_grant is null then
    insert into public.rewarded_ad_grants (
      user_id,
      play_date,
      grant_purpose,
      expires_at
    ) values (
      current_user_id,
      play_day,
      'ranked_extra',
      public.next_daily_reset_at(play_day)
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

create or replace function public.claim_rewarded_attempt_without_kakao(
  reward_session_id uuid
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  target_grant public.rewarded_ad_grants;
  existing_session public.daily_play_sessions;
  existing_attempt public.attempts;
  choice_state jsonb;
  next_ordinal smallint;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select * into target_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.id = reward_session_id
    and grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'ranked_extra'
  for update;

  if target_grant is null then
    raise exception 'daily game changed';
  end if;

  if target_grant.status = 'consumed' then
    select * into existing_session
    from public.daily_play_sessions session
    where session.reward_grant_id = reward_session_id;

    if existing_session is not null then
      select * into existing_attempt
      from public.attempts attempt
      where attempt.id = existing_session.attempt_id;
      if existing_attempt is not null then
        return existing_attempt;
      end if;
    end if;
  end if;

  if target_grant.status <> 'verified' then
    raise exception 'reward verification pending';
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'challenge_available')::boolean, false)
    or (choice_state->>'play_count')::integer = 0 then
    raise exception 'challenge is not available';
  end if;

  next_ordinal := ((choice_state->>'play_count')::integer + 1)::smallint;
  scheduled_game := public.ensure_daily_game(play_day);

  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;

  if selected_game is null then
    raise exception 'game version not found';
  end if;

  insert into public.attempts (
    user_id,
    play_date,
    game_id,
    game_version,
    ordinal,
    grant_type,
    issued_at
  ) values (
    current_user_id,
    play_day,
    selected_game.game_id,
    selected_game.version,
    next_ordinal,
    'rewarded_ad',
    target_grant.prepared_at
  )
  returning * into claimed_attempt;

  insert into public.daily_play_sessions (
    user_id,
    play_date,
    ordinal,
    play_mode,
    attempt_id,
    reward_grant_id,
    game_id,
    game_version,
    game_duration_seconds,
    created_at
  ) values (
    current_user_id,
    play_day,
    next_ordinal,
    'challenge',
    claimed_attempt.id,
    target_grant.id,
    selected_game.game_id,
    selected_game.version,
    selected_game.duration_seconds,
    target_grant.prepared_at
  );

  update public.rewarded_ad_grants
  set status = 'consumed', consumed_at = now()
  where id = reward_session_id;

  return claimed_attempt;
end;
$$;

create or replace function public.prepare_practice_ad(
  expected_play_date date
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  choice_state jsonb;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  active_grant public.rewarded_ad_grants;
  is_test boolean := false;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if not public.rewarded_ads_enabled() then
    raise exception 'rewarded ads disabled';
  end if;

  select coalesce(profile.is_test_account, false)
  into is_test
  from public.profiles profile
  where profile.id = current_user_id;
  if coalesce(is_test, false) then
    raise exception 'practice unavailable in test mode';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'practice_available')::boolean, false)
    or (choice_state->>'play_count')::integer = 0 then
    raise exception 'practice is not available';
  end if;

  scheduled_game := public.ensure_daily_game(play_day);
  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;
  if selected_game is null then
    raise exception 'game version not found';
  end if;

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and status in ('prepared', 'verified')
    and expires_at <= now();

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and grant_purpose <> 'practice'
    and status = 'prepared';

  select * into active_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
    and grant_row.status in ('prepared', 'verified')
    and grant_row.expires_at > now()
  order by grant_row.prepared_at desc
  limit 1
  for update;

  if active_grant is null and exists (
    select 1 from public.rewarded_ad_grants grant_row
    where grant_row.user_id = current_user_id
      and grant_row.play_date = play_day
      and grant_row.status in ('prepared', 'verified')
  ) then
    raise exception 'another reward is pending';
  end if;

  if active_grant is null then
    insert into public.rewarded_ad_grants (
      user_id,
      play_date,
      grant_purpose,
      game_id,
      game_version,
      game_duration_seconds,
      expires_at
    ) values (
      current_user_id,
      play_day,
      'practice',
      selected_game.game_id,
      selected_game.version,
      selected_game.duration_seconds,
      public.next_daily_reset_at(play_day)
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

create or replace function public.claim_practice_attempt(
  reward_session_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  target_grant public.rewarded_ad_grants;
  existing_session public.daily_play_sessions;
  choice_state jsonb;
  next_ordinal smallint;
  claimed_session public.daily_play_sessions;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select * into target_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.id = reward_session_id
    and grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
  for update;

  if target_grant is null then
    raise exception 'practice session not found';
  end if;

  if target_grant.status = 'consumed' then
    select * into existing_session
    from public.daily_play_sessions session
    where session.reward_grant_id = reward_session_id;
    if existing_session is not null then
      return jsonb_build_object(
        'id', existing_session.id,
        'ordinal', existing_session.ordinal,
        'status', 'practice',
        'grant_type', 'practice_ad',
        'game_id', existing_session.game_id,
        'game_version', existing_session.game_version,
        'game_duration_seconds', existing_session.game_duration_seconds,
        'play_date', existing_session.play_date,
        'issued_at', existing_session.created_at
      );
    end if;
  end if;

  if target_grant.status <> 'verified' then
    raise exception 'reward verification pending';
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'practice_available')::boolean, false)
    or (choice_state->>'play_count')::integer = 0 then
    raise exception 'practice is not available';
  end if;

  next_ordinal := ((choice_state->>'play_count')::integer + 1)::smallint;

  insert into public.daily_play_sessions (
    user_id,
    play_date,
    ordinal,
    play_mode,
    reward_grant_id,
    game_id,
    game_version,
    game_duration_seconds,
    created_at
  ) values (
    current_user_id,
    play_day,
    next_ordinal,
    'practice',
    target_grant.id,
    target_grant.game_id,
    target_grant.game_version,
    target_grant.game_duration_seconds,
    target_grant.prepared_at
  )
  returning * into claimed_session;

  update public.rewarded_ad_grants
  set status = 'consumed', consumed_at = now()
  where id = reward_session_id;

  return jsonb_build_object(
    'id', claimed_session.id,
    'ordinal', claimed_session.ordinal,
    'status', 'practice',
    'grant_type', 'practice_ad',
    'game_id', claimed_session.game_id,
    'game_version', claimed_session.game_version,
    'game_duration_seconds', claimed_session.game_duration_seconds,
    'play_date', claimed_session.play_date,
    'issued_at', claimed_session.created_at
  );
end;
$$;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  state jsonb := public.get_today_state_without_kakao_requirement();
  play_day date := (state->>'play_date')::date;
  is_test boolean := coalesce((state->>'test_mode')::boolean, false);
  choice_state jsonb;
  play_count integer;
  ads_enabled boolean := public.rewarded_ads_enabled();
begin
  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  play_count := coalesce((choice_state->>'play_count')::integer, 0);

  if is_test then
    return state || jsonb_build_object(
      'requires_kakao_for_daily_play', false,
      'play_count', coalesce(jsonb_array_length(state->'attempts'), 0),
      'challenge_available', true,
      'practice_available', false,
      'next_play_requires_ad', false
    );
  end if;

  return state || jsonb_build_object(
    'requires_kakao_for_daily_play',
      public.kakao_required_for_daily_play(play_day),
    'daily_claimed',
      coalesce((state->>'daily_claimed')::boolean, false) or play_count > 0,
    -- Old build-11 clients must never issue the legacy second ranked attempt.
    'ad_attempt_available', false,
    'play_count', play_count,
    'challenge_available',
      coalesce((choice_state->>'challenge_available')::boolean, false)
      and (play_count = 0 or ads_enabled),
    'practice_available',
      coalesce((choice_state->>'practice_available')::boolean, false)
      and (play_count = 0 or ads_enabled),
    'next_play_requires_ad',
      coalesce((choice_state->>'next_play_requires_ad')::boolean, false)
  );
end;
$$;

revoke all on function public.daily_play_choice_state(uuid, date)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_first_device_play(uuid, date)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_daily_practice(date) from public;
revoke all on function public.get_today_state() from public;

grant execute on function public.claim_daily_practice(date) to authenticated;
grant execute on function public.get_today_state() to authenticated;

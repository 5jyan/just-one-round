-- A player sees at most one rewarded ad per play day.
-- Practice before the challenge is free. If the challenge is chosen first,
-- the first practice after it uses the day's single ad. Otherwise the
-- challenge after practice uses that ad, and all later practice is free.

create or replace function public.daily_play_choice_state(
  target_user_id uuid,
  target_play_date date
)
returns jsonb
language sql
stable
security definer set search_path = ''
as $$
  with play_summary as (
    select
      count(*)::integer as play_count,
      count(*) filter (where session.play_mode = 'practice')::integer
        as practice_count,
      coalesce(bool_or(session.play_mode = 'challenge'), false)
        as challenge_played,
      coalesce(bool_or(
        session.play_mode = 'challenge' and attempt.status = 'issued'
      ), false) as challenge_in_progress
    from public.daily_play_sessions session
    left join public.attempts attempt on attempt.id = session.attempt_id
    where session.user_id = target_user_id
      and session.play_date = target_play_date
  ), ad_summary as (
    select exists (
      select 1
      from public.rewarded_ad_grants grant_row
      where grant_row.user_id = target_user_id
        and grant_row.play_date = target_play_date
        and grant_row.status in ('verified', 'consumed')
    ) as ad_watched
  ), availability as (
    select
      play_summary.*,
      ad_summary.ad_watched,
      not play_summary.challenge_played
        and not play_summary.challenge_in_progress
        and play_summary.play_count < 3 as challenge_available,
      not play_summary.challenge_in_progress
        and (
          play_summary.play_count = 0
          or play_summary.challenge_played
          or play_summary.play_count < 2
        ) as practice_available
    from play_summary
    cross join ad_summary
  )
  select jsonb_build_object(
    'play_count', availability.play_count,
    'practice_count', availability.practice_count,
    'challenge_played', availability.challenge_played,
    'challenge_in_progress', availability.challenge_in_progress,
    'ad_watched', availability.ad_watched,
    'challenge_available', availability.challenge_available,
    'practice_available', availability.practice_available,
    'challenge_requires_ad',
      availability.challenge_available
      and availability.practice_count > 0
      and not availability.ad_watched,
    'practice_requires_ad',
      availability.practice_available
      and availability.challenge_played
      and availability.practice_count = 0
      and not availability.ad_watched,
    'next_play_requires_ad',
      (
        availability.challenge_available
        and availability.practice_count > 0
        and not availability.ad_watched
      ) or (
        availability.practice_available
        and availability.challenge_played
        and availability.practice_count = 0
        and not availability.ad_watched
      )
  )
  from availability;
$$;

create function public.enforce_one_daily_rewarded_ad()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.rewarded_ad_grants existing
    where existing.user_id = new.user_id
      and existing.play_date = new.play_date
      and existing.status in ('verified', 'consumed')
  ) then
    raise exception 'daily rewarded ad already used';
  end if;
  return new;
end;
$$;

create trigger rewarded_ad_grants_one_per_day_before_insert
before insert on public.rewarded_ad_grants
for each row execute function public.enforce_one_daily_rewarded_ad();

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
  choice_state jsonb;
  play_count integer;
  next_ordinal smallint;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  existing_attempt public.attempts;
  verified_grant public.rewarded_ad_grants;
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
    and session.play_mode = 'challenge'
  order by session.ordinal
  limit 1;

  if existing_attempt is not null then
    return existing_attempt;
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'challenge_available')::boolean, false) then
    raise exception 'challenge is not available';
  end if;
  if coalesce((choice_state->>'challenge_requires_ad')::boolean, false) then
    raise exception 'challenge requires rewarded ad';
  end if;

  play_count := coalesce((choice_state->>'play_count')::integer, 0);
  if play_count = 0 then
    perform public.claim_first_device_play(current_user_id, play_day);
  end if;

  scheduled_game := public.ensure_daily_game(play_day);
  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;
  if selected_game is null then
    raise exception 'game version not found';
  end if;

  select * into verified_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'ranked_extra'
    and grant_row.status = 'verified'
  order by grant_row.prepared_at desc
  limit 1
  for update;

  next_ordinal := (play_count + 1)::smallint;
  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type, issued_at
  ) values (
    current_user_id,
    play_day,
    selected_game.game_id,
    selected_game.version,
    next_ordinal,
    (
      case when verified_grant is null then 'daily' else 'rewarded_ad' end
    )::public.attempt_grant_type,
    coalesce(verified_grant.prepared_at, now())
  )
  returning * into claimed_attempt;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode, attempt_id, reward_grant_id,
    game_id, game_version, game_duration_seconds, created_at
  ) values (
    current_user_id,
    play_day,
    next_ordinal,
    'challenge',
    claimed_attempt.id,
    verified_grant.id,
    selected_game.game_id,
    selected_game.version,
    selected_game.duration_seconds,
    claimed_attempt.issued_at
  );

  if verified_grant is not null then
    update public.rewarded_ad_grants
    set status = 'consumed', consumed_at = now()
    where id = verified_grant.id;
  end if;

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
  choice_state jsonb;
  play_count integer;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
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

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'practice_available')::boolean, false) then
    raise exception 'practice is not available';
  end if;
  if coalesce((choice_state->>'practice_requires_ad')::boolean, false) then
    raise exception 'practice requires rewarded ad';
  end if;

  play_count := coalesce((choice_state->>'play_count')::integer, 0);
  if play_count = 0 then
    perform public.claim_first_device_play(current_user_id, play_day);
  end if;

  scheduled_game := public.ensure_daily_game(play_day);
  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;
  if selected_game is null then
    raise exception 'game version not found';
  end if;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode,
    game_id, game_version, game_duration_seconds
  ) values (
    current_user_id,
    play_day,
    (play_count + 1)::smallint,
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
  challenge_requires_ad boolean;
  practice_requires_ad boolean;
begin
  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  play_count := coalesce((choice_state->>'play_count')::integer, 0);

  if is_test then
    return state || jsonb_build_object(
      'requires_kakao_for_daily_play', false,
      'play_count', coalesce(jsonb_array_length(state->'attempts'), 0),
      'challenge_available', true,
      'practice_available', false,
      'challenge_requires_ad', false,
      'practice_requires_ad', false,
      'next_play_requires_ad', false
    );
  end if;

  challenge_requires_ad := coalesce(
    (choice_state->>'challenge_requires_ad')::boolean,
    false
  );
  practice_requires_ad := coalesce(
    (choice_state->>'practice_requires_ad')::boolean,
    false
  );

  return state || jsonb_build_object(
    'requires_kakao_for_daily_play',
      public.kakao_required_for_daily_play(play_day),
    'daily_claimed',
      coalesce((state->>'daily_claimed')::boolean, false) or play_count > 0,
    'ad_attempt_available', false,
    'play_count', play_count,
    'challenge_available',
      coalesce((choice_state->>'challenge_available')::boolean, false)
      and (not challenge_requires_ad or ads_enabled),
    'practice_available',
      coalesce((choice_state->>'practice_available')::boolean, false)
      and (not practice_requires_ad or ads_enabled),
    'challenge_requires_ad', challenge_requires_ad,
    'practice_requires_ad', practice_requires_ad,
    -- Compatibility for clients that still use one shared ad flag.
    'next_play_requires_ad',
      ads_enabled and (challenge_requires_ad or practice_requires_ad)
  );
end;
$$;

revoke all on function public.enforce_one_daily_rewarded_ad()
  from public, anon, authenticated, service_role;

-- APPLY ONLY AFTER iOS build 26 is installable in the App Store. Earlier iOS
-- builds do not accept the restored rule numbers. Android Alpha runs build 22.
-- Preserve every issued attempt, session, and score; only future schedules
-- follow the restored catalog. iOS build 26 receives a server-side 150-second
-- lily_frog v3 override while Android build 22 keeps the captured 300 seconds.
-- The update gate and its one-ticket campaign are iOS-only.
--
-- Rollback: use a new forward migration to restore the former catalog rows
-- from game_rule_versions (blackjack v4, slugger v8, frog v5) and the shared
-- minimum_supported_build of 25. Restore the iOS minimum only after older
-- clients can accept the newer catalog again. Keep the v7 score wrapper and historical
-- rows so attempts issued during this compatibility window can still submit.

begin;

select pg_advisory_xact_lock(hashtext('public.ensure_daily_game.rotation'));

do $$
begin
  if not exists (
    select 1 from public.app_runtime_config
    where id and android_minimum_supported_build = 22
  ) then
    raise exception 'Android build 22 is not currently allowed';
  end if;

  if (
    select count(*)
    from public.game_rule_versions
    where (game_id, version) in (
      ('beat_the_dealer', 3),
      ('ten_pitch_slugger', 7),
      ('lily_frog', 3)
    )
  ) <> 3 then
    raise exception 'build 22 game rule snapshots are missing';
  end if;
end;
$$;

-- The games trigger enforces immutable metadata, so copy each original row
-- exactly rather than assigning an old number to a new duration or text.
update public.games as catalog
set version = old.version,
    display_name = old.display_name,
    description = old.description,
    duration_seconds = old.duration_seconds,
    minimum_app_build = old.minimum_app_build
from public.game_rule_versions as old
where (catalog.id, old.version) in (
    ('beat_the_dealer', 3),
    ('ten_pitch_slugger', 7),
    ('lily_frog', 3)
  )
  and old.game_id = catalog.id
  and catalog.version is distinct from old.version;

-- Only dates that have not begun may change. Existing attempts keep their
-- captured game version and duration.
update public.daily_games as scheduled
set game_version = catalog.version
from public.games as catalog
where scheduled.play_date > public.current_play_date()
  and scheduled.game_id = catalog.id
  and scheduled.game_id in (
    'beat_the_dealer', 'ten_pitch_slugger', 'lily_frog'
  )
  and scheduled.game_version is distinct from catalog.version;

-- Rotation must use the Android 22 floor. Retire iOS 25 and older at the
-- same instant so they cannot claim a game version they do not implement.
update public.app_runtime_config
set minimum_supported_build = 22,
    ios_minimum_supported_build = 26,
    update_reward_enabled = true,
    update_reward_campaign = 'ios-build-26-update-reward',
    update_reward_target_build = 26,
    update_reward_started_at = case
      when update_reward_campaign is distinct from 'ios-build-26-update-reward'
        or update_reward_started_at is null then now()
      else update_reward_started_at
    end,
    updated_at = now()
where id
  and android_minimum_supported_build = 22
  and (
    minimum_supported_build is distinct from 22
    or ios_minimum_supported_build is distinct from 26
    or update_reward_enabled is distinct from true
    or update_reward_campaign is distinct from 'ios-build-26-update-reward'
    or update_reward_target_build is distinct from 26
    or update_reward_started_at is null
  );

-- Keep the existing immutable rule lookup, then apply the iOS 26 client
-- contract only to new lily_frog v3 attempts. The snapshot row remains 300s;
-- issued attempts and every historical row stay untouched.
create or replace function public.snapshot_attempt_game_rules()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), ''),
    '{}'
  )::jsonb;
  client_platform text := lower(coalesce(headers ->> 'x-app-platform', 'unknown'));
  client_build integer := public.request_app_build();
begin
  select versioned.duration_seconds
  into new.game_duration_seconds
  from public.game_rule_versions versioned
  where versioned.game_id = new.game_id
    and versioned.version = new.game_version;

  if new.game_duration_seconds is null then
    raise exception 'game version not found';
  end if;

  if client_platform = 'ios'
    and client_build >= 26
    and new.game_id = 'lily_frog'
    and new.game_version = 3 then
    new.game_duration_seconds := 150;
  end if;
  return new;
end;
$$;

revoke all on function public.snapshot_attempt_game_rules()
  from public, anon, authenticated, service_role;

-- Challenge sessions copy the duration captured on their attempt. Practice
-- sessions have no attempt_id, so apply the same iOS 26 policy directly.
-- Existing attempts/sessions are untouched, including consumed ad grants.
create or replace function public.apply_ios26_lily_frog_session_duration()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  captured_duration integer;
  headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), ''),
    '{}'
  )::jsonb;
  client_platform text := lower(coalesce(headers ->> 'x-app-platform', 'unknown'));
  client_build integer := public.request_app_build();
begin
  if new.attempt_id is not null then
    select attempt.game_duration_seconds
    into captured_duration
    from public.attempts attempt
    where attempt.id = new.attempt_id;

    if captured_duration is not null then
      new.game_duration_seconds := captured_duration;
    end if;
    return new;
  end if;

  if client_platform = 'ios'
    and client_build >= 26
    and new.game_id = 'lily_frog'
    and new.game_version = 3 then
    new.game_duration_seconds := 150;
  end if;
  return new;
end;
$$;

drop trigger if exists daily_play_sessions_ios26_duration_before_insert
  on public.daily_play_sessions;
create trigger daily_play_sessions_ios26_duration_before_insert
before insert on public.daily_play_sessions
for each row execute function public.apply_ios26_lily_frog_session_duration();

revoke all on function public.apply_ios26_lily_frog_session_duration()
  from public, anon, authenticated, service_role;

-- Home duration also drives optimistic ad starts. Preserve the original
-- function and all its side effects while matching newly issued sessions.
do $$
begin
  if to_regprocedure('public.get_today_state_before_ios26_alignment()') is null then
    alter function public.get_today_state() rename to get_today_state_before_ios26_alignment;
  end if;
end;
$$;
revoke all on function public.get_today_state_before_ios26_alignment()
  from public, anon, authenticated, service_role;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb;
  headers jsonb := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
begin
  state := public.get_today_state_before_ios26_alignment();
  if lower(coalesce(headers ->> 'x-app-platform', 'unknown')) = 'ios'
    and public.request_app_build() >= 26 then
    if state #>> '{game,id}' = 'lily_frog'
      and state #>> '{game,version}' = '3' then
      state := jsonb_set(state, '{game,duration_seconds}', '150'::jsonb);
    end if;
    if state #>> '{tomorrow,game,id}' = 'lily_frog'
      and state #>> '{tomorrow,game,version}' = '3' then
      state := jsonb_set(state, '{tomorrow,game,duration_seconds}', '150'::jsonb);
    end if;
  end if;
  return state;
end;
$$;
revoke all on function public.get_today_state() from public, anon;
grant execute on function public.get_today_state() to authenticated;

-- Preserve the deployed reward claim's eligibility, locks, and one-time
-- grant. The new campaign additionally requires the iOS platform header.
do $$
begin
  if to_regprocedure('public.claim_app_update_reward_before_ios26_alignment()') is null then
    alter function public.claim_app_update_reward()
      rename to claim_app_update_reward_before_ios26_alignment;
  end if;
end;
$$;
revoke all on function public.claim_app_update_reward_before_ios26_alignment()
  from public, anon, authenticated, service_role;

create or replace function public.claim_app_update_reward()
returns jsonb
language plpgsql
volatile
security definer set search_path = ''
as $$
declare
  campaign text;
  headers jsonb := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
begin
  select config.update_reward_campaign into campaign
  from public.app_runtime_config config where config.id;
  if campaign = 'ios-build-26-update-reward'
    and lower(coalesce(headers ->> 'x-app-platform', 'unknown')) <> 'ios' then
    return jsonb_build_object('granted', false, 'tickets_granted', 0);
  end if;
  return public.claim_app_update_reward_before_ios26_alignment();
end;
$$;
revoke all on function public.claim_app_update_reward() from public, anon;
grant execute on function public.claim_app_update_reward() to authenticated;

-- iOS 26 can score up to 16875 on slugger v7's stronger seventh pitch;
-- Android 22's existing 0..15000 results remain valid. iOS frog v3 uses the
-- deployed v5 scoring bounds with a 150-second cap; frog v3 attempts captured
-- at 300 seconds and every other game delegate to the prior validator.
do $$
begin
  if to_regprocedure(
    'public.submit_daily_score_before_android22_slugger_v7(uuid,integer,integer,integer,integer)'
  ) is null then
    alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
      rename to submit_daily_score_before_android22_slugger_v7;
  end if;
end;
$$;

revoke all on function public.submit_daily_score_before_android22_slugger_v7(
  uuid, integer, integer, integer, integer
) from public, anon, authenticated;

create or replace function public.submit_daily_score(
  attempt_id uuid,
  raw_score integer,
  stars_collected integer,
  collisions integer,
  duration_ms integer
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  active_attempt public.attempts;
  scheduled_duration integer;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id and user_id = current_user_id
  for update;

  if active_attempt is null then raise exception 'attempt not found'; end if;

  if active_attempt.game_id = 'lily_frog'
    and active_attempt.game_version = 3
    and active_attempt.game_duration_seconds = 150 then
    if active_attempt.status = 'submitted' then
      return public.get_my_daily_result(active_attempt.play_date);
    end if;
    if active_attempt.status <> 'issued' then
      raise exception 'active attempt not found';
    end if;

    perform public.assert_score_submission_elapsed(
      active_attempt.issued_at, duration_ms
    );

    -- This is the deployed lily_frog v5 validator with the restored v3
    -- identity. It accepts both the existing 0-score timeout and the scored
    -- path while preserving its score, collision, and elapsed-time bounds.
    if raw_score is null
      or stars_collected is null
      or collisions is null
      or duration_ms is null
      or stars_collected not between 0 and 1000
      or collisions not between 0 and 1
      or duration_ms not between 3000 and 150000
      or (collisions = 0 and duration_ms <> 150000)
      or (collisions = 1 and duration_ms >= 150000)
      or raw_score not between 0 and 200000
      or raw_score % 10 <> 0
      or raw_score < stars_collected * 100 then
      raise exception 'invalid lily frog result';
    end if;

    insert into public.scores (
      attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
    ) values (
      active_attempt.id, current_user_id, active_attempt.play_date,
      active_attempt.game_id, active_attempt.game_version, raw_score, duration_ms
    );

    update public.attempts
    set status = 'submitted', submitted_at = now()
    where id = active_attempt.id;

    return public.get_my_daily_result(active_attempt.play_date);
  end if;

  if active_attempt.game_id is distinct from 'ten_pitch_slugger'
    or active_attempt.game_version is distinct from 7 then
    return public.submit_daily_score_before_android22_slugger_v7(
      attempt_id, raw_score, stars_collected, collisions, duration_ms
    );
  end if;

  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued' then
    raise exception 'active attempt not found';
  end if;

  scheduled_duration := active_attempt.game_duration_seconds;
  if scheduled_duration is null then
    raise exception 'attempt game rules not found';
  end if;

  perform public.assert_score_submission_elapsed(
    active_attempt.issued_at, duration_ms
  );

  if raw_score is null
    or stars_collected is null
    or collisions is null
    or duration_ms is null
    or raw_score not between 0 and 16875
    or stars_collected not between 0 and 10
    or collisions not between 0 and 10
    or stars_collected + collisions <> 10
    or duration_ms not between 25000 and scheduled_duration * 1000
    or (stars_collected = 0 and raw_score <> 0)
    or (stars_collected > 0 and raw_score < 3500) then
    raise exception 'invalid ten pitch slugger result';
  end if;

  insert into public.scores (
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values (
    active_attempt.id, current_user_id, active_attempt.play_date,
    active_attempt.game_id, active_attempt.game_version, raw_score, duration_ms
  );

  update public.attempts
  set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;

  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

revoke all on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  from public, anon;
grant execute on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  to authenticated;

do $$
begin
  if not exists (
    select 1 from public.app_runtime_config
    where id and minimum_supported_build = 22
      and ios_minimum_supported_build = 26
      and android_minimum_supported_build = 22
      and update_reward_enabled
      and update_reward_campaign = 'ios-build-26-update-reward'
      and update_reward_target_build = 26
      and update_reward_started_at is not null
  ) then
    raise exception 'platform build floors were not aligned';
  end if;

  if exists (
    select 1 from public.daily_games as scheduled
    left join public.game_rule_versions as rules
      on rules.game_id = scheduled.game_id
      and rules.version = scheduled.game_version
    where scheduled.play_date > public.current_play_date()
      and (rules.game_id is null or rules.minimum_app_build > 22)
  ) then
    raise exception 'a future schedule does not support Android build 22';
  end if;

  if exists (
    select 1 from public.daily_games as scheduled
    join public.games as catalog on catalog.id = scheduled.game_id
    where scheduled.play_date > public.current_play_date()
      and scheduled.game_id in (
        'beat_the_dealer', 'ten_pitch_slugger', 'lily_frog'
      )
      and scheduled.game_version is distinct from catalog.version
  ) then
    raise exception 'a future schedule has a stale game version';
  end if;
end;
$$;

commit;

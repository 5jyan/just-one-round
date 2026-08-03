-- After the two ranked attempts are used, let players keep practicing behind
-- the same verified AdMob reward flow. Practice sessions never create an
-- attempts or scores row, so they cannot affect history, rewards, or ranking.

alter table public.rewarded_ad_grants
  add column grant_purpose text not null default 'ranked_extra',
  add column game_id text,
  add column game_version integer,
  add column game_duration_seconds smallint;

alter table public.rewarded_ad_grants
  add constraint rewarded_ad_grants_purpose_check
  check (grant_purpose in ('ranked_extra', 'practice'));

alter table public.rewarded_ad_grants
  add constraint rewarded_ad_grants_practice_snapshot_check
  check (
    grant_purpose = 'ranked_extra'
    or (
      game_id is not null
      and game_version is not null
      and game_version > 0
      and game_duration_seconds is not null
      and game_duration_seconds > 0
    )
  );

create index rewarded_ad_grants_practice_idx
  on public.rewarded_ad_grants (user_id, play_date, prepared_at desc)
  where grant_purpose = 'practice';

create or replace function public.prepare_practice_ad(expected_play_date date)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  second_attempt public.attempts;
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

  select profile.is_test_account
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

  select *
  into second_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = play_day
    and ordinal = 2
    and status <> 'issued';

  if second_attempt is null then
    raise exception 'practice requires two completed attempts';
  end if;

  scheduled_game := public.ensure_daily_game(play_day);

  select *
  into selected_game
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
    and grant_purpose = 'practice'
    and status in ('prepared', 'verified')
    and expires_at <= now();

  select *
  into active_grant
  from public.rewarded_ad_grants
  where user_id = current_user_id
    and play_date = play_day
    and grant_purpose = 'practice'
    and status in ('prepared', 'verified')
    and expires_at > now()
  order by prepared_at desc
  limit 1
  for update;

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

create or replace function public.prepare_practice_ad()
returns jsonb
language sql
security definer set search_path = ''
as $$
  select public.prepare_practice_ad(public.current_play_date());
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
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select *
  into target_grant
  from public.rewarded_ad_grants
  where id = reward_session_id
    and user_id = current_user_id
    and play_date = play_day
    and grant_purpose = 'practice'
  for update;

  if target_grant is null then
    raise exception 'practice session not found';
  end if;

  if target_grant.status = 'consumed' then
    return jsonb_build_object(
      'id', target_grant.id,
      'ordinal', 3,
      'status', 'practice',
      'grant_type', 'practice_ad',
      'game_id', target_grant.game_id,
      'game_version', target_grant.game_version,
      'game_duration_seconds', target_grant.game_duration_seconds,
      'play_date', target_grant.play_date
    );
  end if;

  if target_grant.status <> 'verified' then
    raise exception 'reward verification pending';
  end if;

  update public.rewarded_ad_grants
  set status = 'consumed', consumed_at = now()
  where id = reward_session_id;

  return jsonb_build_object(
    'id', target_grant.id,
    'ordinal', 3,
    'status', 'practice',
    'grant_type', 'practice_ad',
    'game_id', target_grant.game_id,
    'game_version', target_grant.game_version,
    'game_duration_seconds', target_grant.game_duration_seconds,
    'play_date', target_grant.play_date
  );
end;
$$;

-- Keep the state response compatible with the current issue-timestamp and
-- Kakao-retention wrappers while exposing the practice button condition.
create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date;
  state jsonb;
  is_test boolean := false;
  practice_available boolean := false;
begin
  state := public.get_today_state_without_kakao_requirement();
  play_day := (state->>'play_date')::date;

  select profile.is_test_account
  into is_test
  from public.profiles profile
  where profile.id = current_user_id;

  if not coalesce(is_test, false) and public.rewarded_ads_enabled() then
    practice_available := exists (
      select 1
      from public.attempts attempt
      where attempt.user_id = current_user_id
        and attempt.play_date = play_day
        and attempt.ordinal = 2
        and attempt.status <> 'issued'
    );
  end if;

  return state || jsonb_build_object(
    'requires_kakao_for_daily_play',
    public.kakao_required_for_daily_play(play_day),
    'practice_available',
    practice_available
  );
end;
$$;

revoke all on function public.prepare_practice_ad() from public;
revoke all on function public.prepare_practice_ad(date) from public;
revoke all on function public.claim_practice_attempt(uuid) from public;
grant execute on function public.prepare_practice_ad() to authenticated;
grant execute on function public.prepare_practice_ad(date) to authenticated;
grant execute on function public.claim_practice_attempt(uuid) to authenticated;

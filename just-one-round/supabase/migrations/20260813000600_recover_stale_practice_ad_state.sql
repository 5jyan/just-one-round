-- A client can retain the pre-verification home state while the first
-- practice ad is being verified in the background. If that stale state later
-- calls prepare_practice_ad again, recover the already-consumed practice
-- grant. The client probes claim_practice_attempt before showing an ad, so it
-- enters the existing practice session without displaying a second ad.
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

  -- Recover only a consumed practice grant that already owns a play session.
  -- claim_practice_attempt is idempotent for this exact case, and the client
  -- calls it before attempting to show another rewarded ad.
  select grant_row.* into active_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
    and grant_row.status = 'consumed'
    and exists (
      select 1
      from public.daily_play_sessions session
      where session.reward_grant_id = grant_row.id
        and session.user_id = current_user_id
        and session.play_date = play_day
        and session.play_mode = 'practice'
    )
  order by grant_row.consumed_at desc
  limit 1;

  if active_grant is not null then
    return jsonb_build_object(
      'id', active_grant.id,
      'user_id', active_grant.user_id,
      'status', active_grant.status,
      'expires_at', active_grant.expires_at
    );
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

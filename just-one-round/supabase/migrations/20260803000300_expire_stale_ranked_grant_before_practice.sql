-- A test-mode session can leave an old ranked-extra grant prepared while the
-- same account already has two completed attempts. Expire that no-longer
-- claimable grant before creating a practice grant, otherwise the legacy
-- one-active-grant index rejects the practice insert.

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
    and grant_purpose = 'ranked_extra'
    and status = 'prepared';

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

revoke all on function public.prepare_practice_ad() from public;
revoke all on function public.prepare_practice_ad(date) from public;
grant execute on function public.prepare_practice_ad() to authenticated;
grant execute on function public.prepare_practice_ad(date) to authenticated;

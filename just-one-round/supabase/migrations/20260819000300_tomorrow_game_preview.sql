-- Expose tomorrow's scheduled game and let players spend today's shared
-- practice-ticket balance on it. Ranked challenges remain restricted to the
-- current play date by claim_daily_attempt.

alter table public.daily_play_sessions
  add column target_game_date date;

update public.daily_play_sessions
set target_game_date = play_date
where play_mode = 'practice';

alter function public.get_today_state()
rename to get_today_state_before_tomorrow_preview;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_tomorrow_preview();
  play_day date := (state->>'play_date')::date;
  preview_day date := play_day + 1;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
begin
  scheduled_game := public.ensure_daily_game(preview_day);
  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;

  if selected_game.game_id is null then
    return state;
  end if;

  return state || jsonb_build_object(
    'tomorrow', jsonb_build_object(
      'play_date', preview_day,
      'game', jsonb_build_object(
        'id', selected_game.game_id,
        'version', selected_game.version,
        'display_name', selected_game.display_name,
        'description', selected_game.description,
        'duration_seconds', selected_game.duration_seconds
      )
    )
  );
end;
$$;

revoke all on function public.get_today_state_before_tomorrow_preview()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

create function public.claim_preview_practice(
  expected_play_date date,
  game_date date,
  play_request_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  choice_state jsonb;
  play_count integer;
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  existing_session public.daily_play_sessions;
  verified_grant public.rewarded_ad_grants;
  claimed_session public.daily_play_sessions;
  is_test boolean := false;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if game_date is distinct from play_day + 1 then
    raise exception 'preview game changed';
  end if;
  if play_request_id is null then
    raise exception 'play request id required';
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

  scheduled_game := public.ensure_daily_game(game_date);
  select * into selected_game
  from public.game_rule_versions versioned
  where versioned.game_id = scheduled_game.game_id
    and versioned.version = scheduled_game.game_version;
  if selected_game.game_id is null then
    raise exception 'game version not found';
  end if;

  select * into existing_session
  from public.daily_play_sessions session
  where session.user_id = current_user_id
    and session.play_date = play_day
    and session.client_request_id = play_request_id;

  if existing_session.id is null then
    select * into existing_session
    from public.daily_play_sessions session
    where session.user_id = current_user_id
      and session.play_date = play_day
      and session.play_mode = 'practice'
      and session.started_at is null
    order by session.created_at, session.id
    limit 1
    for update;

    if existing_session.id is not null
      and existing_session.client_request_id is distinct from play_request_id then
      update public.daily_play_sessions
      set client_request_id = play_request_id
      where id = existing_session.id
      returning * into existing_session;
    end if;
  end if;

  if existing_session.id is not null then
    return jsonb_build_object(
      'id', existing_session.id,
      'ordinal', existing_session.ordinal,
      'status', 'practice',
      'grant_type', case
        when existing_session.reward_grant_id is null then 'practice_daily'
        else 'practice_ad'
      end,
      'game_id', existing_session.game_id,
      'game_version', existing_session.game_version,
      'game_duration_seconds', existing_session.game_duration_seconds,
      'play_date', coalesce(existing_session.target_game_date, play_day),
      'issued_at', existing_session.created_at,
      'practice_ordinal',
        public.practice_ordinal_for_session(existing_session.id),
      'client_request_id', existing_session.client_request_id
    );
  end if;

  choice_state := public.daily_play_choice_state(current_user_id, play_day);
  if not coalesce((choice_state->>'practice_available')::boolean, false) then
    raise exception 'practice is not available';
  end if;

  select * into verified_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'practice'
    and grant_row.status = 'verified'
  order by grant_row.prepared_at desc
  limit 1
  for update;

  play_count := coalesce((choice_state->>'play_count')::integer, 0);
  if play_count = 0 then
    perform public.claim_first_device_play(current_user_id, play_day);
  end if;

  insert into public.daily_play_sessions (
    user_id, play_date, ordinal, play_mode, reward_grant_id,
    game_id, game_version, game_duration_seconds, created_at,
    client_request_id, target_game_date
  ) values (
    current_user_id,
    play_day,
    (play_count + 1)::smallint,
    'practice',
    verified_grant.id,
    selected_game.game_id,
    selected_game.version,
    selected_game.duration_seconds,
    coalesce(verified_grant.prepared_at, now()),
    play_request_id,
    game_date
  )
  returning * into claimed_session;

  if verified_grant.id is not null then
    update public.rewarded_ad_grants
    set status = 'consumed', consumed_at = now()
    where id = verified_grant.id;
  end if;

  return jsonb_build_object(
    'id', claimed_session.id,
    'ordinal', claimed_session.ordinal,
    'status', 'practice',
    'grant_type', case
      when verified_grant.id is null then 'practice_daily'
      else 'practice_ad'
    end,
    'game_id', claimed_session.game_id,
    'game_version', claimed_session.game_version,
    'game_duration_seconds', claimed_session.game_duration_seconds,
    'play_date', game_date,
    'issued_at', claimed_session.created_at,
    'practice_ordinal',
      public.practice_ordinal_for_session(claimed_session.id),
    'client_request_id', claimed_session.client_request_id
  );
end;
$$;

comment on function public.claim_preview_practice(date, date, uuid) is
  'Spends the current day shared practice balance on tomorrow scheduled game.';

revoke all on function public.claim_preview_practice(date, date, uuid)
  from public;
grant execute on function public.claim_preview_practice(date, date, uuid)
  to authenticated;

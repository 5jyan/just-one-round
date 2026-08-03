-- Keep rewarded extra play available to anonymous accounts.
-- Kakao linking remains available for account retention, but it is not a
-- prerequisite for the AdMob reward flow.

create or replace function public.prepare_rewarded_ad(expected_play_date date)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  first_attempt public.attempts;
  active_grant public.rewarded_ad_grants;
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

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select * into first_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = play_day
    and ordinal = 1;

  if first_attempt is null or first_attempt.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;

  if exists (
    select 1 from public.attempts
    where user_id = current_user_id
      and play_date = play_day
      and ordinal = 2
  ) then
    raise exception 'rewarded attempt already claimed';
  end if;

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and status in ('prepared', 'verified')
    and expires_at <= now();

  select * into active_grant
  from public.rewarded_ad_grants
  where user_id = current_user_id
    and play_date = play_day
    and status in ('prepared', 'verified')
    and expires_at > now()
  order by prepared_at desc
  limit 1
  for update;

  if active_grant is null then
    insert into public.rewarded_ad_grants (
      user_id,
      play_date,
      expires_at
    ) values (
      current_user_id,
      play_day,
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

create or replace function public.claim_rewarded_attempt(
  reward_session_id uuid
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  first_attempt public.attempts;
  existing_attempt public.attempts;
  scheduled_game public.daily_games;
  target_grant public.rewarded_ad_grants;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into target_grant
  from public.rewarded_ad_grants
  where id = reward_session_id
    and user_id = current_user_id
    and play_date = play_day
  for update;

  if target_grant is null then
    raise exception 'daily game changed';
  end if;

  select * into existing_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = play_day
    and ordinal = 2;

  if target_grant.status = 'consumed' and existing_attempt is not null then
    return existing_attempt;
  end if;

  if target_grant.status <> 'verified' then
    raise exception 'reward verification pending';
  end if;

  select * into first_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = play_day
    and ordinal = 1;

  if first_attempt is null or first_attempt.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;

  scheduled_game := public.ensure_daily_game(play_day);

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type
  ) values (
    current_user_id, play_day, scheduled_game.game_id,
    scheduled_game.game_version, 2, 'rewarded_ad'
  )
  on conflict (user_id, play_date, ordinal) do nothing
  returning * into claimed_attempt;

  if claimed_attempt is null then
    select * into claimed_attempt
    from public.attempts
    where user_id = current_user_id
      and play_date = play_day
      and ordinal = 2;
  end if;

  update public.rewarded_ad_grants
  set status = 'consumed', consumed_at = now()
  where id = reward_session_id;

  return claimed_attempt;
end;
$$;

revoke all on function public.prepare_rewarded_ad(date) from public;
revoke all on function public.claim_rewarded_attempt(uuid) from public;
grant execute on function public.prepare_rewarded_ad(date) to authenticated;
grant execute on function public.claim_rewarded_attempt(uuid) to authenticated;

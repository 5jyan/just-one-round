-- Award a small, server-authoritative coin grant for one shop ad per day.

alter table public.rewarded_ad_grants
  drop constraint rewarded_ad_grants_purpose_check,
  add constraint rewarded_ad_grants_purpose_check
    check (grant_purpose in ('ranked_extra', 'practice', 'coin'));

alter table public.rewarded_ad_grants
  drop constraint rewarded_ad_grants_practice_snapshot_check,
  add constraint rewarded_ad_grants_practice_snapshot_check
    check (
      grant_purpose in ('ranked_extra', 'coin')
      or (
        game_id is not null
        and game_version is not null
        and game_version > 0
        and game_duration_seconds is not null
        and game_duration_seconds > 0
      )
    );

create index rewarded_ad_grants_coin_idx
  on public.rewarded_ad_grants (user_id, play_date, prepared_at desc)
  where grant_purpose = 'coin';

create function public.prepare_coin_ad(expected_play_date date)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  active_grant public.rewarded_ad_grants;
  is_test boolean := false;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if not public.rewarded_ads_enabled() then
    raise exception 'rewarded ads disabled';
  end if;

  select coalesce(profile.is_test_account, false) into is_test
  from public.profiles profile where profile.id = current_user_id;
  if is_test then raise exception 'coin ad unavailable in test mode'; end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text), hashtext(play_day::text)
  );

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and status in ('prepared', 'verified')
    and expires_at <= now();

  if exists (
    select 1 from public.rewarded_ad_grants grant_row
    where grant_row.user_id = current_user_id
      and grant_row.play_date = play_day
      and grant_row.grant_purpose = 'coin'
      and grant_row.status = 'consumed'
  ) then
    raise exception 'daily coin ad already used';
  end if;

  select grant_row.* into active_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'coin'
    and grant_row.status in ('prepared', 'verified')
    and grant_row.expires_at > now()
  order by grant_row.prepared_at desc limit 1 for update;

  if active_grant.id is null and exists (
    select 1 from public.rewarded_ad_grants grant_row
    where grant_row.user_id = current_user_id
      and grant_row.play_date = play_day
      and grant_row.grant_purpose <> 'coin'
      and grant_row.status in ('prepared', 'verified')
      and grant_row.expires_at > now()
  ) then
    raise exception 'another reward is pending';
  end if;

  if active_grant.id is null then
    insert into public.rewarded_ad_grants (
      user_id, play_date, grant_purpose, expires_at
    ) values (
      current_user_id, play_day, 'coin', public.next_daily_reset_at(play_day)
    ) returning * into active_grant;
  end if;

  return jsonb_build_object(
    'id', active_grant.id,
    'user_id', active_grant.user_id,
    'status', active_grant.status,
    'expires_at', active_grant.expires_at
  );
end;
$$;

create function public.claim_coin_ad_reward(reward_session_id uuid)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  target_grant public.rewarded_ad_grants;
  transaction_result jsonb;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text), hashtext(play_day::text)
  );

  select grant_row.* into target_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.id = reward_session_id
    and grant_row.user_id = current_user_id
    and grant_row.play_date = play_day
    and grant_row.grant_purpose = 'coin'
  for update;

  if target_grant.id is null then raise exception 'coin reward session not found'; end if;
  if target_grant.status not in ('verified', 'consumed') then
    raise exception 'reward verification pending';
  end if;

  transaction_result := public.apply_coin_transaction(
    current_user_id,
    50,
    0,
    'coin_ad_reward',
    'coin-ad:' || target_grant.id::text,
    null,
    play_day,
    jsonb_build_object('reward_session_id', target_grant.id)
  );

  if target_grant.status = 'verified' then
    update public.rewarded_ad_grants
    set status = 'consumed', consumed_at = now()
    where id = target_grant.id;
  end if;

  return transaction_result || jsonb_build_object('coins_granted', 50);
end;
$$;

create function public.verify_local_coin_ad_for_development(
  reward_session_id uuid
)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  target_grant public.rewarded_ad_grants;
  bypass_enabled boolean := false;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select config.local_test_ad_verification_enabled into bypass_enabled
  from public.app_runtime_config config where config.id;
  if not coalesce(bypass_enabled, false) then
    raise exception 'local test ad verification disabled';
  end if;

  select grant_row.* into target_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.id = reward_session_id
    and grant_row.user_id = current_user_id
    and grant_row.play_date = public.current_play_date()
    and grant_row.grant_purpose = 'coin'
  for update;

  if target_grant.id is null then raise exception 'coin reward session not found'; end if;
  if target_grant.status in ('verified', 'consumed') then return; end if;
  if target_grant.status <> 'prepared' or target_grant.expires_at <= now() then
    raise exception 'coin reward session unavailable';
  end if;

  update public.rewarded_ad_grants
  set status = 'verified',
      provider_transaction_id = coalesce(
        provider_transaction_id, 'local-coin-test-' || id::text
      ),
      reward_item = 'coin', reward_amount = 50,
      verified_at = coalesce(verified_at, now())
  where id = target_grant.id;
end;
$$;

alter function public.get_today_state()
rename to get_today_state_before_coin_ad;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb := public.get_today_state_before_coin_ad();
  current_user_id uuid := (select auth.uid());
  play_day date := (state->>'play_date')::date;
  coin_ad_used boolean;
begin
  select exists (
    select 1 from public.rewarded_ad_grants grant_row
    where grant_row.user_id = current_user_id
      and grant_row.play_date = play_day
      and grant_row.grant_purpose = 'coin'
      and grant_row.status = 'consumed'
  ) into coin_ad_used;

  return state || jsonb_build_object(
    'coin_ad_available',
      not coalesce((state->>'test_mode')::boolean, false)
      and public.rewarded_ads_enabled()
      and not coalesce(coin_ad_used, false)
  );
end;
$$;

revoke all on function public.prepare_coin_ad(date) from public, anon;
revoke all on function public.claim_coin_ad_reward(uuid) from public, anon;
revoke all on function public.verify_local_coin_ad_for_development(uuid)
  from public, anon;
revoke all on function public.get_today_state_before_coin_ad()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.prepare_coin_ad(date) to authenticated;
grant execute on function public.claim_coin_ad_reward(uuid) to authenticated;
grant execute on function public.verify_local_coin_ad_for_development(uuid)
  to authenticated;
grant execute on function public.get_today_state() to authenticated;

comment on function public.prepare_coin_ad(date) is
  'Prepares the single daily shop ad that rewards 50 coins.';
comment on function public.claim_coin_ad_reward(uuid) is
  'Idempotently grants 50 coins after server-side rewarded-ad verification.';

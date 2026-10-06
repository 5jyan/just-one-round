-- Automatically settle a previous-day reward after its one-day display window
-- closes. The acknowledgement row and the ledger reference are both unique,
-- so a manual confirmation, app refresh, and scheduled settlement all share
-- one idempotent payout path.

create or replace function public.apply_daily_result_reward(
  target_date date,
  target_game_id text
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  result jsonb;
  reward_coins integer;
  reward_experience integer;
  inserted_acknowledgement integer;
  transaction_result jsonb;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if target_date is null or target_game_id is null then
    raise exception 'daily result target is required';
  end if;
  if target_date >= public.current_play_date() then
    raise exception 'daily result is not finished';
  end if;
  if exists (
    select 1
    from public.profiles profile
    where profile.id = current_user_id and profile.is_test_account
  ) then
    raise exception 'test account cannot claim economy reward';
  end if;
  if not exists (
    select 1
    from public.scores score
    where score.user_id = current_user_id
      and score.play_date = target_date
      and score.game_id = target_game_id
  ) then
    raise exception 'daily result not found';
  end if;

  result := public.get_my_daily_result(target_date);
  if result->>'score' is null
    or result->>'rank' is null
    or result->>'participants' is null then
    raise exception 'daily result not found';
  end if;

  reward_coins := public.daily_result_reward_coins(
    (result->>'rank')::integer,
    (result->>'participants')::integer
  );
  reward_experience := reward_coins;

  insert into public.daily_result_acknowledgements (
    user_id,
    play_date,
    game_id
  ) values (
    current_user_id,
    target_date,
    target_game_id
  ) on conflict do nothing;
  get diagnostics inserted_acknowledgement = row_count;

  if inserted_acknowledgement = 0 then
    return public.get_my_economy() || jsonb_build_object(
      'coins_granted', 0,
      'experience_granted', 0,
      'was_applied', false
    );
  end if;

  transaction_result := public.apply_coin_transaction(
    current_user_id,
    reward_coins,
    reward_experience,
    'daily_result_reward',
    'daily_result:' || target_date::text || ':' || target_game_id,
    target_game_id,
    target_date,
    jsonb_build_object(
      'rank', (result->>'rank')::integer,
      'participants', (result->>'participants')::integer,
      'top_percent', (result->>'top_percent')::integer
    )
  );

  return transaction_result || jsonb_build_object(
    'coins_granted', reward_coins,
    'experience_granted', reward_experience
  );
end;
$$;

-- The button keeps its current one-day-only contract. Older results are
-- settled by the automatic path below once the user has had the whole day to
-- inspect the popup.
create or replace function public.acknowledge_previous_daily_result(
  target_date date,
  target_game_id text
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
begin
  if target_date is distinct from public.current_play_date() - 1 then
    raise exception 'result is not from the previous play date';
  end if;
  return public.apply_daily_result_reward(target_date, target_game_id);
end;
$$;

create or replace function public.auto_claim_expired_daily_result_rewards()
returns integer
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_play_day date := public.current_play_date();
  pending record;
  claimed_count integer := 0;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if exists (
    select 1
    from public.profiles profile
    where profile.id = current_user_id and profile.is_test_account
  ) then
    return 0;
  end if;

  -- The previous result remains manually claimable for the whole current
  -- play day. At the next 06:00 boundary it becomes an expired popup and is
  -- settled here. DISTINCT ON mirrors the popup's latest-score selection.
  for pending in
    select distinct on (score.play_date)
      score.play_date,
      score.game_id
    from public.scores score
    where score.user_id = current_user_id
      and score.play_date <= current_play_day - 2
      and not exists (
        select 1
        from public.daily_result_acknowledgements acknowledgement
        where acknowledgement.user_id = current_user_id
          and acknowledgement.play_date = score.play_date
          and acknowledgement.game_id = score.game_id
      )
    order by score.play_date, score.submitted_at desc, score.attempt_id desc
  loop
    perform public.apply_daily_result_reward(
      pending.play_date,
      pending.game_id
    );
    claimed_count := claimed_count + 1;
  end loop;

  return claimed_count;
end;
$$;

-- A scheduled server call handles users who are offline. The app-side calls
-- below remain as a recovery path when pg_cron is unavailable or delayed.
create or replace function public.auto_claim_expired_daily_result_rewards_for_all_users()
returns integer
language plpgsql
security definer set search_path = ''
as $$
declare
  original_subject text := current_setting('request.jwt.claim.sub', true);
  profile_row record;
  claimed_count integer := 0;
begin
  for profile_row in
    select profile.id
    from public.profiles profile
    where not profile.is_test_account
  loop
    -- The existing result/economy functions intentionally operate on
    -- auth.uid(). This server-only function supplies the trusted subject for
    -- each account while the transaction is open; it is never client-granted.
    perform set_config(
      'request.jwt.claim.sub',
      profile_row.id::text,
      true
    );
    claimed_count := claimed_count
      + public.auto_claim_expired_daily_result_rewards();
  end loop;

  perform set_config(
    'request.jwt.claim.sub',
    coalesce(original_subject, ''),
    true
  );
  return claimed_count;
end;
$$;

revoke all on function public.apply_daily_result_reward(date, text)
  from public, anon, authenticated, service_role;
revoke all on function public.auto_claim_expired_daily_result_rewards()
  from public, anon, authenticated, service_role;
revoke all on function public.auto_claim_expired_daily_result_rewards_for_all_users()
  from public, anon, authenticated, service_role;
revoke all on function public.acknowledge_previous_daily_result(date, text)
  from public, anon;
grant execute on function public.acknowledge_previous_daily_result(date, text)
  to authenticated;

-- Supabase databases run on UTC by default. 21:01 UTC is 06:01 KST, just after
-- the daily boundary when the previous popup's display window closes. That
-- result has already been final since the preceding day's 06:10 deadline.
-- If pg_cron is not enabled in an environment, the guarded block skips the
-- job and the get_today_state/get_unseen wrappers still settle on next use.
do $migration$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    null;
  end;
end;
$migration$;

do $migration$
declare
  existing_job record;
begin
  if to_regnamespace('cron') is null then
    return;
  end if;

  for existing_job in
    execute
      'select jobid from cron.job where jobname = $1'
    using 'just-one-round-settle-daily-rewards'
  loop
    execute 'select cron.unschedule($1)' using existing_job.jobid;
  end loop;

  execute 'select cron.schedule($1, $2, $3)'
  using
    'just-one-round-settle-daily-rewards',
    '1 21 * * *',
    'select public.auto_claim_expired_daily_result_rewards_for_all_users();';
exception when others then
  -- Client-side lazy settlement remains authoritative if a deployment does
  -- not permit cron jobs from migrations.
  null;
end;
$migration$;

-- Settle stale rewards before the popup lookup, so an old popup cannot remain
-- claimable after its display day has ended.
alter function public.get_unseen_previous_daily_result()
rename to get_unseen_previous_daily_result_before_auto_settlement;

create function public.get_unseen_previous_daily_result()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
begin
  perform public.auto_claim_expired_daily_result_rewards();
  return public.get_unseen_previous_daily_result_before_auto_settlement();
end;
$$;

revoke all on function public.get_unseen_previous_daily_result_before_auto_settlement()
  from public, anon, authenticated, service_role;
revoke all on function public.get_unseen_previous_daily_result()
  from public, anon;
grant execute on function public.get_unseen_previous_daily_result()
  to authenticated;

-- Keep the economy returned by the home state in sync even when the user
-- opens the app after several missed days.
alter function public.get_today_state()
rename to get_today_state_before_auto_settlement;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
begin
  perform public.auto_claim_expired_daily_result_rewards();
  return public.get_today_state_before_auto_settlement();
end;
$$;

revoke all on function public.get_today_state_before_auto_settlement()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public, anon;
grant execute on function public.get_today_state() to authenticated;

comment on function public.auto_claim_expired_daily_result_rewards() is
  'Settles unacknowledged daily result rewards after their display day closes.';

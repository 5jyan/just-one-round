-- The client can enter a rewarded game before the AdMob SSV callback arrives.
-- Anchor the ranked attempt's elapsed-time check to the ad session start so a
-- delayed callback does not make a legitimately completed short game look
-- impossibly fast.

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
    scheduled_game.game_id,
    scheduled_game.game_version,
    2,
    'rewarded_ad',
    target_grant.prepared_at
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

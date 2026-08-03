-- Give the previous day's result a server-owned, idempotent reward path.
-- Coins are a spendable wallet balance; experience is cumulative and is not
-- reduced when a future game spends coins.

alter table public.profiles
  add column coin_balance bigint not null default 0,
  add column experience_points bigint not null default 0,
  add constraint profiles_coin_balance_range
    check (coin_balance between 0 and 1000000000),
  add constraint profiles_experience_points_range
    check (experience_points between 0 and 1000000000);

-- Economy fields must not be writable through the table API. Nicknames are
-- still changed through the existing SECURITY DEFINER RPC.
drop policy if exists "profiles_update_own" on public.profiles;
revoke update on public.profiles from public, anon, authenticated;

create table public.coin_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  coin_delta bigint not null,
  experience_delta bigint not null default 0,
  balance_after bigint not null,
  transaction_type text not null,
  reference_key text not null,
  game_id text,
  play_date date,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint coin_transactions_coin_delta_nonzero check (coin_delta <> 0),
  constraint coin_transactions_experience_delta_nonnegative
    check (experience_delta >= 0),
  constraint coin_transactions_balance_after_nonnegative
    check (balance_after >= 0),
  constraint coin_transactions_type_present
    check (char_length(btrim(transaction_type)) between 1 and 48),
  constraint coin_transactions_reference_present
    check (char_length(btrim(reference_key)) between 1 and 160)
);

create unique index coin_transactions_user_reference_idx
  on public.coin_transactions (user_id, reference_key);

create index coin_transactions_user_created_idx
  on public.coin_transactions (user_id, created_at desc);

alter table public.coin_transactions enable row level security;
revoke all on table public.coin_transactions from public, anon, authenticated;

create or replace function public.experience_level(total_experience bigint)
returns integer
language sql
immutable
strict
security definer set search_path = ''
as $$
  select floor(sqrt(greatest(total_experience, 0)::numeric / 100))::integer + 1;
$$;

create or replace function public.build_player_economy_json(
  total_coins bigint,
  total_experience bigint
)
returns jsonb
language sql
immutable
security definer set search_path = ''
as $$
  with values as (
    select
      greatest(total_coins, 0) as coins,
      greatest(total_experience, 0) as experience_points,
      public.experience_level(greatest(total_experience, 0)) as level
  )
  select jsonb_build_object(
    'coins', values.coins,
    'experience_points', values.experience_points,
    'level', values.level,
    'experience_to_next_level', greatest(
      0,
      (values.level::bigint * values.level::bigint * 100)
        - values.experience_points
    )
  )
  from values;
$$;

create or replace function public.daily_result_reward_coins(
  result_rank integer,
  result_participants integer
)
returns integer
language plpgsql
immutable
security definer set search_path = ''
as $$
declare
  top_percent integer;
begin
  if result_rank <= 0
    or result_participants <= 0
    or result_rank > result_participants then
    return 0;
  end if;
  if result_rank = 1 then
    return 100;
  end if;

  top_percent := greatest(
    1,
    ceil(result_rank::numeric * 100 / result_participants)::integer
  );

  if top_percent <= 1 then return 100; end if;
  if top_percent <= 5 then return 80; end if;
  if top_percent <= 10 then return 60; end if;
  if top_percent <= 25 then return 40; end if;
  if top_percent <= 50 then return 25; end if;
  return 10;
end;
$$;

-- This is the only reusable balance mutation primitive. It is intentionally
-- not exposed to client roles; game-specific RPCs call it server-side.
create or replace function public.apply_coin_transaction(
  target_user_id uuid,
  coin_delta bigint,
  experience_delta bigint,
  target_transaction_type text,
  target_reference_key text,
  target_game_id text default null,
  target_play_date date default null,
  transaction_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_coins bigint;
  current_experience bigint;
  next_coins bigint;
  next_experience bigint;
  existing_id uuid;
  existing_coin_delta bigint;
  existing_experience_delta bigint;
  economy jsonb;
begin
  if target_user_id is null then
    raise exception 'user is required';
  end if;
  if coin_delta = 0 then
    raise exception 'coin delta must not be zero';
  end if;
  if experience_delta < 0 then
    raise exception 'experience delta must not be negative';
  end if;
  if target_transaction_type is null
    or char_length(btrim(target_transaction_type)) not between 1 and 48 then
    raise exception 'transaction type is invalid';
  end if;
  if target_reference_key is null
    or char_length(btrim(target_reference_key)) not between 1 and 160 then
    raise exception 'transaction reference is invalid';
  end if;

  select profile.coin_balance, profile.experience_points
  into current_coins, current_experience
  from public.profiles profile
  where profile.id = target_user_id
  for update;

  if current_coins is null or current_experience is null then
    raise exception 'profile not found';
  end if;

  select transaction.id, transaction.coin_delta, transaction.experience_delta
  into existing_id, existing_coin_delta, existing_experience_delta
  from public.coin_transactions transaction
  where transaction.user_id = target_user_id
    and transaction.reference_key = target_reference_key
  for update;

  if existing_id is not null then
    if existing_coin_delta <> coin_delta
      or existing_experience_delta <> experience_delta then
      raise exception 'transaction reference already used';
    end if;
    return public.build_player_economy_json(
      current_coins,
      current_experience
    ) || jsonb_build_object(
      'coin_delta', existing_coin_delta,
      'experience_delta', existing_experience_delta,
      'was_applied', false
    );
  end if;

  next_coins := current_coins + coin_delta;
  next_experience := current_experience + experience_delta;
  if next_coins < 0 then
    raise exception 'insufficient coin balance';
  end if;
  if next_coins > 1000000000 or next_experience > 1000000000 then
    raise exception 'economy balance limit exceeded';
  end if;

  insert into public.coin_transactions (
    user_id,
    coin_delta,
    experience_delta,
    balance_after,
    transaction_type,
    reference_key,
    game_id,
    play_date,
    metadata
  ) values (
    target_user_id,
    coin_delta,
    experience_delta,
    next_coins,
    btrim(target_transaction_type),
    btrim(target_reference_key),
    target_game_id,
    target_play_date,
    coalesce(transaction_metadata, '{}'::jsonb)
  );

  update public.profiles
  set
    coin_balance = next_coins,
    experience_points = next_experience,
    updated_at = now()
  where id = target_user_id;

  economy := public.build_player_economy_json(
    next_coins,
    next_experience
  );
  return economy || jsonb_build_object(
    'coin_delta', coin_delta,
    'experience_delta', experience_delta,
    'was_applied', true
  );
end;
$$;

create function public.get_my_economy()
returns jsonb
language plpgsql
security definer set search_path = ''
stable
as $$
declare
  current_user_id uuid := (select auth.uid());
  economy jsonb;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select public.build_player_economy_json(
    profile.coin_balance,
    profile.experience_points
  )
  into economy
  from public.profiles profile
  where profile.id = current_user_id;

  return coalesce(
    economy,
    public.build_player_economy_json(0, 0)
  );
end;
$$;

drop function public.acknowledge_previous_daily_result(date, text);

create function public.acknowledge_previous_daily_result(
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
  if target_date <> public.current_play_date() - 1 then
    raise exception 'result is not from the previous play date';
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

create or replace function public.get_unseen_previous_daily_result()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  previous_date date := public.current_play_date() - 1;
  result_available_at timestamptz :=
    ((previous_date + 1) + time '06:10') at time zone 'Asia/Seoul';
  previous_game_id text;
  previous_game_version integer;
  previous_game_name text;
  result jsonb;
  reward_coins integer;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if now() < result_available_at then
    return null;
  end if;

  if exists (
    select 1
    from public.profiles profile
    where profile.id = current_user_id and profile.is_test_account
  ) then
    return null;
  end if;

  select score.game_id, score.game_version, versioned.display_name
  into previous_game_id, previous_game_version, previous_game_name
  from public.scores score
  join public.game_rule_versions versioned
    on versioned.game_id = score.game_id
    and versioned.version = score.game_version
  where score.user_id = current_user_id
    and score.play_date = previous_date
  order by score.submitted_at desc
  limit 1;

  if previous_game_id is null or exists (
    select 1
    from public.daily_result_acknowledgements acknowledgement
    where acknowledgement.user_id = current_user_id
      and acknowledgement.play_date = previous_date
      and acknowledgement.game_id = previous_game_id
  ) then
    return null;
  end if;

  result := public.get_my_daily_result(previous_date);
  if result->'score' = 'null'::jsonb then
    return null;
  end if;

  reward_coins := public.daily_result_reward_coins(
    (result->>'rank')::integer,
    (result->>'participants')::integer
  );
  return result || jsonb_build_object(
    'play_date', previous_date,
    'game_id', previous_game_id,
    'game_version', previous_game_version,
    'display_name', previous_game_name,
    'reward_coins', reward_coins,
    'reward_experience_points', reward_coins
  );
end;
$$;

-- Keep the economy in the same response as today's game state so the home
-- screen never renders a stale wallet after a fresh state fetch.
create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  play_day date := public.current_play_date();
  scheduled_game public.daily_games;
  selected_game public.game_rule_versions;
  device_key text := public.current_device_hash();
  is_test boolean := false;
  selected_test_game_id text;
  ads_enabled boolean := public.rewarded_ads_enabled();
  device_claimed boolean := false;
begin
  scheduled_game := public.ensure_daily_game(play_day);

  select profile.is_test_account, profile.test_game_id
  into is_test, selected_test_game_id
  from public.profiles profile
  where profile.id = (select auth.uid());

  if not coalesce(is_test, false) then
    device_claimed := exists (
      select 1
      from public.device_daily_claims claim
      where claim.device_hash = device_key
        and claim.play_date = play_day
    );
  end if;

  if coalesce(is_test, false) and selected_test_game_id is not null then
    select versioned.* into selected_game
    from public.game_rule_versions versioned
    join public.games game
      on game.id = versioned.game_id and game.version = versioned.version
    where game.id = selected_test_game_id and game.is_active;
  end if;

  if selected_game is null then
    select versioned.* into selected_game
    from public.game_rule_versions versioned
    where versioned.game_id = scheduled_game.game_id
      and versioned.version = scheduled_game.game_version;
  end if;

  if selected_game is null then
    raise exception 'game version not found';
  end if;

  return (
    with my_attempts as (
      select *
      from public.attempts
      where user_id = (select auth.uid()) and play_date = play_day
    )
    select jsonb_build_object(
      'play_date', play_day,
      'game', jsonb_build_object(
        'id', selected_game.game_id,
        'version', selected_game.version,
        'display_name', selected_game.display_name,
        'description', selected_game.description,
        'duration_seconds', selected_game.duration_seconds
      ),
      'nickname', (
        select profile.nickname
        from public.profiles profile
        where profile.id = (select auth.uid())
      ),
      'economy', public.get_my_economy(),
      'attempts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'ordinal', ordinal,
        'status', status,
        'grant_type', grant_type,
        'game_id', game_id,
        'game_version', game_version,
        'game_duration_seconds', game_duration_seconds,
        'play_date', play_date
      ) order by ordinal) from my_attempts), '[]'::jsonb),
      'test_mode', coalesce(is_test, false),
      'daily_claimed', device_claimed or exists (select 1 from my_attempts),
      'ad_attempt_available', case
        when coalesce(is_test, false) or not ads_enabled then false
        else exists (
          select 1 from my_attempts where ordinal = 1 and status <> 'issued'
        ) and not exists (
          select 1 from my_attempts where ordinal = 2
        )
      end,
      'result', public.get_my_daily_result(play_day)
    )
  );
end;
$$;

create function public.spend_coins(
  amount integer,
  game_id text,
  reference_id text
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  transaction_result jsonb;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if amount not between 1 and 1000000 then
    raise exception 'coin spend amount is invalid';
  end if;
  if game_id is null or game_id !~ '^[a-z0-9_]+$' then
    raise exception 'game id is invalid';
  end if;
  if reference_id is null
    or char_length(btrim(reference_id)) not between 1 and 120
    or reference_id ~ '[[:cntrl:]]' then
    raise exception 'coin spend reference is invalid';
  end if;

  transaction_result := public.apply_coin_transaction(
    current_user_id,
    -amount,
    0,
    'coin_spend',
    'spend:' || game_id || ':' || btrim(reference_id),
    game_id,
    null,
    jsonb_build_object('amount', amount)
  );
  return transaction_result || jsonb_build_object(
    'coins_spent', amount
  );
end;
$$;

revoke all on function public.experience_level(bigint)
  from public, anon, authenticated;
revoke all on function public.build_player_economy_json(bigint, bigint)
  from public, anon, authenticated;
revoke all on function public.daily_result_reward_coins(integer, integer)
  from public, anon, authenticated;
revoke all on function public.apply_coin_transaction(
  uuid, bigint, bigint, text, text, text, date, jsonb
) from public, anon, authenticated;
revoke all on function public.get_my_economy()
  from public, anon;
revoke all on function public.get_unseen_previous_daily_result()
  from public, anon;
revoke all on function public.get_today_state()
  from public, anon;
revoke all on function public.acknowledge_previous_daily_result(date, text)
  from public, anon;
revoke all on function public.spend_coins(integer, text, text)
  from public, anon;

grant execute on function public.get_my_economy() to authenticated;
grant execute on function public.get_unseen_previous_daily_result()
  to authenticated;
grant execute on function public.get_today_state() to authenticated;
grant execute on function public.acknowledge_previous_daily_result(date, text)
  to authenticated;
grant execute on function public.spend_coins(integer, text, text)
  to authenticated;

comment on table public.coin_transactions is
  'Immutable server-owned coin and experience ledger with idempotent references.';
comment on column public.profiles.coin_balance is
  'Spendable coin wallet balance; mutate through server-side economy RPCs only.';
comment on column public.profiles.experience_points is
  'Cumulative experience; coin spending never decreases it.';

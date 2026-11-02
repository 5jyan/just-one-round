-- 1:1 coin duel rooms.
--
-- The waiting room is created before either player is charged. The second
-- successful READY transition escrows both stakes and publishes one common
-- start time. Client roles only use the RPC surface below.

alter table public.games
  add column if not exists duel_enabled boolean not null default false;

alter table public.app_runtime_config
  add column if not exists local_duel_test_enabled boolean not null default false;

comment on column public.app_runtime_config.local_duel_test_enabled is
  'Local validation only: permits duels between two isolated test accounts.';

comment on column public.games.duel_enabled is
  'Explicit operator gate. New duel code does not activate a game automatically.';

alter table public.games
  add constraint games_duel_excluded_check
  check (duel_enabled = false or id not in ('wind_darts', 'western_duel'));

create table public.duel_matches (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  opponent_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null references public.games(id),
  game_version integer not null,
  stake bigint not null,
  runtime_revision text not null default 'duel-v1',
  status text not null default 'waiting',
  outcome text,
  winner_id uuid references auth.users(id),
  room_revision bigint not null default 1,
  waiting_expires_at timestamptz not null default (now() + interval '10 minutes'),
  start_at timestamptz,
  submit_deadline timestamptz,
  seed bigint,
  game_duration_seconds integer not null,
  result_reveal_allowance_seconds integer not null default 5,
  charged boolean not null default false,
  client_request_id uuid not null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  settled_at timestamptz,
  constraint duel_matches_distinct_users check (requester_id <> opponent_id),
  constraint duel_matches_stake_range check (stake >= 10 and stake % 10 = 0),
  constraint duel_matches_status_check check (
    status in ('waiting', 'starting', 'playing', 'settled', 'declined',
      'cancelled', 'expired', 'voided')
  ),
  constraint duel_matches_outcome_check check (
    outcome is null or outcome in ('requester_win', 'opponent_win', 'tie',
      'refund', 'void')
  ),
  constraint duel_matches_game_version_positive check (game_version > 0),
  constraint duel_matches_duration_positive check (game_duration_seconds > 0),
  constraint duel_matches_allowance_nonnegative check (
    result_reveal_allowance_seconds >= 0
  ),
  unique (requester_id, client_request_id)
);

create unique index duel_matches_pair_open_idx
  on public.duel_matches (least(requester_id, opponent_id), greatest(requester_id, opponent_id))
  where status in ('waiting', 'starting', 'playing');
create index duel_matches_requester_status_idx
  on public.duel_matches (requester_id, status, created_at desc);
create index duel_matches_opponent_status_idx
  on public.duel_matches (opponent_id, status, created_at desc);
create index duel_matches_waiting_expiry_idx
  on public.duel_matches (waiting_expires_at) where status = 'waiting';

create table public.duel_runs (
  id uuid primary key default gen_random_uuid(),
  duel_id uuid not null references public.duel_matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('requester', 'opponent')),
  session_token uuid not null default gen_random_uuid(),
  session_generation bigint not null default 1,
  presence_expires_at timestamptz,
  joined_at timestamptz,
  loading_complete boolean not null default false,
  ready boolean not null default false,
  client_runtime_revision text,
  run_token uuid,
  run_status text not null default 'waiting',
  started_at timestamptz,
  submit_deadline timestamptz,
  raw_score bigint,
  duration_ms integer,
  result_kind text,
  terminal_reason text,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint duel_runs_status_check check (
    run_status in ('waiting', 'starting', 'playing', 'submitted',
      'forfeited', 'no_result')
  ),
  constraint duel_runs_result_kind_check check (
    result_kind is null or result_kind in ('valid', 'no_result', 'forfeit')
  ),
  constraint duel_runs_score_nonnegative check (raw_score is null or raw_score >= 0),
  constraint duel_runs_duration_nonnegative check (duration_ms is null or duration_ms >= 0),
  unique (duel_id, user_id),
  unique (duel_id, role)
);

create index duel_runs_user_status_idx
  on public.duel_runs (user_id, run_status, created_at desc);

alter table public.duel_matches enable row level security;
alter table public.duel_runs enable row level security;
revoke all on table public.duel_matches from public, anon, authenticated;
revoke all on table public.duel_runs from public, anon, authenticated;
grant select, insert, update, delete on table public.duel_matches to service_role;
grant select, insert, update, delete on table public.duel_runs to service_role;

alter table public.social_notifications
  drop constraint if exists social_notifications_action_type_check;
alter table public.social_notifications
  add constraint social_notifications_action_type_check
  check (action_type in ('poke', 'boast', 'gift', 'duel_room_invite',
    'duel_room_joined', 'duel_result'));

create or replace function public.duel_room_snapshot(
  target_duel_id uuid,
  viewer_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
stable
as $function$
declare
  match_row public.duel_matches;
  viewer_run public.duel_runs;
begin
  select * into match_row
  from public.duel_matches
  where id = target_duel_id
    and viewer_id in (requester_id, opponent_id);
  if match_row.id is null then raise exception 'duel not found'; end if;

  select * into viewer_run
  from public.duel_runs
  where duel_id = target_duel_id and user_id = viewer_id;

  return jsonb_build_object(
    'id', match_row.id,
    'requester_id', match_row.requester_id,
    'opponent_id', match_row.opponent_id,
    'game_id', match_row.game_id,
    'game_version', match_row.game_version,
    'stake', match_row.stake,
    'total_pot', match_row.stake * 2,
    'runtime_revision', match_row.runtime_revision,
    'status', match_row.status,
    'outcome', match_row.outcome,
    'winner_id', match_row.winner_id,
    'room_revision', match_row.room_revision,
    'waiting_expires_at', match_row.waiting_expires_at,
    'start_at', match_row.start_at,
    'submit_deadline', match_row.submit_deadline,
    'charged', match_row.charged,
    'created_at', match_row.created_at,
    'settled_at', match_row.settled_at,
    'viewer_session_token', viewer_run.session_token,
    'viewer_run_id', viewer_run.id,
    'viewer_run_status', viewer_run.run_status,
    'viewer_joined', viewer_run.joined_at is not null,
    'viewer_loading_complete', viewer_run.loading_complete,
    'viewer_ready', viewer_run.ready,
    'viewer_run_token', case
      when match_row.status in ('starting', 'playing', 'settled')
        then viewer_run.run_token else null end,
    'seed', case
      when match_row.status in ('starting', 'playing', 'settled')
        then match_row.seed else null end,
    'runs', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'user_id', run.user_id,
        'role', run.role,
        'joined', run.joined_at is not null,
        'loading_complete', run.loading_complete,
        'ready', run.ready,
        'run_status', run.run_status,
        'started_at', run.started_at,
        'submit_deadline', run.submit_deadline,
        'raw_score', case
          when match_row.status = 'settled' or run.user_id = viewer_id
            then run.raw_score else null end,
        'result_kind', case
          when match_row.status = 'settled' or run.user_id = viewer_id
            then run.result_kind else null end,
        'result_type', case
          when match_row.status = 'settled' or run.user_id = viewer_id
            then run.result_kind else null end
      ) order by run.role), '[]'::jsonb)
      from public.duel_runs run where run.duel_id = target_duel_id
    )
  );
end;
$function$;

create or replace function public.get_duel_options()
returns jsonb
language sql
security definer set search_path = ''
stable
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', versioned.game_id,
    'game_id', versioned.game_id,
    'game_version', versioned.version,
    'display_name', versioned.display_name,
    'duration_seconds', versioned.duration_seconds,
    'runtime_revision', versioned.game_id || ':v' || versioned.version || ':duel-v1'
  ) order by versioned.display_name, versioned.game_id), '[]'::jsonb)
  from public.game_rule_versions versioned
  join public.games game on game.id = versioned.game_id
  where game.is_active and game.duel_enabled
    and game.version = versioned.version
    and versioned.game_id not in ('wind_darts', 'western_duel');
$function$;

create or replace function public.get_duel(target_duel_id uuid)
returns jsonb
language plpgsql
security definer set search_path = ''
stable
as $function$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  return public.duel_room_snapshot(target_duel_id, auth.uid());
end;
$function$;

create or replace function public.get_duels(result_limit integer default 50)
returns jsonb
language plpgsql
security definer set search_path = ''
stable
as $function$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  return (
    select coalesce(jsonb_agg(public.duel_room_snapshot(id, current_user_id)
      order by created_at desc), '[]'::jsonb)
    from (
      select room.id, room.created_at
      from public.duel_matches room
      where current_user_id in (room.requester_id, room.opponent_id)
      order by room.created_at desc
      limit greatest(1, least(coalesce(result_limit, 50), 100))
    ) match
  );
end;
$function$;

create or replace function public.create_duel(
  target_user_id uuid,
  target_game_id text,
  target_game_version integer,
  target_stake bigint,
  target_request_id uuid,
  client_runtime_revision text default null
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare
  current_user_id uuid := auth.uid();
  target_game public.game_rule_versions;
  sender_profile public.profiles;
  target_profile public.profiles;
  existing public.duel_matches;
  created public.duel_matches;
  runtime text := coalesce(nullif(btrim(client_runtime_revision), ''),
    target_game_id || ':v' || target_game_version || ':duel-v1');
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if target_user_id is null or target_user_id = current_user_id
    then raise exception 'invalid opponent'; end if;
  if target_request_id is null then raise exception 'client request id required'; end if;
  if target_stake < 10 or target_stake % 10 <> 0 or target_stake > 200
    then raise exception 'stake must be a 10 coin amount between 10 and 200'; end if;
  if target_game_id in ('wind_darts', 'western_duel')
    then raise exception 'game is not available for duels'; end if;
  perform pg_advisory_xact_lock(
    hashtext(least(current_user_id::text, target_user_id::text)),
    hashtext(greatest(current_user_id::text, target_user_id::text) || ':duel')
  );
  select * into existing from public.duel_matches
  where requester_id = current_user_id
    and client_request_id = target_request_id;
  if existing.id is not null then
    return public.duel_room_snapshot(existing.id, current_user_id);
  end if;
  select * into sender_profile from public.profiles
  where id = current_user_id for update;
  select * into target_profile from public.profiles
  where id = target_user_id for update;
  if sender_profile.id is null or target_profile.id is null
    then raise exception 'opponent unavailable'; end if;
  if (coalesce(sender_profile.is_test_account, false)
    or coalesce(target_profile.is_test_account, false))
    and not (
      coalesce(sender_profile.is_test_account, false)
      and coalesce(target_profile.is_test_account, false)
      and exists (
        select 1 from public.app_runtime_config config
        where config.id and config.local_duel_test_enabled
      )
    )
    then raise exception 'duels unavailable for test accounts'; end if;
  if exists (
    select 1 from public.duel_matches room
    where room.status in ('waiting', 'starting', 'playing')
      and (room.requester_id = current_user_id
        or room.opponent_id = current_user_id
        or room.requester_id = target_user_id
        or room.opponent_id = target_user_id)
  ) then raise exception 'participant already has an open duel'; end if;
  select * into target_game from public.game_rule_versions versioned
  where versioned.game_id = target_game_id
    and versioned.version = target_game_version;
  if target_game.game_id is null or not exists (
    select 1 from public.games game
    where game.id = target_game_id
      and game.version = target_game_version
      and game.is_active and game.duel_enabled
  ) then raise exception 'game version unavailable'; end if;
  insert into public.duel_matches (
    requester_id, opponent_id, game_id, game_version, stake,
    runtime_revision, game_duration_seconds, client_request_id
  ) values (
    current_user_id, target_user_id, target_game_id, target_game_version,
    target_stake, runtime, target_game.duration_seconds, target_request_id
  ) returning * into created;
  insert into public.duel_runs (
    duel_id, user_id, role, joined_at, client_runtime_revision,
    presence_expires_at
  ) values (
    created.id, current_user_id, 'requester', now(), runtime,
    now() + interval '15 seconds'
  );
  insert into public.duel_runs (duel_id, user_id, role)
  values (created.id, target_user_id, 'opponent');
  insert into public.social_notifications(
    sender_id, recipient_id, action_type, request_id
  ) values (current_user_id, target_user_id, 'duel_room_invite', created.id)
  on conflict (sender_id, request_id) do nothing;
  insert into public.push_notification_outbox(
    notification_id, recipient_id, title, body, payload
  )
  select notification.id, notification.recipient_id, '딱한판만',
    coalesce(sender.nickname, '상대') || '님이 1:1 대결방을 만들었어요.',
    jsonb_build_object(
      'schema_version', '1',
      'notification_id', notification.id,
      'action_type', 'duel_room_invite',
      'destination', 'duel_room',
      'duel_id', created.id
    )
  from public.social_notifications notification
  join public.profiles sender on sender.id = notification.sender_id
  join public.profiles recipient on recipient.id = notification.recipient_id
  where notification.sender_id = current_user_id
    and notification.request_id = created.id
    and recipient.social_notifications_enabled
  on conflict (notification_id) do nothing;
  return public.duel_room_snapshot(created.id, current_user_id);
end;
$function$;

create or replace function public.join_duel(
  target_duel_id uuid,
  device_session_id uuid default null,
  client_runtime_revision text default null
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare
  current_user_id uuid := auth.uid();
  match_row public.duel_matches;
  run_row public.duel_runs;
  token uuid := coalesce(device_session_id, gen_random_uuid());
  runtime text;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select * into match_row from public.duel_matches
  where id = target_duel_id for update;
  if match_row.id is null or current_user_id not in
    (match_row.requester_id, match_row.opponent_id)
    then raise exception 'duel not found'; end if;
  if match_row.status <> 'waiting'
    then return public.duel_room_snapshot(target_duel_id, current_user_id); end if;
  if match_row.waiting_expires_at <= now() then
    update public.duel_matches set status = 'expired',
      room_revision = room_revision + 1 where id = target_duel_id;
    return public.duel_room_snapshot(target_duel_id, current_user_id);
  end if;
  select * into run_row from public.duel_runs
  where duel_id = target_duel_id and user_id = current_user_id for update;
  runtime := coalesce(nullif(btrim(client_runtime_revision), ''),
    match_row.runtime_revision);
  if run_row.joined_at is not null and device_session_id is not null
    and run_row.session_token <> device_session_id then
    update public.duel_runs set session_generation = session_generation + 1,
      session_token = token, presence_expires_at = now() + interval '15 seconds',
      ready = false, loading_complete = false, client_runtime_revision = runtime
    where id = run_row.id;
  else
    update public.duel_runs set joined_at = coalesce(joined_at, now()),
      session_token = token, presence_expires_at = now() + interval '15 seconds',
      client_runtime_revision = runtime where id = run_row.id;
  end if;
  update public.duel_matches set accepted_at = coalesce(accepted_at, now())
  where id = target_duel_id and accepted_at is null;
  return public.duel_room_snapshot(target_duel_id, current_user_id);
end;
$function$;
create or replace function public.heartbeat_duel(
  target_duel_id uuid,
  device_session_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  update public.duel_runs set presence_expires_at = now() + interval '15 seconds'
  where duel_id = target_duel_id and user_id = current_user_id
    and session_token = device_session_id;
  if not found then raise exception 'stale duel session'; end if;
  return public.duel_room_snapshot(target_duel_id, current_user_id);
end;
$function$;

create or replace function public.set_duel_ready(
  target_duel_id uuid,
  desired_ready boolean,
  is_loading_complete boolean,
  device_session_id uuid,
  client_runtime_revision text default null
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare
  current_user_id uuid := auth.uid();
  match_row public.duel_matches;
  own_run public.duel_runs;
  other_run public.duel_runs;
  own_profile public.profiles;
  other_profile public.profiles;
  runtime text;
  start_time timestamptz;
  deadline timestamptz;
  seed_value bigint;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select * into match_row from public.duel_matches
  where id = target_duel_id for update;
  if match_row.id is null or current_user_id not in
    (match_row.requester_id, match_row.opponent_id)
    then raise exception 'duel not found'; end if;
  if match_row.status <> 'waiting'
    then return public.duel_room_snapshot(target_duel_id, current_user_id); end if;
  select * into own_run from public.duel_runs
  where duel_id = target_duel_id and user_id = current_user_id for update;
  if own_run.id is null or own_run.joined_at is null
    or own_run.session_token <> device_session_id
    then raise exception 'join this duel on the current device first'; end if;
  if desired_ready and (not is_loading_complete
    or own_run.presence_expires_at <= now())
    then raise exception 'game is still loading or the room session expired'; end if;

  runtime := coalesce(nullif(btrim(client_runtime_revision), ''),
    own_run.client_runtime_revision, match_row.runtime_revision);
  update public.duel_runs set
    loading_complete = case when desired_ready
      then is_loading_complete else loading_complete end,
    ready = desired_ready, client_runtime_revision = runtime,
    presence_expires_at = now() + interval '15 seconds'
  where id = own_run.id;

  if not desired_ready then
    update public.duel_matches set room_revision = room_revision + 1
    where id = target_duel_id;
    return public.duel_room_snapshot(target_duel_id, current_user_id);
  end if;

  select * into other_run from public.duel_runs
  where duel_id = target_duel_id and user_id <> current_user_id for update;
  if other_run.id is null or not other_run.ready then
    update public.duel_matches set room_revision = room_revision + 1
    where id = target_duel_id;
    return public.duel_room_snapshot(target_duel_id, current_user_id);
  end if;
  if other_run.joined_at is null or not other_run.loading_complete
    or other_run.presence_expires_at <= now()
    or other_run.client_runtime_revision is distinct from runtime then
    update public.duel_runs set ready = false where id in (own_run.id, other_run.id);
    update public.duel_matches set room_revision = room_revision + 1
    where id = target_duel_id;
    return public.duel_room_snapshot(target_duel_id, current_user_id)
      || jsonb_build_object(
        'start_failed', true, 'start_failure_reason', 'opponent_not_ready'
      );
  end if;

  -- Profiles are locked in a deterministic order before changing either
  -- balance. apply_coin_transaction repeats the same row lock safely.
  select * into own_profile from public.profiles
  where id in (match_row.requester_id, match_row.opponent_id)
  order by id limit 1 for update;
  select * into other_profile from public.profiles
  where id in (match_row.requester_id, match_row.opponent_id)
  order by id desc limit 1 for update;
  if own_profile.coin_balance < match_row.stake
    or other_profile.coin_balance < match_row.stake
    or own_profile.coin_balance + match_row.stake > 1000000000
    or other_profile.coin_balance + match_row.stake > 1000000000 then
    update public.duel_runs set ready = false where id in (own_run.id, other_run.id);
    update public.duel_matches set room_revision = room_revision + 1
    where id = target_duel_id;
    return public.duel_room_snapshot(target_duel_id, current_user_id)
      || jsonb_build_object(
        'start_failed', true,
        'start_failure_reason', 'insufficient_coin_balance'
      );
  end if;

  start_time := now() + interval '3 seconds';
  deadline := start_time + make_interval(
    secs => match_row.game_duration_seconds
      + match_row.result_reveal_allowance_seconds + 120
  );
  seed_value := hashtextextended(
    target_duel_id::text || clock_timestamp()::text, 0
  );
  perform public.apply_coin_transaction(
    match_row.requester_id, -match_row.stake, 0, 'duel_escrow',
    'duel:' || target_duel_id::text || ':stake:' || match_row.requester_id::text,
    match_row.game_id, null, jsonb_build_object('duel_id', target_duel_id)
  );
  perform public.apply_coin_transaction(
    match_row.opponent_id, -match_row.stake, 0, 'duel_escrow',
    'duel:' || target_duel_id::text || ':stake:' || match_row.opponent_id::text,
    match_row.game_id, null, jsonb_build_object('duel_id', target_duel_id)
  );
  update public.duel_matches set status = 'starting', charged = true,
    room_revision = room_revision + 1, seed = seed_value, start_at = start_time,
    submit_deadline = deadline, accepted_at = coalesce(accepted_at, now())
  where id = target_duel_id;
  update public.duel_runs set run_token = gen_random_uuid(),
    run_status = 'starting', started_at = start_time,
    submit_deadline = deadline, ready = true
  where duel_id = target_duel_id;
  return public.duel_room_snapshot(target_duel_id, current_user_id)
    || jsonb_build_object('started', true);
end;
$function$;

create or replace function public.leave_duel(
  target_duel_id uuid,
  device_session_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare current_user_id uuid := auth.uid();
  match_row public.duel_matches;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select * into match_row from public.duel_matches
  where id = target_duel_id for update;
  if match_row.id is null or current_user_id not in
    (match_row.requester_id, match_row.opponent_id)
    then raise exception 'duel not found'; end if;
  if not exists (
    select 1 from public.duel_runs
    where duel_id = target_duel_id and user_id = current_user_id
      and session_token = device_session_id
  ) then raise exception 'stale duel session'; end if;
  if match_row.status = 'waiting' then
    update public.duel_matches set status = 'cancelled',
      room_revision = room_revision + 1 where id = target_duel_id;
  end if;
  return public.duel_room_snapshot(target_duel_id, current_user_id);
end;
$function$;
create or replace function public.settle_duel(target_duel_id uuid)
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare
  match_row public.duel_matches;
  first_run public.duel_runs;
  second_run public.duel_runs;
  winner uuid;
  outcome_value text;
  first_valid boolean;
  second_valid boolean;
begin
  select * into match_row from public.duel_matches
  where id = target_duel_id for update;
  if match_row.id is null then raise exception 'duel not found'; end if;
  if match_row.status in ('settled', 'cancelled', 'expired', 'voided', 'declined')
    then return jsonb_build_object('status', match_row.status); end if;
  select * into first_run from public.duel_runs
  where duel_id = target_duel_id
  order by case when role = 'requester' then 0 else 1 end
  limit 1 for update;
  select * into second_run from public.duel_runs
  where duel_id = target_duel_id
  order by case when role = 'requester' then 0 else 1 end desc
  limit 1 for update;
  if first_run.run_status not in ('submitted', 'forfeited', 'no_result')
    or second_run.run_status not in ('submitted', 'forfeited', 'no_result') then
    return public.duel_room_snapshot(target_duel_id, coalesce(auth.uid(), match_row.requester_id));
  end if;

  first_valid := first_run.run_status = 'submitted' and first_run.result_kind = 'valid';
  second_valid := second_run.run_status = 'submitted' and second_run.result_kind = 'valid';
  if first_valid and second_valid and first_run.raw_score = second_run.raw_score then
    outcome_value := 'tie';
  elsif first_valid and (not second_valid or first_run.raw_score > second_run.raw_score) then
    winner := first_run.user_id; outcome_value := 'requester_win';
  elsif second_valid then
    winner := second_run.user_id; outcome_value := 'opponent_win';
  else
    outcome_value := 'refund';
  end if;

  if outcome_value in ('tie', 'refund') then
    insert into public.duel_payouts(duel_id, user_id, payout_kind, amount)
    values
      (target_duel_id, first_run.user_id, 'refund', match_row.stake),
      (target_duel_id, second_run.user_id, 'refund', match_row.stake)
    on conflict (duel_id, user_id, payout_kind) do nothing;
    perform public.credit_duel_payout(target_duel_id, first_run.user_id, 'refund');
    perform public.credit_duel_payout(target_duel_id, second_run.user_id, 'refund');
  else
    insert into public.duel_payouts(duel_id, user_id, payout_kind, amount)
    values (target_duel_id, winner, 'payout', match_row.stake * 2)
    on conflict (duel_id, user_id, payout_kind) do nothing;
    perform public.credit_duel_payout(target_duel_id, winner, 'payout');
  end if;
  update public.duel_matches set status = 'settled', outcome = outcome_value,
    winner_id = winner, settled_at = now(), room_revision = room_revision + 1
  where id = target_duel_id;
  return public.duel_room_snapshot(target_duel_id, coalesce(auth.uid(), match_row.requester_id));
end;
$function$;

create or replace function public.submit_duel_result(
  target_duel_id uuid,
  target_run_id uuid,
  target_run_token uuid,
  submitted_score bigint,
  submitted_duration_ms integer,
  target_result_kind text default 'valid',
  client_request_id uuid default null
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare
  current_user_id uuid := auth.uid();
  match_row public.duel_matches;
  run_row public.duel_runs;
  elapsed_ms bigint;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if target_result_kind not in ('valid', 'no_result')
    then raise exception 'invalid result kind'; end if;
  select * into match_row from public.duel_matches
  where id = target_duel_id for update;
  select * into run_row from public.duel_runs
  where id = target_run_id and duel_id = target_duel_id
    and user_id = current_user_id for update;
  if run_row.id is null or run_row.run_token <> target_run_token
    then raise exception 'invalid duel run'; end if;
  if match_row.status not in ('starting', 'playing')
    then return public.duel_room_snapshot(target_duel_id, current_user_id); end if;
  if run_row.run_status in ('submitted', 'forfeited', 'no_result')
    then return public.duel_room_snapshot(target_duel_id, current_user_id); end if;
  if match_row.start_at is null or now() < match_row.start_at
    then raise exception 'duel has not started'; end if;
  if match_row.submit_deadline <= now()
    then raise exception 'duel result deadline passed'; end if;
  if submitted_score is null or submitted_score < 0
    then raise exception 'score is invalid'; end if;
  if submitted_duration_ms is null or submitted_duration_ms < 0
    or submitted_duration_ms > (match_row.game_duration_seconds + 120) * 1000
    then raise exception 'duration is invalid'; end if;
  elapsed_ms := greatest(
    0,
    floor(extract(epoch from (now() - match_row.start_at)) * 1000)::bigint
  );
  if submitted_duration_ms::bigint > elapsed_ms
    + (match_row.result_reveal_allowance_seconds * 1000) then
    raise exception 'duel duration exceeds server elapsed time';
  end if;
  perform public.validate_duel_score(
    match_row.game_id, match_row.game_version,
    match_row.game_duration_seconds, submitted_score,
    submitted_duration_ms, target_result_kind
  );

  update public.duel_runs set
    run_status = case when target_result_kind = 'valid'
      then 'submitted' else 'no_result' end,
    raw_score = submitted_score, duration_ms = submitted_duration_ms,
    result_kind = target_result_kind, submitted_at = now(),
    terminal_reason = 'submitted'
  where id = target_run_id;
  update public.duel_matches set status = 'playing',
    room_revision = room_revision + 1
  where id = target_duel_id and status = 'starting';
  return public.settle_duel(target_duel_id);
end;
$function$;

create or replace function public.forfeit_duel(
  target_duel_id uuid,
  target_run_id uuid,
  target_run_token uuid,
  reason text default 'client_interrupted'
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare
  current_user_id uuid := auth.uid();
  match_row public.duel_matches;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select * into match_row from public.duel_matches
  where id = target_duel_id for update;
  if match_row.id is null or current_user_id not in
    (match_row.requester_id, match_row.opponent_id)
    then raise exception 'duel not found'; end if;
  if match_row.status not in ('starting', 'playing') then
    return public.duel_room_snapshot(target_duel_id, current_user_id);
  end if;
  update public.duel_runs set run_status = 'forfeited',
    result_kind = 'forfeit',
    terminal_reason = left(coalesce(reason, 'client_interrupted'), 160),
    submitted_at = now()
  where id = target_run_id and duel_id = target_duel_id
    and user_id = current_user_id and run_token = target_run_token
    and run_status not in ('submitted', 'forfeited', 'no_result');
  if not found then raise exception 'invalid duel run'; end if;
  return public.settle_duel(target_duel_id);
end;
$function$;

create or replace function public.expire_duel_rooms()
returns integer
language plpgsql
security definer set search_path = ''
as $function$
declare
  expired_count integer := 0;
  room_row public.duel_matches;
begin
  for room_row in
    select * from public.duel_matches
    where status = 'waiting' and waiting_expires_at <= now()
    for update skip locked
  loop
    update public.duel_matches set status = 'expired',
      room_revision = room_revision + 1
    where id = room_row.id and status = 'waiting';
    expired_count := expired_count + 1;
  end loop;
  return expired_count;
end;
$function$;

revoke all on function public.duel_room_snapshot(uuid, uuid),
  public.get_duel_options(), public.get_duel(uuid), public.get_duels(integer),
  public.create_duel(uuid,text,integer,bigint,uuid,text),
  public.join_duel(uuid,uuid,text), public.heartbeat_duel(uuid,uuid),
  public.set_duel_ready(uuid,boolean,boolean,uuid,text),
  public.leave_duel(uuid,uuid), public.settle_duel(uuid),
  public.submit_duel_result(uuid,uuid,uuid,bigint,integer,text,uuid),
  public.forfeit_duel(uuid,uuid,uuid,text), public.expire_duel_rooms()
  from public, anon;

grant execute on function public.get_duel_options(), public.get_duel(uuid),
  public.get_duels(integer), public.create_duel(uuid,text,integer,bigint,uuid,text),
  public.join_duel(uuid,uuid,text), public.heartbeat_duel(uuid,uuid),
  public.set_duel_ready(uuid,boolean,boolean,uuid,text),
  public.leave_duel(uuid,uuid),
  public.submit_duel_result(uuid,uuid,uuid,bigint,integer,text,uuid),
  public.forfeit_duel(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.expire_duel_rooms() to service_role;



create or replace function public.expire_duel_runs()
returns integer
language plpgsql
security definer set search_path = ''
as $function$
declare
  marked_count integer := 0;
  room_row public.duel_matches;
  changed_count integer;
begin
  -- Match-first locking mirrors submit_duel_result and settle_duel. It keeps
  -- deadline expiry from holding a run row while a result submission holds
  -- the parent match row.
  for room_row in
    select *
    from public.duel_matches
    where status in ('starting', 'playing')
      and submit_deadline <= now()
    for update skip locked
  loop
    update public.duel_runs set run_status = 'no_result',
      result_kind = 'no_result', terminal_reason = 'submit_deadline',
      submitted_at = now()
    where duel_id = room_row.id
      and run_status in ('starting', 'playing');
    get diagnostics changed_count = row_count;
    marked_count := marked_count + changed_count;
    if changed_count > 0 then
      perform public.settle_duel(room_row.id);
    end if;
  end loop;
  return marked_count;
end;
$function$;

revoke all on function public.expire_duel_runs() from public, anon;
grant execute on function public.expire_duel_runs() to service_role;



create or replace function public.duel_score_upper_bound(
  target_game_id text,
  target_game_version integer,
  target_duration_seconds integer
)
returns bigint
language sql
immutable
security definer set search_path = ''
as $function$
  select case target_game_id
    when 'dung_dodge_v2' then greatest(target_duration_seconds, 1)::bigint * 1000
    when 'gravity_switch' then greatest(target_duration_seconds, 1)::bigint * 1000
    when 'apple_game_v2' then 1000
    when 'number_rush' then 3600000
    when 'mole_reaction' then 1000000
    when 'mama_duck_trail' then 10000
    when 'midnight_snake' then 149
    when 'beat_the_dealer' then 925
    when 'ten_pitch_slugger' then 16875
    when 'ramen_timer' then 3600000
    when 'bathhouse_sort' then 10000
    when 'lily_frog' then 10000
    when 'net_boat' then 10000
    when 'temple_run' then 1000000
    else null
  end;
$function$;

create or replace function public.validate_duel_score(
  target_game_id text,
  target_game_version integer,
  target_duration_seconds integer,
  submitted_score bigint,
  submitted_duration_ms integer,
  target_result_kind text
)
returns void
language plpgsql
security definer set search_path = ''
as $function$
declare upper_bound bigint;
begin
  if target_result_kind = 'no_result' then
    if submitted_score <> 0 then raise exception 'no-result score must be zero'; end if;
    return;
  end if;
  upper_bound := public.duel_score_upper_bound(
    target_game_id, target_game_version, target_duration_seconds
  );
  if upper_bound is null then
    raise exception 'game has no duel validator';
  end if;
  if submitted_score is null or submitted_score < 0 or submitted_score > upper_bound then
    raise exception 'duel score is outside the game contract';
  end if;
  if submitted_duration_ms is null or submitted_duration_ms < 0
    or submitted_duration_ms > (target_duration_seconds + 120) * 1000 then
    raise exception 'duel duration is outside the game contract';
  end if;
end;
$function$;

revoke all on function public.duel_score_upper_bound(text, integer, integer),
  public.validate_duel_score(text, integer, integer, bigint, integer, text)
  from public, anon, authenticated;



create table public.duel_payouts (
  id uuid primary key default gen_random_uuid(),
  duel_id uuid not null references public.duel_matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  payout_kind text not null check (payout_kind in ('refund', 'payout')),
  amount bigint not null check (amount > 0),
  credited_amount bigint not null default 0 check (
    credited_amount >= 0 and credited_amount <= amount
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (duel_id, user_id, payout_kind)
);

alter table public.duel_payouts enable row level security;
revoke all on table public.duel_payouts from public, anon, authenticated;
grant select, insert, update, delete on table public.duel_payouts to service_role;

create or replace function public.credit_duel_payout(
  target_duel_id uuid,
  target_user_id uuid,
  target_payout_kind text
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare
  payout public.duel_payouts;
  profile_row public.profiles;
  available bigint;
  delta bigint;
begin
  select * into payout from public.duel_payouts
  where duel_id = target_duel_id and user_id = target_user_id
    and payout_kind = target_payout_kind for update;
  if payout.id is null then return jsonb_build_object('credited', 0); end if;
  select * into profile_row from public.profiles
  where id = target_user_id for update;
  available := greatest(0, 1000000000 - profile_row.coin_balance);
  delta := least(available, payout.amount - payout.credited_amount);
  if delta > 0 then
    perform public.apply_coin_transaction(
      target_user_id, delta, 0,
      case when target_payout_kind = 'refund'
        then 'duel_refund' else 'duel_payout' end,
      'duel:' || target_duel_id::text || ':' || target_payout_kind || ':'
        || target_user_id::text || ':' || (payout.credited_amount + delta)::text,
      null, null, jsonb_build_object('duel_id', target_duel_id)
    );
    update public.duel_payouts set credited_amount = credited_amount + delta,
      updated_at = now() where id = payout.id returning * into payout;
  end if;
  return jsonb_build_object(
    'amount', payout.amount,
    'credited_amount', payout.credited_amount,
    'owed_amount', payout.amount - payout.credited_amount
  );
end;
$function$;

create or replace function public.claim_duel_payouts()
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare
  current_user_id uuid := auth.uid();
  payout public.duel_payouts;
  result jsonb := '[]'::jsonb;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  for payout in
    select * from public.duel_payouts
    where user_id = current_user_id and credited_amount < amount
    order by created_at for update
  loop
    result := result || jsonb_build_array(public.credit_duel_payout(
      payout.duel_id, current_user_id, payout.payout_kind
    ));
  end loop;
  return result;
end;
$function$;

revoke all on function public.credit_duel_payout(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.claim_duel_payouts() from public, anon;
grant execute on function public.claim_duel_payouts() to authenticated;



create or replace function public.void_duels_for_account(target_user_id uuid)
returns integer
language plpgsql
security definer set search_path = ''
as $function$
declare
  room public.duel_matches;
  changed integer := 0;
begin
  if target_user_id is null then raise exception 'account is required'; end if;
  for room in
    select room_row.*
    from public.duel_matches room_row
    where target_user_id in (room_row.requester_id, room_row.opponent_id)
      and room_row.status in ('waiting', 'starting', 'playing')
    order by room_row.created_at
    for update
  loop
    if room.charged then
      update public.duel_runs set run_status = 'no_result',
        result_kind = 'no_result',
        terminal_reason = 'account_deletion',
        raw_score = 0,
        duration_ms = null,
        submitted_at = coalesce(submitted_at, now())
      where duel_id = room.id;
      -- Reusing settlement after forcing both runs to no-result guarantees a
      -- refund for both players, even if one player had already submitted a
      -- valid score before account deletion began.
      perform public.settle_duel(room.id);
      if exists (
        select 1 from public.duel_payouts payout
        where payout.duel_id = room.id
          and payout.credited_amount < payout.amount
      ) then
        raise exception 'duel payout is still pending';
      end if;
      update public.duel_matches set status = 'voided', outcome = 'void',
        winner_id = null, room_revision = room_revision + 1
      where id = room.id;
    else
      update public.duel_matches set status = 'cancelled',
        outcome = 'refund', room_revision = room_revision + 1
      where id = room.id;
    end if;
    changed := changed + 1;
  end loop;
  return changed;
end;
$function$;

create or replace function public.maintain_duels()
returns jsonb
language plpgsql
security definer set search_path = ''
as $function$
declare
  original_subject text := current_setting('request.jwt.claim.sub', true);
  profile_row record;
  expired_rooms integer := public.expire_duel_rooms();
  expired_runs integer := public.expire_duel_runs();
  payout_batches integer := 0;
begin
  for profile_row in
    select profile.id
    from public.profiles profile
    where not coalesce(profile.is_test_account, false)
  loop
    perform set_config('request.jwt.claim.sub', profile_row.id::text, true);
    perform public.claim_duel_payouts();
    payout_batches := payout_batches + 1;
  end loop;
  perform set_config('request.jwt.claim.sub', coalesce(original_subject, ''), true);
  return jsonb_build_object(
    'expired_rooms', expired_rooms,
    'expired_runs', expired_runs,
    'payout_batches', payout_batches
  );
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(original_subject, ''), true);
  raise;
end;
$function$;

revoke all on function public.void_duels_for_account(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.maintain_duels()
  from public, anon, authenticated, service_role;
grant execute on function public.void_duels_for_account(uuid)
  to service_role;
grant execute on function public.maintain_duels()
  to service_role;

-- Run the same maintenance function from pg_cron when the deployment permits
-- the extension. App reads and the account-deletion worker remain recovery
-- paths if cron is unavailable or delayed.
do $migration$
declare
  existing_job record;
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    null;
  end;
  if to_regnamespace('cron') is null then
    return;
  end if;
  for existing_job in
    execute 'select jobid from cron.job where jobname = $1'
    using 'just-one-round-maintain-duels'
  loop
    execute 'select cron.unschedule($1)' using existing_job.jobid;
  end loop;
  execute 'select cron.schedule($1, $2, $3)'
  using
    'just-one-round-maintain-duels',
    '* * * * *',
    'select public.maintain_duels();';
exception when others then
  null;
end;
$migration$;

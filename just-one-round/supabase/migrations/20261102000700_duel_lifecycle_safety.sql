-- Prevent account deletion from racing new rooms or destroying another
-- participant's outstanding payout. The guard disappears with the account.
create table public.duel_account_deletions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.duel_account_deletions enable row level security;
revoke all on public.duel_account_deletions from public, anon, authenticated;

create function public.guard_duel_account_deletion()
returns trigger language plpgsql security definer set search_path = '' as $function$
begin
  if exists (select 1 from public.duel_account_deletions d
      where d.user_id in (new.requester_id, new.opponent_id)) then
    raise exception 'duel participant account is being deleted';
  end if;
  return new;
end;
$function$;
revoke all on function public.guard_duel_account_deletion() from public, anon, authenticated;
create trigger guard_duel_account_deletion
  before insert or update of status on public.duel_matches
  for each row when (new.status in ('waiting', 'starting', 'playing'))
  execute function public.guard_duel_account_deletion();

alter function public.void_duels_for_account(uuid) rename to void_duels_for_account_unchecked;
revoke all on function public.void_duels_for_account_unchecked(uuid) from public, anon, authenticated, service_role;
create function public.void_duels_for_account(target_user_id uuid)
returns integer language plpgsql security definer set search_path = '' as $function$
declare changed integer;
begin
  if target_user_id is null then raise exception 'account is required'; end if;
  -- create_duel locks both profiles before inserting; its insert trigger then
  -- observes this guard after any competing transaction has completed.
  perform 1 from public.profiles where id = target_user_id for update;
  if not found then raise exception 'account is unavailable'; end if;
  insert into public.duel_account_deletions(user_id) values (target_user_id)
    on conflict (user_id) do nothing;
  if exists (
    select 1 from public.duel_payouts p
    join public.duel_matches m on m.id = p.duel_id
    where target_user_id in (m.requester_id, m.opponent_id)
      and p.user_id <> target_user_id and p.credited_amount < p.amount
  ) then raise exception 'another participant has a pending duel payout'; end if;
  changed := public.void_duels_for_account_unchecked(target_user_id);
  if exists (
    select 1 from public.duel_payouts p
    join public.duel_matches m on m.id = p.duel_id
    where target_user_id in (m.requester_id, m.opponent_id)
      and p.user_id <> target_user_id and p.credited_amount < p.amount
  ) then raise exception 'another participant has a pending duel payout'; end if;
  return changed;
end;
$function$;
revoke all on function public.void_duels_for_account(uuid) from public, anon, authenticated;
grant execute on function public.void_duels_for_account(uuid) to service_role;

-- Recheck mutable room, game and account policy under the same match lock as
-- the READY transition; neither a stale client nor a delayed cron can start it.
create or replace function public.set_duel_ready(
  target_duel_id uuid, desired_ready boolean, is_loading_complete boolean,
  device_session_id uuid, client_runtime_revision text default null
) returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  viewer uuid := auth.uid();
  room public.duel_matches;
  own_run public.duel_runs;
  other_run public.duel_runs;
  tests_allowed boolean;
  first_test boolean;
  second_test boolean;
begin
  if viewer is null then raise exception 'authentication required'; end if;
  select * into room from public.duel_matches where id = target_duel_id for update;
  if room.id is null or viewer not in (room.requester_id, room.opponent_id) then
    raise exception 'duel not found';
  end if;
  if room.status = 'waiting' and desired_ready then
    if room.waiting_expires_at <= now() then
      update public.duel_matches set status = 'expired', room_revision = room_revision + 1 where id = room.id;
      return public.duel_room_snapshot(room.id, viewer) || jsonb_build_object('start_failed', true, 'start_failure_reason', 'room_expired');
    end if;
    if not exists (select 1 from public.games g where g.id = room.game_id and g.version = room.game_version and g.is_active and g.duel_enabled) then
      update public.duel_runs set ready = false where duel_id = room.id;
      return public.duel_room_snapshot(room.id, viewer) || jsonb_build_object('start_failed', true, 'start_failure_reason', 'game_unavailable');
    end if;
    select coalesce(p.is_test_account,false) into first_test from public.profiles p where p.id = room.requester_id;
    select coalesce(p.is_test_account,false) into second_test from public.profiles p where p.id = room.opponent_id;
    select coalesce(c.local_duel_test_enabled,false) into tests_allowed from public.app_runtime_config c where c.id;
    if first_test is null or second_test is null or ((first_test or second_test) and not (first_test and second_test and coalesce(tests_allowed,false))) then
      update public.duel_runs set ready = false where duel_id = room.id;
      return public.duel_room_snapshot(room.id, viewer) || jsonb_build_object('start_failed', true, 'start_failure_reason', 'opponent_unavailable');
    end if;
    select * into own_run from public.duel_runs where duel_id = room.id and user_id = viewer for update;
    select * into other_run from public.duel_runs where duel_id = room.id and user_id <> viewer for update;
    if own_run.id is null or own_run.joined_at is null or own_run.session_token is distinct from device_session_id then
      raise exception 'join this duel on the current device first';
    end if;
    if not is_loading_complete or own_run.presence_expires_at is null or own_run.presence_expires_at <= now() then
      raise exception 'game is still loading or the room session expired';
    end if;
    if other_run.id is null or other_run.joined_at is null or other_run.presence_expires_at is null or other_run.presence_expires_at <= now() then
      raise exception 'both players must join before ready';
    end if;
  end if;
  return public.set_duel_ready_unchecked(target_duel_id, desired_ready, is_loading_complete, device_session_id, client_runtime_revision);
end;
$function$;

-- Reads recover overdue rooms and unclaimed payouts for the viewer if the
-- scheduler is delayed. Global scheduler remains necessary for offline users.
create function public.recover_viewer_duels()
returns void language plpgsql security definer set search_path = '' as $function$
declare viewer uuid := auth.uid(); room public.duel_matches;
begin
  if viewer is null then raise exception 'authentication required'; end if;
  for room in select * from public.duel_matches m
    where viewer in (m.requester_id, m.opponent_id)
      and ((m.status = 'waiting' and m.waiting_expires_at <= now())
        or (m.status in ('starting','playing') and m.submit_deadline <= now()))
    order by m.id for update skip locked
  loop
    if room.status = 'waiting' then
      update public.duel_matches set status = 'expired', room_revision = room_revision + 1 where id = room.id;
    else
      update public.duel_runs set run_status = 'no_result', result_kind = 'no_result', terminal_reason = 'submit_deadline', submitted_at = now()
        where duel_id = room.id and run_status not in ('submitted','forfeited','no_result');
      perform public.settle_duel(room.id);
    end if;
  end loop;
  perform public.claim_duel_payouts();
end;
$function$;
revoke all on function public.recover_viewer_duels() from public, anon, authenticated;
create or replace function public.get_duel(target_duel_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not exists (select 1 from public.duel_matches m where m.id = target_duel_id and auth.uid() in (m.requester_id,m.opponent_id)) then
    raise exception 'duel not found';
  end if;
  perform public.recover_viewer_duels();
  return public.duel_room_snapshot(target_duel_id, auth.uid());
end;
$function$;
create or replace function public.get_duels(result_limit integer default 50)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare viewer uuid := auth.uid();
begin
  if viewer is null then raise exception 'authentication required'; end if;
  perform public.recover_viewer_duels();
  return (select coalesce(jsonb_agg(public.duel_room_snapshot(q.id,viewer) order by q.created_at desc),'[]'::jsonb)
    from (select m.id,m.created_at from public.duel_matches m
      where viewer in (m.requester_id,m.opponent_id) order by m.created_at desc
      limit greatest(1,least(coalesce(result_limit,50),100))) q);
end;
$function$;

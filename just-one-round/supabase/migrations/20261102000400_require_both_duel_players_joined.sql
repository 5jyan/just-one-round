-- Keep the original transition implementation private, then add a narrow
-- server gate so a player cannot become READY until the other participant has
-- joined and still holds a live room lease.
alter function public.set_duel_ready(uuid, boolean, boolean, uuid, text)
  rename to set_duel_ready_unchecked;

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
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into match_row
  from public.duel_matches
  where id = target_duel_id
  for update;
  if match_row.id is null or current_user_id not in
    (match_row.requester_id, match_row.opponent_id) then
    raise exception 'duel not found';
  end if;

  if match_row.status = 'waiting' and desired_ready then
    select * into own_run
    from public.duel_runs
    where duel_id = target_duel_id and user_id = current_user_id
    for update;
    if own_run.id is null or own_run.joined_at is null
      or own_run.session_token <> device_session_id then
      raise exception 'join this duel on the current device first';
    end if;
    if not is_loading_complete or own_run.presence_expires_at is null
      or own_run.presence_expires_at <= now() then
      raise exception 'game is still loading or the room session expired';
    end if;

    select * into other_run
    from public.duel_runs
    where duel_id = target_duel_id and user_id <> current_user_id
    for update;
    if other_run.id is null or other_run.joined_at is null
      or other_run.presence_expires_at is null
      or other_run.presence_expires_at <= now() then
      raise exception 'both players must join before ready';
    end if;
  end if;

  return public.set_duel_ready_unchecked(
    target_duel_id, desired_ready, is_loading_complete,
    device_session_id, client_runtime_revision
  );
end;
$function$;

revoke all on function public.set_duel_ready_unchecked(
  uuid, boolean, boolean, uuid, text
) from public, anon, authenticated;
revoke all on function public.set_duel_ready(
  uuid, boolean, boolean, uuid, text
) from public, anon;
grant execute on function public.set_duel_ready(
  uuid, boolean, boolean, uuid, text
) to authenticated;

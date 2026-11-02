-- Expose a server timestamp so clients can compensate for device clock skew
-- while calculating the shared countdown and result deadline.
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
  game_display_name text;
begin
  select * into match_row
  from public.duel_matches
  where id = target_duel_id
    and viewer_id in (requester_id, opponent_id);
  if match_row.id is null then raise exception 'duel not found'; end if;

  select * into viewer_run
  from public.duel_runs
  where duel_id = target_duel_id and user_id = viewer_id;

  select coalesce(game.display_name, versioned.display_name)
  into game_display_name
  from public.game_rule_versions versioned
  left join public.games game on game.id = versioned.game_id
  where versioned.game_id = match_row.game_id
    and versioned.version = match_row.game_version;

  return jsonb_build_object(
    'id', match_row.id,
    'requester_id', match_row.requester_id,
    'opponent_id', match_row.opponent_id,
    'game_id', match_row.game_id,
    'game_version', match_row.game_version,
    'game_name', coalesce(game_display_name, match_row.game_id),
    'game_display_name', coalesce(game_display_name, match_row.game_id),
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
    'server_now', clock_timestamp(),
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
        'nickname', coalesce(profile.nickname,
          case when run.user_id = viewer_id then '나' else '상대' end),
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
      from public.duel_runs run
      left join public.profiles profile on profile.id = run.user_id
      where run.duel_id = target_duel_id
    )
  );
end;
$function$;

revoke all on function public.duel_room_snapshot(uuid, uuid)
  from public, anon, authenticated;

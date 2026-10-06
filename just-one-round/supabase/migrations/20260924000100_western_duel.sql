-- Release-gated: apply only when build 24 is available to players. This
-- changes already-allocated future mole days; running it before the app
-- rollout would serve an unsupported game to older clients. Historical mole
-- sessions and scores remain intact.
insert into public.games (
  id, version, display_name, description, duration_seconds,
  is_active, minimum_app_build
) values (
  'western_duel', 1, '서부의 한 발',
  'DRAW!가 뜨면 한 발. 실제 랭킹 총잡이와 반응속도를 겨루세요.',
  30, true, 24
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  is_active = excluded.is_active,
  minimum_app_build = excluded.minimum_app_build;

update public.games set is_active = false where id = 'mole_reaction';

update public.daily_games
set game_id = 'western_duel', game_version = 1
where play_date > public.current_play_date() and game_id = 'mole_reaction';

update public.daily_game_rotation_entries
set game_id = 'western_duel'
where game_id = 'mole_reaction'
  and (scheduled_date is null or scheduled_date > public.current_play_date());

create table public.western_duel_opponents (
  session_id uuid primary key references public.daily_play_sessions(id) on delete cascade,
  play_date date not null,
  source_user_id uuid references auth.users(id) on delete set null,
  source_score_id uuid,
  nickname text not null,
  nickname_color text not null default 'default',
  reaction_ms integer not null check (reaction_ms between 1 and 1500),
  is_bot boolean not null,
  created_at timestamptz not null default now(),
  constraint western_duel_bot_source check (
    (is_bot and source_user_id is null and source_score_id is null)
    or (not is_bot and source_score_id is not null)
  )
);

create index western_duel_opponents_selection_idx
  on public.western_duel_opponents(play_date, source_user_id)
  where not is_bot;

alter table public.western_duel_opponents enable row level security;
revoke all on table public.western_duel_opponents from public, anon, authenticated;

create function public.confirm_western_duel_started(play_reference_id uuid)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  target_session public.daily_play_sessions;
  existing public.western_duel_opponents;
  selected record;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select * into target_session
  from public.daily_play_sessions s
  where s.user_id = current_user_id
    and s.play_date = public.current_play_date()
    and (s.id = play_reference_id or s.attempt_id = play_reference_id)
  for update;
  if target_session.id is null
    or target_session.game_id <> 'western_duel'
    or target_session.game_version <> 1 then
    raise exception 'western duel session not found';
  end if;

  select * into existing from public.western_duel_opponents
  where session_id = target_session.id;
  if existing.session_id is not null then
    return jsonb_build_object(
      'nickname', existing.nickname,
      'nickname_color', existing.nickname_color,
      'reaction_ms', existing.reaction_ms,
      'is_bot', existing.is_bot
    );
  end if;

  -- A single day lock makes least-used selection atomic across all players.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('western_duel_opponent'),
    pg_catalog.hashtext(target_session.play_date::text)
  );

  -- This also verifies challenge attempt status and marks actual start. Any
  -- error rolls back the assignment made in this same transaction.
  perform public.confirm_daily_play_started(play_reference_id);

  select best.user_id, best.attempt_id, best.raw_score,
         profile.nickname,
         coalesce(to_jsonb(profile)->>'nickname_color', 'default') as nickname_color
  into selected
  from (
    select distinct on (score.user_id)
      score.user_id, score.attempt_id, score.raw_score
    from public.scores score
    join public.profiles profile on profile.id = score.user_id
    where score.play_date = target_session.play_date
      and score.game_id = 'western_duel'
      and score.game_version = 1
      and score.raw_score between 998500 and 999999
      and score.user_id <> current_user_id
      and not profile.is_test_account
    order by score.user_id, score.raw_score desc, score.submitted_at asc
  ) best
  join public.profiles profile on profile.id = best.user_id
  left join (
    select opponent.source_user_id, count(*) as selected_count
    from public.western_duel_opponents opponent
    join public.daily_play_sessions session on session.id = opponent.session_id
    where opponent.play_date = target_session.play_date
      and session.play_mode = 'challenge'
      and not opponent.is_bot
    group by opponent.source_user_id
  ) usage on usage.source_user_id = best.user_id
  order by coalesce(usage.selected_count, 0), random()
  limit 1;

  if selected.user_id is null then
    insert into public.western_duel_opponents(
      session_id, play_date, nickname, reaction_ms, is_bot
    ) values (
      target_session.id, target_session.play_date,
      '떠돌이 총잡이', 350 + floor(random() * 201)::integer, true
    ) returning * into existing;
  else
    insert into public.western_duel_opponents(
      session_id, play_date, source_user_id, source_score_id,
      nickname, nickname_color, reaction_ms, is_bot
    ) values (
      target_session.id, target_session.play_date,
      selected.user_id, selected.attempt_id,
      coalesce(selected.nickname, '이름 없는 총잡이'),
      coalesce(selected.nickname_color, 'default'),
      1000000 - selected.raw_score::integer, false
    ) returning * into existing;
  end if;

  return jsonb_build_object(
    'nickname', existing.nickname,
    'nickname_color', existing.nickname_color,
    'reaction_ms', existing.reaction_ms,
    'is_bot', existing.is_bot
  );
end;
$$;

revoke all on function public.confirm_western_duel_started(uuid) from public, anon;
grant execute on function public.confirm_western_duel_started(uuid) to authenticated;

alter function public.submit_daily_score(uuid, integer, integer, integer, integer)
  rename to submit_daily_score_before_western_duel;

revoke all on function public.submit_daily_score_before_western_duel(
  uuid, integer, integer, integer, integer
) from public, anon, authenticated;

create function public.submit_daily_score(
  attempt_id uuid,
  raw_score integer,
  stars_collected integer,
  collisions integer,
  duration_ms integer
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  active_attempt public.attempts;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  select * into active_attempt from public.attempts
  where id = attempt_id and user_id = current_user_id for update;
  if active_attempt is null then raise exception 'attempt not found'; end if;

  if active_attempt.game_id is distinct from 'western_duel'
    or active_attempt.game_version is distinct from 1 then
    return public.submit_daily_score_before_western_duel(
      attempt_id, raw_score, stars_collected, collisions, duration_ms
    );
  end if;

  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued' then raise exception 'active attempt not found'; end if;

  perform public.assert_score_submission_elapsed(active_attempt.issued_at, duration_ms);
  if active_attempt.game_duration_seconds <> 30
    or raw_score not between 998500 and 999999
    or stars_collected <> 0
    or collisions <> 0
    or duration_ms not between 7600 and 30000
    or not exists (
      select 1 from public.western_duel_opponents opponent
      join public.daily_play_sessions session on session.id = opponent.session_id
      where session.attempt_id = active_attempt.id
        and session.started_at is not null
        and session.started_at <= now() - interval '7 seconds'
    ) then
    raise exception 'invalid western duel result';
  end if;

  if now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts set status = 'expired' where id = active_attempt.id;
    raise exception 'attempt expired';
  end if;

  insert into public.scores (
    attempt_id, user_id, play_date, game_id, game_version, raw_score, duration_ms
  ) values (
    active_attempt.id, current_user_id, active_attempt.play_date,
    active_attempt.game_id, active_attempt.game_version, raw_score, duration_ms
  );
  update public.attempts set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;
  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

revoke all on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  from public, anon;
grant execute on function public.submit_daily_score(uuid, integer, integer, integer, integer)
  to authenticated;

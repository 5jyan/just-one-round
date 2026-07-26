-- Tighten client access, keep test accounts out of public competition, and
-- enforce invariants that previously existed only in SECURITY DEFINER RPCs.

-- Profile mutations must go through vetted RPCs such as set_my_nickname().
drop policy if exists "profiles_update_own" on public.profiles;

-- Supabase grants broad table privileges to API roles by default. RLS was
-- already blocking most writes, but explicit least-privilege grants provide a
-- second boundary and prevent profile privilege escalation.
revoke all on table public.app_runtime_config from anon, authenticated;
revoke all on table public.attempts from anon, authenticated;
revoke all on table public.blocked_profiles from anon, authenticated;
revoke all on table public.daily_games from anon, authenticated;
revoke all on table public.daily_rank_npcs from anon, authenticated;
revoke all on table public.games from anon, authenticated;
revoke all on table public.nickname_reports from anon, authenticated;
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.rewarded_ad_grants from anon, authenticated;
revoke all on table public.scores from anon, authenticated;

grant select on table public.games to anon, authenticated;
grant select on table public.daily_games to anon, authenticated;
grant select on table public.profiles to authenticated;
grant select on table public.attempts to authenticated;
grant select on table public.scores to authenticated;

-- A test account may see its own result, but it must never appear in another
-- user's public leaderboard.
create or replace function public.get_my_daily_result(
  target_date date default null
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  requested_date date := coalesce(
    target_date,
    (now() at time zone 'Asia/Seoul')::date
  );
  requested_game_id text;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select coalesce(
    (
      select s.game_id
      from public.scores s
      where s.user_id = current_user_id and s.play_date = requested_date
      order by s.submitted_at desc
      limit 1
    ),
    (
      select a.game_id
      from public.attempts a
      where a.user_id = current_user_id and a.play_date = requested_date
      order by a.issued_at desc
      limit 1
    ),
    (
      select dg.game_id
      from public.daily_games dg
      where dg.play_date = requested_date
    )
  ) into requested_game_id;

  if requested_game_id is null then
    return jsonb_build_object(
      'score', null,
      'rank', null,
      'nickname', null,
      'participants', 0,
      'top_percent', null,
      'best_score', null,
      'nearby', '[]'::jsonb,
      'leaders', '[]'::jsonb
    );
  end if;

  perform public.ensure_daily_rank_npcs(requested_date, requested_game_id);

  return (
  with real_best as (
    select distinct on (s.user_id)
      'user:' || s.user_id::text as identity_key,
      s.user_id,
      p.nickname,
      s.raw_score,
      s.submitted_at,
      false as is_npc
    from public.scores s
    join public.profiles p on p.id = s.user_id
    where s.play_date = requested_date
      and s.game_id = requested_game_id
      and (not p.is_test_account or s.user_id = current_user_id)
      and not exists (
        select 1
        from public.blocked_profiles blocked
        where blocked.blocker_id = current_user_id
          and blocked.blocked_id = s.user_id
      )
    order by s.user_id, s.raw_score desc, s.submitted_at asc
  ), candidates as (
    select * from real_best
    union all
    select
      'npc:' || npc.slot::text as identity_key,
      null::uuid as user_id,
      npc.nickname,
      npc.raw_score,
      npc.play_date::timestamptz + make_interval(secs => npc.slot) as submitted_at,
      true as is_npc
    from public.daily_rank_npcs npc
    where npc.play_date = requested_date
      and npc.game_id = requested_game_id
  ), ranked as (
    select
      identity_key,
      user_id,
      nickname,
      raw_score,
      is_npc,
      row_number() over (order by raw_score desc, submitted_at asc) as rank,
      count(*) over () as participants
    from candidates
  ), mine as (
    select * from ranked where user_id = current_user_id
  ), bounds as (
    select case
      when rank = 1 then 1
      when rank = participants then greatest(1, participants - 2)
      else rank - 1
    end as first_rank,
    case
      when rank = 1 then least(participants, 3)
      when rank = participants then participants
      else least(participants, rank + 1)
    end as last_rank
    from mine
  )
  select jsonb_build_object(
    'score', (select raw_score from mine),
    'rank', (select rank from mine),
    'nickname', (select nickname from mine),
    'participants', coalesce(
      (select participants from mine),
      (select count(*) from ranked)
    ),
    'top_percent', case
      when not exists (select 1 from mine) then null
      else greatest(
        1,
        ceil(
          (select rank from mine)::numeric * 100 /
          (select participants from mine)
        )::integer
      )
    end,
    'best_score', (select raw_score from ranked where rank = 1),
    'nearby', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'rank', neighbors.rank,
          'user_id', neighbors.user_id,
          'nickname', coalesce(neighbors.nickname, '이름 미설정'),
          'score', neighbors.raw_score,
          'is_me', coalesce(neighbors.user_id = current_user_id, false),
          'is_npc', neighbors.is_npc
        ) order by neighbors.rank
      )
      from ranked neighbors, bounds b
      where neighbors.rank between b.first_rank and b.last_rank
    ), '[]'::jsonb),
    'leaders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'rank', leaders.rank,
          'user_id', leaders.user_id,
          'nickname', coalesce(leaders.nickname, '이름 미설정'),
          'score', leaders.raw_score,
          'is_me', coalesce(leaders.user_id = current_user_id, false),
          'is_npc', leaders.is_npc
        ) order by leaders.rank
      )
      from ranked leaders
      where leaders.rank <= 50
    ), '[]'::jsonb)
  ));
end;
$$;

-- Rank each game independently. This matters for test accounts that may play
-- multiple games on the same date with incomparable scoring scales.
create or replace function public.get_my_play_history(
  history_limit integer default 30
)
returns jsonb
language sql
stable
security definer set search_path = ''
as $$
  with best_per_user_game_day as (
    select distinct on (s.play_date, s.game_id, s.user_id)
      s.play_date,
      s.user_id,
      s.game_id,
      s.raw_score,
      s.submitted_at
    from public.scores s
    join public.profiles p on p.id = s.user_id
    where not p.is_test_account or s.user_id = (select auth.uid())
    order by
      s.play_date,
      s.game_id,
      s.user_id,
      s.raw_score desc,
      s.submitted_at asc
  ), ranked as (
    select
      b.play_date,
      b.user_id,
      b.game_id,
      b.raw_score,
      row_number() over (
        partition by b.play_date, b.game_id
        order by b.raw_score desc, b.submitted_at asc
      ) as rank,
      count(*) over (
        partition by b.play_date, b.game_id
      ) as participants
    from best_per_user_game_day b
  ), mine as (
    select
      r.play_date,
      r.game_id,
      g.display_name,
      r.raw_score,
      r.rank,
      r.participants
    from ranked r
    join public.games g on g.id = r.game_id
    where r.user_id = (select auth.uid())
    order by r.play_date desc, r.game_id
    limit least(greatest(history_limit, 1), 100)
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'play_date', play_date,
      'game_id', game_id,
      'display_name', display_name,
      'score', raw_score,
      'rank', rank,
      'participants', participants
    ) order by play_date desc, game_id
  ), '[]'::jsonb)
  from mine;
$$;

-- Speed up auth.users deletion cascades that search by the non-leading side of
-- composite moderation indexes.
create index blocked_profiles_blocked_id_idx
  on public.blocked_profiles (blocked_id);

create index nickname_reports_reported_user_id_idx
  on public.nickname_reports (reported_user_id);

-- Collapse any pre-existing duplicate active grants before enforcing the
-- invariant at the database level.
with ranked_active_grants as (
  select
    id,
    row_number() over (
      partition by user_id, play_date
      order by
        (status = 'verified') desc,
        prepared_at desc,
        id desc
    ) as active_rank
  from public.rewarded_ad_grants
  where status in ('prepared', 'verified')
)
update public.rewarded_ad_grants grant_row
set status = 'expired'
from ranked_active_grants ranked
where grant_row.id = ranked.id
  and ranked.active_rank > 1;

create unique index rewarded_ad_grants_one_active_idx
  on public.rewarded_ad_grants (user_id, play_date)
  where status in ('prepared', 'verified');

-- scores intentionally duplicates attempt identity for ranking performance.
-- Enforce that the denormalized identity always matches its source attempt.
create function public.enforce_score_attempt_identity()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.attempts attempt
    where attempt.id = new.attempt_id
      and attempt.user_id = new.user_id
      and attempt.play_date = new.play_date
      and attempt.game_id = new.game_id
      and attempt.game_version = new.game_version
  ) then
    raise exception 'score identity does not match attempt'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger enforce_score_attempt_identity_before_write
  before insert or update of
    attempt_id,
    user_id,
    play_date,
    game_id,
    game_version
  on public.scores
  for each row execute procedure public.enforce_score_attempt_identity();

revoke execute on function public.enforce_score_attempt_identity()
  from public, anon, authenticated;

-- Reassert the intended RPC privileges after replacing functions.
revoke execute on function public.get_my_daily_result(date)
  from public, anon;
revoke execute on function public.get_my_play_history(integer)
  from public, anon;
grant execute on function public.get_my_daily_result(date) to authenticated;
grant execute on function public.get_my_play_history(integer) to authenticated;

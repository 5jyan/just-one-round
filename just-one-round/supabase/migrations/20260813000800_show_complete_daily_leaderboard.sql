-- Return every ranked player so the client can display the daily leaderboard
-- continuously from first through last place.

create or replace function public.get_my_daily_result(
  target_date date default null
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  requested_date date := coalesce(target_date, public.current_play_date());
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

  return (
  with real_best as (
    select distinct on (s.user_id)
      s.user_id,
      p.nickname,
      s.raw_score,
      s.submitted_at,
      exists (
        select 1
        from public.blocked_profiles blocked
        where blocked.blocker_id = current_user_id
          and blocked.blocked_id = s.user_id
      ) as is_blocked
    from public.scores s
    join public.profiles p on p.id = s.user_id
    where s.play_date = requested_date
      and s.game_id = requested_game_id
      and (not p.is_test_account or s.user_id = current_user_id)
    order by s.user_id, s.raw_score desc, s.submitted_at asc
  ), ranked as (
    select
      user_id,
      nickname,
      raw_score,
      is_blocked,
      row_number() over (
        order by raw_score desc, submitted_at asc, user_id
      ) as rank,
      count(*) over () as participants
    from real_best
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
          'user_id', case
            when neighbors.is_blocked then null
            else neighbors.user_id
          end,
          'nickname', case
            when neighbors.is_blocked then '차단한 사용자'
            else coalesce(neighbors.nickname, '이름 미설정')
          end,
          'score', neighbors.raw_score,
          'is_me', neighbors.user_id = current_user_id,
          'is_npc', false
        ) order by neighbors.rank
      )
      from ranked neighbors, bounds b
      where neighbors.rank between b.first_rank and b.last_rank
    ), '[]'::jsonb),
    'leaders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'rank', leaderboard.rank,
          'user_id', case
            when leaderboard.is_blocked then null
            else leaderboard.user_id
          end,
          'nickname', case
            when leaderboard.is_blocked then '차단한 사용자'
            else coalesce(leaderboard.nickname, '이름 미설정')
          end,
          'score', leaderboard.raw_score,
          'is_me', leaderboard.user_id = current_user_id,
          'is_npc', false
        ) order by leaderboard.rank
      )
      from ranked leaderboard
    ), '[]'::jsonb)
  ));
end;
$$;

revoke execute on function public.get_my_daily_result(date)
  from public, anon;
grant execute on function public.get_my_daily_result(date) to authenticated;

comment on function public.get_my_daily_result(date) is
  'Returns the complete daily leaderboard ranked against real non-test players.';

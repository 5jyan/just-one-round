-- Include the profile level beside every nickname in daily ranking payloads.

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
      select score.game_id
      from public.scores score
      where score.user_id = current_user_id
        and score.play_date = requested_date
      order by score.submitted_at desc
      limit 1
    ),
    (
      select attempt.game_id
      from public.attempts attempt
      where attempt.user_id = current_user_id
        and attempt.play_date = requested_date
      order by attempt.issued_at desc
      limit 1
    ),
    (
      select scheduled.game_id
      from public.daily_games scheduled
      where scheduled.play_date = requested_date
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
    select distinct on (score.user_id)
      score.user_id,
      profile.nickname,
      public.experience_level(profile.experience_points) as level,
      score.raw_score,
      score.submitted_at,
      exists (
        select 1
        from public.blocked_profiles blocked
        where blocked.blocker_id = current_user_id
          and blocked.blocked_id = score.user_id
      ) as is_blocked
    from public.scores score
    join public.profiles profile on profile.id = score.user_id
    where score.play_date = requested_date
      and score.game_id = requested_game_id
      and (
        not profile.is_test_account
        or score.user_id = current_user_id
      )
    order by score.user_id, score.raw_score desc, score.submitted_at asc
  ), ranked as (
    select
      user_id,
      nickname,
      level,
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
          'level', neighbors.level,
          'score', neighbors.raw_score,
          'is_me', neighbors.user_id = current_user_id,
          'is_npc', false
        ) order by neighbors.rank
      )
      from ranked neighbors, bounds bound
      where neighbors.rank between bound.first_rank and bound.last_rank
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
          'level', leaderboard.level,
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
  'Returns the complete daily leaderboard with each player profile level.';

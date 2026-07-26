create function public.get_daily_result(target_date date default null)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  requested_date date := coalesce(
    target_date,
    (now() at time zone 'Asia/Seoul')::date
  );
  requested_game_id text;
begin
  select coalesce(
    (
      select s.game_id
      from public.scores s
      where s.user_id = (select auth.uid()) and s.play_date = requested_date
      order by s.submitted_at desc
      limit 1
    ),
    (
      select a.game_id
      from public.attempts a
      where a.user_id = (select auth.uid()) and a.play_date = requested_date
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
      and not exists (
        select 1
        from public.blocked_profiles blocked
        where blocked.blocker_id = (select auth.uid())
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
    select * from ranked where user_id = (select auth.uid())
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
          'is_me', coalesce(neighbors.user_id = (select auth.uid()), false),
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
          'is_me', coalesce(leaders.user_id = (select auth.uid()), false),
          'is_npc', leaders.is_npc
        ) order by leaders.rank
      )
      from ranked leaders
      where leaders.rank <= 50
    ), '[]'::jsonb)
  ));
end;
$$;

create or replace function public.get_my_daily_result(target_date date default null)
returns jsonb
language sql
security definer set search_path = ''
as $$
  select public.get_daily_result(target_date);
$$;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  scheduled_game public.daily_games;
  selected_game public.games;
  is_test boolean := false;
  selected_test_game_id text;
begin
  scheduled_game := public.ensure_daily_game(seoul_date);

  select p.is_test_account, p.test_game_id
  into is_test, selected_test_game_id
  from public.profiles p
  where p.id = (select auth.uid());

  if coalesce(is_test, false) and selected_test_game_id is not null then
    select * into selected_game
    from public.games
    where id = selected_test_game_id and is_active;
  end if;

  if selected_game is null then
    select * into selected_game
    from public.games
    where id = scheduled_game.game_id and version = scheduled_game.game_version;
  end if;

  return (
    with my_attempts as (
      select *
      from public.attempts
      where user_id = (select auth.uid()) and play_date = seoul_date
    )
    select jsonb_build_object(
      'play_date', seoul_date,
      'game', jsonb_build_object(
        'id', selected_game.id,
        'version', selected_game.version,
        'display_name', selected_game.display_name,
        'description', selected_game.description,
        'duration_seconds', selected_game.duration_seconds
      ),
      'nickname', (
        select nickname
        from public.profiles
        where id = (select auth.uid())
      ),
      'attempts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'ordinal', ordinal,
        'status', status,
        'grant_type', grant_type,
        'game_id', game_id
      ) order by ordinal) from my_attempts), '[]'::jsonb),
      'test_mode', coalesce(is_test, false),
      'ad_attempt_available', case
        when coalesce(is_test, false) then false
        else exists (
          select 1 from my_attempts where ordinal = 1 and status <> 'issued'
        ) and not exists (
          select 1 from my_attempts where ordinal = 2
        )
      end,
      'result', public.get_my_daily_result(seoul_date)
    )
  );
end;
$$;

drop function public.get_filtered_daily_result(
  date,
  smallint,
  public.profile_gender
);
drop function public.update_my_demographics(
  smallint,
  smallint,
  public.profile_gender
);

alter table public.profiles
  drop column birth_year,
  drop column birth_month,
  drop column birth_decade,
  drop column gender,
  drop column region_code;

revoke all on function public.get_daily_result(date) from public;
grant execute on function public.get_daily_result(date) to authenticated;

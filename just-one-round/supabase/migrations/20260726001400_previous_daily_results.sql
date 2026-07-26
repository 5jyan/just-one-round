-- Finalize each play day at 06:10 KST, keep synthetic NPC records in every
-- ranking surface, and remember which previous-day result each user has seen.

create table public.daily_result_acknowledgements (
  user_id uuid not null references auth.users (id) on delete cascade,
  play_date date not null,
  game_id text not null references public.games (id),
  acknowledged_at timestamptz not null default now(),
  primary key (user_id, play_date, game_id)
);

alter table public.daily_result_acknowledgements enable row level security;
revoke all on table public.daily_result_acknowledgements
  from public, anon, authenticated;

create function public.enforce_daily_score_deadline()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  submission_deadline timestamptz :=
    ((new.play_date + 1) + time '06:10') at time zone 'Asia/Seoul';
begin
  if clock_timestamp() >= submission_deadline then
    raise exception 'score submission window closed';
  end if;
  return new;
end;
$$;

create trigger scores_enforce_daily_deadline
before insert on public.scores
for each row execute function public.enforce_daily_score_deadline();

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

  perform public.ensure_daily_rank_npcs(requested_date, requested_game_id);

  return (
  with real_best as (
    select distinct on (s.user_id)
      'user:' || s.user_id::text as identity_key,
      s.user_id,
      p.nickname,
      s.raw_score,
      s.submitted_at,
      false as is_npc,
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
  ), candidates as (
    select * from real_best
    union all
    select
      'npc:' || npc.slot::text as identity_key,
      null::uuid as user_id,
      npc.nickname,
      npc.raw_score,
      npc.play_date::timestamptz + make_interval(secs => npc.slot)
        as submitted_at,
      true as is_npc,
      false as is_blocked
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
      is_blocked,
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
          'user_id', case
            when neighbors.is_blocked then null
            else neighbors.user_id
          end,
          'nickname', case
            when neighbors.is_blocked then '차단한 사용자'
            else coalesce(neighbors.nickname, '이름 미설정')
          end,
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
          'user_id', case
            when leaders.is_blocked then null
            else leaders.user_id
          end,
          'nickname', case
            when leaders.is_blocked then '차단한 사용자'
            else coalesce(leaders.nickname, '이름 미설정')
          end,
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

create or replace function public.get_my_play_history(
  history_limit integer default 30
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  played record;
  history jsonb;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  for played in
    select distinct s.play_date, s.game_id
    from public.scores s
    where s.user_id = current_user_id
  loop
    perform public.ensure_daily_rank_npcs(
      played.play_date,
      played.game_id
    );
  end loop;

  with real_best as (
    select distinct on (s.play_date, s.game_id, s.user_id)
      s.play_date,
      s.user_id,
      s.game_id,
      s.raw_score,
      s.submitted_at
    from public.scores s
    join public.profiles p on p.id = s.user_id
    where not p.is_test_account or s.user_id = current_user_id
    order by
      s.play_date,
      s.game_id,
      s.user_id,
      s.raw_score desc,
      s.submitted_at asc
  ), candidates as (
    select
      r.play_date,
      r.user_id,
      r.game_id,
      r.raw_score,
      r.submitted_at
    from real_best r
    union all
    select
      npc.play_date,
      null::uuid as user_id,
      npc.game_id,
      npc.raw_score,
      npc.play_date::timestamptz + make_interval(secs => npc.slot)
        as submitted_at
    from public.daily_rank_npcs npc
    where exists (
      select 1
      from real_best mine
      where mine.user_id = current_user_id
        and mine.play_date = npc.play_date
        and mine.game_id = npc.game_id
    )
  ), ranked as (
    select
      c.play_date,
      c.user_id,
      c.game_id,
      c.raw_score,
      row_number() over (
        partition by c.play_date, c.game_id
        order by c.raw_score desc, c.submitted_at asc
      ) as rank,
      count(*) over (
        partition by c.play_date, c.game_id
      ) as participants
    from candidates c
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
    where r.user_id = current_user_id
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
  ), '[]'::jsonb) into history
  from mine;
  return history;
end;
$$;

create function public.get_unseen_previous_daily_result()
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
  previous_game_name text;
  result jsonb;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if now() < result_available_at then
    return null;
  end if;

  if exists (
    select 1
    from public.profiles p
    where p.id = current_user_id and p.is_test_account
  ) then
    return null;
  end if;

  select s.game_id, g.display_name
  into previous_game_id, previous_game_name
  from public.scores s
  join public.games g on g.id = s.game_id
  where s.user_id = current_user_id
    and s.play_date = previous_date
  order by s.submitted_at desc
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

  return result || jsonb_build_object(
    'play_date', previous_date,
    'game_id', previous_game_id,
    'display_name', previous_game_name
  );
end;
$$;

create function public.acknowledge_previous_daily_result(
  target_date date,
  target_game_id text
)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if target_date <> public.current_play_date() - 1 then
    raise exception 'result is not from the previous play date';
  end if;
  if not exists (
    select 1
    from public.scores s
    where s.user_id = current_user_id
      and s.play_date = target_date
      and s.game_id = target_game_id
  ) then
    raise exception 'daily result not found';
  end if;

  insert into public.daily_result_acknowledgements (
    user_id,
    play_date,
    game_id
  ) values (
    current_user_id,
    target_date,
    target_game_id
  )
  on conflict do nothing;
end;
$$;

revoke all on function public.enforce_daily_score_deadline() from public;
revoke all on function public.get_unseen_previous_daily_result() from public;
revoke all on function public.acknowledge_previous_daily_result(date, text)
  from public;

grant execute on function public.get_unseen_previous_daily_result()
  to authenticated;
grant execute on function public.acknowledge_previous_daily_result(date, text)
  to authenticated;

comment on table public.daily_result_acknowledgements is
  'Tracks the one-time previous-day final result popup per user and game.';

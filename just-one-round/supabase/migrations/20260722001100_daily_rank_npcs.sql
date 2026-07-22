create table public.daily_rank_npcs (
  play_date date not null,
  game_id text not null references public.games (id) on delete cascade,
  slot smallint not null,
  nickname text not null,
  raw_score integer not null check (raw_score >= 0),
  birth_decade smallint not null check (birth_decade between 1960 and 2010),
  gender public.profile_gender not null,
  created_at timestamptz not null default now(),
  primary key (play_date, game_id, slot),
  constraint daily_rank_npcs_supported_gender
    check (gender in ('male'::public.profile_gender, 'female'::public.profile_gender))
);

alter table public.daily_rank_npcs enable row level security;

create or replace function public.rank_npc_hash(seed text)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select ('x' || substr(md5(seed), 1, 8))::bit(32)::bigint;
$$;

create or replace function public.ensure_daily_rank_npcs(
  target_date date,
  target_game_id text
)
returns integer
language plpgsql
security definer set search_path = ''
as $$
declare
  nicknames text[] := array[
    '졸린감자', '밤산책', '초코우유', '구름한입', '퇴근요정', '민트싫어',
    '점심뭐먹지', '작은공룡', '느긋한곰', '새벽두시', '버스막차', '파란양말',
    '고구마피자', '오늘만산다', '왼손잡이', '우주먼지', '연습중', '한번만더',
    '달빛소다', '말랑주먹', '비오는날', '반숙계란', '낮잠천재', '토스트한장',
    '주말순삭', '빙글빙글', '소금빵', '공룡발자국', '집에갈래', '느린번개',
    '귤한박스', '모래시계', '보라구름', '아침잠', '작은파도', '후추톡톡'
  ];
  decades smallint[] := array[1970, 1980, 1990, 2000, 2010];
  desired_count integer;
  nickname_start integer;
  npc_slot integer;
  nickname_index integer;
  score_ratio double precision;
  score_jitter integer;
  generated_score integer;
  generated_gender public.profile_gender;
begin
  if not exists (
    select 1 from public.games where id = target_game_id and is_active
  ) then
    raise exception 'active game not found';
  end if;

  desired_count := 15 + mod(
    public.rank_npc_hash(target_date::text || ':' || target_game_id || ':count'),
    11
  )::integer;
  nickname_start := mod(
    public.rank_npc_hash(target_date::text || ':' || target_game_id || ':names'),
    array_length(nicknames, 1)
  )::integer;

  for npc_slot in 1..desired_count loop
    nickname_index := 1 + mod(
      nickname_start + ((npc_slot - 1) * 7),
      array_length(nicknames, 1)
    );
    score_ratio := (desired_count - npc_slot + 1)::double precision / desired_count;
    score_jitter := mod(
      public.rank_npc_hash(
        target_date::text || ':' || target_game_id || ':score:' || npc_slot
      ),
      4001
    )::integer - 2000;

    generated_score := case target_game_id
      when 'gravity_switch' then greatest(
        2500,
        round(3500 + 58000 * power(score_ratio, 1.65) + score_jitter)::integer
      )
      when 'dung_dodge' then least(
        60000,
        greatest(
          4000,
          round(7000 + 53000 * power(score_ratio, 1.45) + score_jitter)::integer
        )
      )
      else greatest(
        1000,
        round(3000 + 50000 * power(score_ratio, 1.6) + score_jitter)::integer
      )
    end;

    generated_gender := case mod(
      public.rank_npc_hash(
        target_date::text || ':' || target_game_id || ':gender:' || npc_slot
      ),
      2
    )
      when 0 then 'female'::public.profile_gender
      else 'male'::public.profile_gender
    end;

    insert into public.daily_rank_npcs (
      play_date,
      game_id,
      slot,
      nickname,
      raw_score,
      birth_decade,
      gender
    ) values (
      target_date,
      target_game_id,
      npc_slot,
      nicknames[nickname_index],
      generated_score,
      decades[1 + mod(
        public.rank_npc_hash(
          target_date::text || ':' || target_game_id || ':age:' || npc_slot
        ),
        array_length(decades, 1)
      )::integer],
      generated_gender
    ) on conflict (play_date, game_id, slot) do nothing;
  end loop;

  return desired_count;
end;
$$;

create or replace function public.get_filtered_daily_result(
  target_date date default null,
  filter_birth_decade smallint default null,
  filter_gender public.profile_gender default null
)
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
      'nearby', '[]'::jsonb
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
      and (filter_birth_decade is null or p.birth_decade = filter_birth_decade)
      and (filter_gender is null or p.gender = filter_gender)
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
      and (filter_birth_decade is null or npc.birth_decade = filter_birth_decade)
      and (filter_gender is null or npc.gender = filter_gender)
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
    'nearby', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'rank', neighbors.rank,
          'nickname', coalesce(neighbors.nickname, '이름 미설정'),
          'score', neighbors.raw_score,
          'is_me', coalesce(neighbors.user_id = (select auth.uid()), false),
          'is_npc', neighbors.is_npc
        ) order by neighbors.rank
      )
      from ranked neighbors, bounds b
      where neighbors.rank between b.first_rank and b.last_rank
    ), '[]'::jsonb)
  ));
end;
$$;

create or replace function public.get_my_daily_result(target_date date default null)
returns jsonb
language sql
security definer set search_path = ''
as $$
  select public.get_filtered_daily_result(target_date, null, null);
$$;

revoke all on table public.daily_rank_npcs from public, anon, authenticated;
revoke all on function public.rank_npc_hash(text) from public;
revoke all on function public.ensure_daily_rank_npcs(date, text) from public;
revoke all on function public.get_filtered_daily_result(
  date,
  smallint,
  public.profile_gender
) from public;
revoke all on function public.get_my_daily_result(date) from public;

grant execute on function public.get_filtered_daily_result(
  date,
  smallint,
  public.profile_gender
) to authenticated;
grant execute on function public.get_my_daily_result(date) to authenticated;

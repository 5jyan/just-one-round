insert into public.games (
  id,
  version,
  display_name,
  description,
  duration_seconds,
  is_active
) values (
  'failed_bakery',
  1,
  '대충 케이크',
  '움직이는 못난이 케이크를 탭해 쌓으세요. 어긋난 부분은 잘리고 3연속 퍼펙트면 크기가 회복됩니다.',
  180,
  true
) on conflict (id) do update set
  version = excluded.version,
  display_name = excluded.display_name,
  description = excluded.description,
  duration_seconds = excluded.duration_seconds,
  is_active = excluded.is_active;

create or replace function public.submit_daily_score(
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
  scheduled_duration integer;
  submitted_score integer := $2;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id and user_id = current_user_id
  for update;

  if active_attempt is null then raise exception 'attempt not found'; end if;
  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued' then
    raise exception 'active attempt not found';
  end if;

  select duration_seconds into scheduled_duration
  from public.games
  where id = active_attempt.game_id and version = active_attempt.game_version;

  case active_attempt.game_id
    when 'dung_dodge' then
      if submitted_score <> duration_ms
        or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid dung dodge result';
      end if;
    when 'gravity_switch' then
      if submitted_score <> duration_ms
        or stars_collected <> 0
        or collisions <> 1
        or duration_ms < 1 then
        raise exception 'invalid gravity switch result';
      end if;
    when 'failed_bakery' then
      if submitted_score not between 0 and 999
        or stars_collected not between 0 and submitted_score
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid failed bakery result';
      end if;
    else
      raise exception 'unsupported game result';
  end case;

  if active_attempt.game_id <> 'gravity_switch'
    and now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts set status = 'expired' where id = active_attempt.id;
    raise exception 'attempt expired';
  end if;

  insert into public.scores (
    attempt_id,
    user_id,
    play_date,
    game_id,
    game_version,
    raw_score,
    duration_ms,
    stars_collected,
    collisions
  ) values (
    active_attempt.id,
    current_user_id,
    active_attempt.play_date,
    active_attempt.game_id,
    active_attempt.game_version,
    submitted_score,
    duration_ms,
    stars_collected,
    collisions
  );

  update public.attempts
  set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;

  return public.get_my_daily_result(active_attempt.play_date);
end;
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
      when 'failed_bakery' then greatest(
        3,
        round(
          5 + 55 * power(score_ratio, 1.55)
          + (
            mod(
              public.rank_npc_hash(
                target_date::text || ':' || target_game_id || ':cake:' || npc_slot
              ),
              9
            )::integer - 4
          )
        )::integer
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

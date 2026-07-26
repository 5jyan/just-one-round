-- Rebalance synthetic leaderboard entries to the approved per-game ranges and
-- refresh their nickname pool. Boundary slots are exact; intermediate slots
-- use a deterministic curve plus bounded deterministic jitter.

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
    '거제야호', '파라파라', '카리나', 'FAKER', '랄로', '테스터훈',
    '퇴근하고싶다', '오늘도야근', '점메추', '저메추', '민초단', '반민초단',
    '알잘딱깔센', '오히려좋아', '못참지', '가보자고', '억까금지', '폼미쳤다',
    '중꺾마', '긁혔네', '완전럭키비키', '원영적사고', '도파민중독', '일단누워',
    '집가고싶다', '내일할게', '방금일어남', '배고픈개발자', '버스놓침',
    '와이파이도둑', '무지성클릭', '한판만더', '진짜마지막', '손가락이슈',
    '키보드워리어', '실버탈출중', '뉴비입니다', '고인물아님', '랜덤인생',
    '월급루팡', '야식금지', '치킨마요', '제로콜라', '얼죽아', '물복파',
    '딱복파', '붕어빵팥', '슈붕최고'
  ];
  desired_count integer;
  nickname_start integer;
  nickname_index integer;
  normalized_position double precision;
  generated_score integer;
  generated_duration integer;
begin
  if not exists (
    select 1
    from public.games
    where id = target_game_id and is_active
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

  for current_slot in 1..desired_count loop
    nickname_index := 1 + mod(
      nickname_start + ((current_slot - 1) * 7),
      array_length(nicknames, 1)
    );
    normalized_position :=
      (desired_count - current_slot)::double precision / (desired_count - 1);

    if target_game_id = 'apple_game_v2' then
      generated_score := case
        when current_slot = 1 then 52
        when current_slot = desired_count then 22
        else least(
          51,
          greatest(
            23,
            22
            + round(30 * power(normalized_position, 1.15))::integer
            + (
              mod(
                public.rank_npc_hash(
                  target_date::text || ':' || target_game_id
                  || ':jitter:' || current_slot
                ),
                5
              )::integer - 2
            )
          )
        )
      end;
    elsif target_game_id = 'dung_dodge_v2' then
      generated_score := case
        when current_slot = 1 then 62370
        when current_slot = desired_count then 12170
        else least(
          62369,
          greatest(
            12171,
            12170
            + round(50200 * power(normalized_position, 1.45))::integer
            + (
              mod(
                public.rank_npc_hash(
                  target_date::text || ':' || target_game_id
                  || ':jitter:' || current_slot
                ),
                2401
              )::integer - 1200
            )
          )
        )
      end;
    elsif target_game_id = 'gravity_switch' then
      generated_score := case
        when current_slot = 1 then 57890
        when current_slot = desired_count then 4530
        else least(
          57889,
          greatest(
            4531,
            4530
            + round(53360 * power(normalized_position, 1.55))::integer
            + (
              mod(
                public.rank_npc_hash(
                  target_date::text || ':' || target_game_id
                  || ':jitter:' || current_slot
                ),
                2001
              )::integer - 1000
            )
          )
        )
      end;
    elsif target_game_id = 'number_rush' then
      generated_duration := case
        when current_slot = 1 then 51570
        when current_slot = desired_count then 140570
        else least(
          140569,
          greatest(
            51571,
            51570
            + round(
              89000 * power(1 - normalized_position, 1.25)
            )::integer
            + (
              mod(
                public.rank_npc_hash(
                  target_date::text || ':' || target_game_id
                  || ':jitter:' || current_slot
                ),
                3001
              )::integer - 1500
            )
          )
        )
      end;
      generated_score := 3600000 - generated_duration;
    else
      generated_score := null;
    end if;

    if generated_score is null then
      raise exception 'unsupported active game';
    end if;

    insert into public.daily_rank_npcs (
      play_date,
      game_id,
      slot,
      nickname,
      raw_score
    ) values (
      target_date,
      target_game_id,
      current_slot,
      nicknames[nickname_index],
      generated_score
    )
    on conflict (play_date, game_id, slot) do nothing;
  end loop;

  return desired_count;
end;
$$;

-- Cached rows would otherwise keep the previous formula indefinitely.
delete from public.daily_rank_npcs
where play_date >= public.current_play_date();

revoke execute on function public.ensure_daily_rank_npcs(date, text)
  from public, anon, authenticated;

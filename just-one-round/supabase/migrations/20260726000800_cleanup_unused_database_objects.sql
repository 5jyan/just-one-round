-- Remove database objects left behind by retired game and demographic features,
-- and make SECURITY DEFINER RPC access explicit.

-- This legacy overload predates raw_score and is no longer called by the app.
drop function if exists public.submit_daily_score(
  uuid,
  integer,
  integer,
  integer
);

-- Keep the public RPC contract stable, but only validate active games and stop
-- persisting result metadata that is never queried after validation.
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
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id and user_id = current_user_id
  for update;

  if active_attempt is null then
    raise exception 'attempt not found';
  end if;
  if active_attempt.status = 'submitted' then
    return public.get_my_daily_result(active_attempt.play_date);
  end if;
  if active_attempt.status <> 'issued' then
    raise exception 'active attempt not found';
  end if;

  select duration_seconds into scheduled_duration
  from public.games
  where id = active_attempt.game_id
    and version = active_attempt.game_version
    and is_active;

  if scheduled_duration is null then
    raise exception 'active game version not found';
  end if;

  case active_attempt.game_id
    when 'dung_dodge_v2' then
      if submitted_score <> duration_ms
        or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid dung dodge v2 result';
      end if;
    when 'gravity_switch' then
      if submitted_score <> duration_ms
        or stars_collected <> 0
        or collisions <> 1
        or duration_ms < 1 then
        raise exception 'invalid gravity switch result';
      end if;
    when 'apple_game_v2' then
      if submitted_score not between 0 and 77
        or stars_collected <> 0
        or collisions <> 0
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid apple game v2 result';
      end if;
    when 'number_rush' then
      if submitted_score <> 3600000 - duration_ms
        or submitted_score not between
          3600000 - scheduled_duration * 1000 and 3599999
        or stars_collected <> 0
        or collisions not in (0, 1)
        or duration_ms not between 1 and scheduled_duration * 1000 then
        raise exception 'invalid number rush result';
      end if;
    else
      raise exception 'unsupported game result';
  end case;

  if active_attempt.game_id <> 'gravity_switch'
    and now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts
    set status = 'expired'
    where id = active_attempt.id;
    raise exception 'attempt expired';
  end if;

  insert into public.scores (
    attempt_id,
    user_id,
    play_date,
    game_id,
    game_version,
    raw_score,
    duration_ms
  ) values (
    active_attempt.id,
    current_user_id,
    active_attempt.play_date,
    active_attempt.game_id,
    active_attempt.game_version,
    submitted_score,
    duration_ms
  );

  update public.attempts
  set status = 'submitted', submitted_at = now()
  where id = active_attempt.id;

  return public.get_my_daily_result(active_attempt.play_date);
end;
$$;

alter table public.scores
  drop column stars_collected,
  drop column collisions;

-- Demographic filtering was removed from real profiles. Remove the matching
-- write-only NPC attributes and the enum that existed solely for those fields.
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
  desired_count integer;
  nickname_start integer;
  nickname_index integer;
  score_ratio double precision;
  score_jitter integer;
  generated_score integer;
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
    score_ratio :=
      (desired_count - current_slot + 1)::double precision / desired_count;
    score_jitter := mod(
      public.rank_npc_hash(
        target_date::text || ':' || target_game_id || ':score:' || current_slot
      ),
      4001
    )::integer - 2000;

    generated_score := case target_game_id
      when 'gravity_switch' then greatest(
        2500,
        round(3500 + 58000 * power(score_ratio, 1.65) + score_jitter)::integer
      )
      when 'dung_dodge_v2' then least(
        60000,
        greatest(
          4000,
          round(7000 + 53000 * power(score_ratio, 1.45) + score_jitter)::integer
        )
      )
      when 'apple_game_v2' then least(
        72,
        greatest(
          12,
          round(
            8 + 56 * power(score_ratio, 1.45)
            + (
              mod(
                public.rank_npc_hash(
                  target_date::text || ':' || target_game_id
                  || ':apple2:' || current_slot
                ),
                11
              )::integer - 5
            )
          )::integer
        )
      )
      when 'number_rush' then 3600000 - least(
        45000,
        greatest(
          8500,
          round(
            9000 + 31000 * power(1 - score_ratio, 1.35)
            + (
              mod(
                public.rank_npc_hash(
                  target_date::text || ':' || target_game_id
                  || ':rush:' || current_slot
                ),
                3001
              )::integer - 1500
            )
          )::integer
        )
      )
      else null
    end;

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

alter table public.daily_rank_npcs
  drop column birth_decade,
  drop column gender;

drop type public.profile_gender;

-- Preserve the app-facing function name and remove the one-line wrapper.
drop function public.get_my_daily_result(date);
alter function public.get_daily_result(date)
  rename to get_my_daily_result;

-- Supabase's default privileges can grant EXECUTE directly to API roles when a
-- function is created. Revoke those grants explicitly, then allow only the
-- intended entry points.
revoke execute on function public.handle_new_user()
  from public, anon, authenticated;
revoke execute on function public.ensure_daily_game(date)
  from public, anon, authenticated;
revoke execute on function public.ensure_daily_rank_npcs(date, text)
  from public, anon, authenticated;
revoke execute on function public.rank_npc_hash(text)
  from public, anon, authenticated;
revoke execute on function public.rewarded_ads_enabled()
  from public, anon, authenticated;
revoke execute on function public.verify_rewarded_ad_grant(
  uuid,
  uuid,
  text,
  text,
  integer,
  text
) from public, anon, authenticated;

revoke execute on function public.block_user(uuid)
  from public, anon;
revoke execute on function public.claim_daily_attempt()
  from public, anon;
revoke execute on function public.claim_rewarded_attempt(uuid)
  from public, anon;
revoke execute on function public.expire_attempt(uuid)
  from public, anon;
revoke execute on function public.get_developer_games()
  from public, anon;
revoke execute on function public.get_my_daily_result(date)
  from public, anon;
revoke execute on function public.get_my_play_history(integer)
  from public, anon;
revoke execute on function public.get_today_state()
  from public, anon;
revoke execute on function public.prepare_rewarded_ad()
  from public, anon;
revoke execute on function public.report_nickname(uuid)
  from public, anon;
revoke execute on function public.reset_developer_daily_progress()
  from public, anon;
revoke execute on function public.set_developer_game(text)
  from public, anon;
revoke execute on function public.set_my_nickname(text)
  from public, anon;
revoke execute on function public.submit_daily_score(
  uuid,
  integer,
  integer,
  integer,
  integer
) from public, anon;

grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.claim_daily_attempt() to authenticated;
grant execute on function public.claim_rewarded_attempt(uuid) to authenticated;
grant execute on function public.expire_attempt(uuid) to authenticated;
grant execute on function public.get_developer_games() to authenticated;
grant execute on function public.get_my_daily_result(date) to authenticated;
grant execute on function public.get_my_play_history(integer) to authenticated;
grant execute on function public.get_today_state() to authenticated;
grant execute on function public.prepare_rewarded_ad() to authenticated;
grant execute on function public.report_nickname(uuid) to authenticated;
grant execute on function public.reset_developer_daily_progress()
  to authenticated;
grant execute on function public.set_developer_game(text) to authenticated;
grant execute on function public.set_my_nickname(text) to authenticated;
grant execute on function public.submit_daily_score(
  uuid,
  integer,
  integer,
  integer,
  integer
) to authenticated;
grant execute on function public.verify_rewarded_ad_grant(
  uuid,
  uuid,
  text,
  text,
  integer,
  text
) to service_role;

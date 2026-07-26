-- A play day starts at 06:00 in Seoul and ends immediately before the next
-- day's 06:00. Keeping this calculation in one function prevents RPCs from
-- disagreeing at the reset boundary.
create function public.current_play_date(at_time timestamptz default now())
returns date
language sql
stable
security definer set search_path = ''
as $$
  select (
    (at_time at time zone 'Asia/Seoul') - interval '6 hours'
  )::date;
$$;

create function public.next_daily_reset_at(play_day date)
returns timestamptz
language sql
immutable
security definer set search_path = ''
as $$
  select (
    (play_day + 1)::timestamp + interval '6 hours'
  ) at time zone 'Asia/Seoul';
$$;

create or replace function public.ensure_daily_game(
  target_date date default public.current_play_date()
)
returns public.daily_games
language plpgsql
security definer set search_path = ''
as $$
declare
  existing_schedule public.daily_games;
  selected_game public.games;
  active_game_count integer;
begin
  select * into existing_schedule
  from public.daily_games
  where play_date = target_date;

  if existing_schedule is not null then
    return existing_schedule;
  end if;

  select count(*) into active_game_count
  from public.games
  where is_active;

  if active_game_count = 0 then
    raise exception 'no active games available';
  end if;

  select * into selected_game
  from public.games
  where is_active
  order by id
  offset mod(target_date - date '2026-01-01', active_game_count)
  limit 1;

  insert into public.daily_games (play_date, game_id, game_version)
  values (target_date, selected_game.id, selected_game.version)
  on conflict (play_date) do nothing
  returning * into existing_schedule;

  if existing_schedule is null then
    select * into existing_schedule
    from public.daily_games
    where play_date = target_date;
  end if;

  return existing_schedule;
end;
$$;

create function public.claim_daily_attempt(expected_play_date date)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  scheduled_game public.daily_games;
  selected_game public.games;
  claimed_attempt public.attempts;
  is_test boolean := false;
  selected_test_game_id text;
  next_ordinal smallint := 1;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;

  select p.is_test_account, p.test_game_id
  into is_test, selected_test_game_id
  from public.profiles p
  where p.id = current_user_id;

  scheduled_game := public.ensure_daily_game(play_day);

  if coalesce(is_test, false) and selected_test_game_id is not null then
    select * into selected_game
    from public.games
    where id = selected_test_game_id and is_active;
  end if;

  if selected_game is null then
    select * into selected_game
    from public.games
    where id = scheduled_game.game_id
      and version = scheduled_game.game_version;
  end if;

  if coalesce(is_test, false) then
    select coalesce(max(ordinal), 0) + 1 into next_ordinal
    from public.attempts
    where user_id = current_user_id and play_date = play_day;

    insert into public.attempts (
      user_id, play_date, game_id, game_version, ordinal, grant_type
    ) values (
      current_user_id, play_day, selected_game.id,
      selected_game.version, next_ordinal, 'daily'
    ) returning * into claimed_attempt;
  else
    insert into public.attempts (
      user_id, play_date, game_id, game_version, ordinal, grant_type
    ) values (
      current_user_id, play_day, selected_game.id,
      selected_game.version, 1, 'daily'
    )
    on conflict (user_id, play_date, ordinal)
    do update set user_id = excluded.user_id
    returning * into claimed_attempt;
  end if;

  return claimed_attempt;
end;
$$;

create or replace function public.claim_daily_attempt()
returns public.attempts
language sql
security definer set search_path = ''
as $$
  select public.claim_daily_attempt(public.current_play_date());
$$;

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
      npc.play_date::timestamptz + make_interval(secs => npc.slot)
        as submitted_at,
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

create or replace function public.get_daily_result(target_date date default null)
returns jsonb
language sql
security definer set search_path = ''
as $$
  select public.get_my_daily_result(
    coalesce(target_date, public.current_play_date())
  );
$$;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  play_day date := public.current_play_date();
  scheduled_game public.daily_games;
  selected_game public.games;
  is_test boolean := false;
  selected_test_game_id text;
  ads_enabled boolean := public.rewarded_ads_enabled();
begin
  scheduled_game := public.ensure_daily_game(play_day);

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
    where id = scheduled_game.game_id
      and version = scheduled_game.game_version;
  end if;

  return (
    with my_attempts as (
      select *
      from public.attempts
      where user_id = (select auth.uid()) and play_date = play_day
    )
    select jsonb_build_object(
      'play_date', play_day,
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
        when coalesce(is_test, false) or not ads_enabled then false
        else exists (
          select 1 from my_attempts where ordinal = 1 and status <> 'issued'
        ) and not exists (
          select 1 from my_attempts where ordinal = 2
        )
      end,
      'result', public.get_my_daily_result(play_day)
    )
  );
end;
$$;

create function public.prepare_rewarded_ad(expected_play_date date)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  first_attempt public.attempts;
  active_grant public.rewarded_ad_grants;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_play_date is distinct from play_day then
    raise exception 'daily game changed';
  end if;
  if not public.rewarded_ads_enabled() then
    raise exception 'rewarded ads disabled';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext(play_day::text)
  );

  select * into first_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = play_day
    and ordinal = 1;

  if first_attempt is null or first_attempt.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;

  if exists (
    select 1 from public.attempts
    where user_id = current_user_id
      and play_date = play_day
      and ordinal = 2
  ) then
    raise exception 'rewarded attempt already claimed';
  end if;

  update public.rewarded_ad_grants
  set status = 'expired'
  where user_id = current_user_id
    and play_date = play_day
    and status in ('prepared', 'verified')
    and expires_at <= now();

  select * into active_grant
  from public.rewarded_ad_grants
  where user_id = current_user_id
    and play_date = play_day
    and status in ('prepared', 'verified')
    and expires_at > now()
  order by prepared_at desc
  limit 1
  for update;

  if active_grant is null then
    insert into public.rewarded_ad_grants (
      user_id,
      play_date,
      expires_at
    ) values (
      current_user_id,
      play_day,
      public.next_daily_reset_at(play_day)
    )
    returning * into active_grant;
  end if;

  return jsonb_build_object(
    'id', active_grant.id,
    'user_id', active_grant.user_id,
    'status', active_grant.status,
    'expires_at', active_grant.expires_at
  );
end;
$$;

create or replace function public.prepare_rewarded_ad()
returns jsonb
language sql
security definer set search_path = ''
as $$
  select public.prepare_rewarded_ad(public.current_play_date());
$$;

create or replace function public.claim_rewarded_attempt(
  reward_session_id uuid
)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  first_attempt public.attempts;
  existing_attempt public.attempts;
  scheduled_game public.daily_games;
  target_grant public.rewarded_ad_grants;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into target_grant
  from public.rewarded_ad_grants
  where id = reward_session_id
    and user_id = current_user_id
    and play_date = play_day
  for update;

  if target_grant is null then
    raise exception 'daily game changed';
  end if;

  select * into existing_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = play_day
    and ordinal = 2;

  if target_grant.status = 'consumed' and existing_attempt is not null then
    return existing_attempt;
  end if;

  if target_grant.status <> 'verified' then
    raise exception 'reward verification pending';
  end if;

  select * into first_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = play_day
    and ordinal = 1;

  if first_attempt is null or first_attempt.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;

  scheduled_game := public.ensure_daily_game(play_day);

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type
  ) values (
    current_user_id, play_day, scheduled_game.game_id,
    scheduled_game.game_version, 2, 'rewarded_ad'
  )
  on conflict (user_id, play_date, ordinal) do nothing
  returning * into claimed_attempt;

  if claimed_attempt is null then
    select * into claimed_attempt
    from public.attempts
    where user_id = current_user_id
      and play_date = play_day
      and ordinal = 2;
  end if;

  update public.rewarded_ad_grants
  set status = 'consumed', consumed_at = now()
  where id = reward_session_id;

  return claimed_attempt;
end;
$$;

create or replace function public.reset_developer_daily_progress()
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_test_account
  ) then
    raise exception 'test account required';
  end if;

  delete from public.attempts
  where user_id = (select auth.uid())
    and play_date = public.current_play_date();
end;
$$;

create or replace function public.set_developer_game(selected_game_id text)
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_test_account
  ) then
    raise exception 'test account required';
  end if;

  if not exists (
    select 1 from public.games where id = selected_game_id and is_active
  ) then
    raise exception 'active game not found';
  end if;

  update public.profiles
  set test_game_id = selected_game_id, updated_at = now()
  where id = (select auth.uid());

  delete from public.attempts
  where user_id = (select auth.uid())
    and play_date = public.current_play_date();
end;
$$;

revoke all on function public.current_play_date(timestamptz) from public;
revoke all on function public.next_daily_reset_at(date) from public;
revoke all on function public.claim_daily_attempt(date) from public;
revoke all on function public.prepare_rewarded_ad(date) from public;

grant execute on function public.current_play_date(timestamptz) to authenticated;
grant execute on function public.next_daily_reset_at(date) to authenticated;
grant execute on function public.claim_daily_attempt(date) to authenticated;
grant execute on function public.prepare_rewarded_ad(date) to authenticated;

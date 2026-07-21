alter table public.scores
  add column stars_collected integer not null default 0,
  add column collisions integer not null default 0,
  add constraint scores_stars_range check (stars_collected between 0 and 200),
  add constraint scores_collisions_range check (collisions between 0 and 200);

create or replace function public.expire_attempt(attempt_id uuid)
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  expired_attempt public.attempts;
begin
  update public.attempts
  set status = 'expired'
  where id = attempt_id
    and user_id = (select auth.uid())
    and status = 'issued'
  returning * into expired_attempt;

  if expired_attempt is null then
    raise exception 'active attempt not found';
  end if;

  return expired_attempt;
end;
$$;

create or replace function public.claim_rewarded_attempt()
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  first_attempt public.attempts;
  scheduled_game public.daily_games;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into first_attempt
  from public.attempts
  where user_id = current_user_id
    and play_date = seoul_date
    and ordinal = 1;

  if first_attempt is null or first_attempt.status = 'issued' then
    raise exception 'first attempt must be completed or expired';
  end if;

  select * into scheduled_game
  from public.daily_games
  where play_date = seoul_date;

  insert into public.attempts (
    user_id, play_date, game_id, game_version, ordinal, grant_type
  ) values (
    current_user_id,
    seoul_date,
    scheduled_game.game_id,
    scheduled_game.game_version,
    2,
    'rewarded_ad'
  )
  on conflict (user_id, play_date, ordinal)
  do update set user_id = excluded.user_id
  returning * into claimed_attempt;

  return claimed_attempt;
end;
$$;

create or replace function public.get_my_daily_result(target_date date default null)
returns jsonb
language sql
security definer set search_path = ''
stable
as $$
  with requested as (
    select coalesce(target_date, (now() at time zone 'Asia/Seoul')::date) as play_date
  ),
  best_per_user as (
    select distinct on (s.user_id)
      s.user_id,
      s.raw_score,
      s.submitted_at
    from public.scores s, requested r
    where s.play_date = r.play_date
    order by s.user_id, s.raw_score desc, s.submitted_at asc
  ),
  ranked as (
    select
      user_id,
      raw_score,
      row_number() over (order by raw_score desc, submitted_at asc) as rank
    from best_per_user
  ),
  mine as (
    select * from ranked where user_id = (select auth.uid())
  )
  select jsonb_build_object(
    'score', (select raw_score from mine),
    'rank', (select rank from mine),
    'participants', (select count(*) from ranked),
    'top_percent', case
      when (select count(*) from ranked) = 0 or not exists (select 1 from mine)
        then null
      else greatest(
        1,
        ceil(
          (select rank from mine)::numeric * 100 /
          (select count(*) from ranked)
        )::integer
      )
    end,
    'nearby', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'rank', neighbors.rank,
          'score', neighbors.raw_score,
          'is_me', neighbors.user_id = (select auth.uid())
        ) order by neighbors.rank
      )
      from ranked neighbors
      where neighbors.rank between
        greatest(1, coalesce((select rank from mine), 1) - 2)
        and coalesce((select rank from mine), 1) + 2
    ), '[]'::jsonb)
  );
$$;

create or replace function public.submit_daily_score(
  attempt_id uuid,
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
  official_score bigint;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into active_attempt
  from public.attempts
  where id = attempt_id
    and user_id = current_user_id
  for update;

  if active_attempt is null or active_attempt.status <> 'issued' then
    raise exception 'active attempt not found';
  end if;

  select duration_seconds into scheduled_duration
  from public.games
  where id = active_attempt.game_id
    and version = active_attempt.game_version;

  if stars_collected not between 0 and 200
    or collisions not between 0 and 200 then
    raise exception 'invalid game counters';
  end if;

  if duration_ms < (scheduled_duration * 1000 - 2000)
    or duration_ms > (scheduled_duration * 1000 + 10000) then
    raise exception 'invalid game duration';
  end if;

  if now() < active_attempt.issued_at
      + make_interval(secs => greatest(1, scheduled_duration - 2)) then
    raise exception 'game finished too quickly';
  end if;

  if now() > active_attempt.issued_at + interval '10 minutes' then
    update public.attempts set status = 'expired'
    where id = active_attempt.id;
    raise exception 'attempt expired';
  end if;

  official_score := greatest(
    0,
    stars_collected * 100
      + floor(duration_ms / 1000.0)::integer * 10
      - collisions * 50
  );

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
    official_score,
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

create or replace function public.get_today_state()
returns jsonb
language sql
security definer set search_path = ''
stable
as $$
  with today as (
    select (now() at time zone 'Asia/Seoul')::date as play_date
  ),
  scheduled as (
    select dg.play_date, g.*
    from public.daily_games dg
    join public.games g on g.id = dg.game_id
    join today t on t.play_date = dg.play_date
  ),
  my_attempts as (
    select a.*
    from public.attempts a, today t
    where a.user_id = (select auth.uid())
      and a.play_date = t.play_date
  )
  select jsonb_build_object(
    'play_date', (select play_date from today),
    'game', (select jsonb_build_object(
      'id', id,
      'version', version,
      'display_name', display_name,
      'description', description,
      'duration_seconds', duration_seconds
    ) from scheduled),
    'attempts', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id,
      'ordinal', ordinal,
      'status', status,
      'grant_type', grant_type
    ) order by ordinal) from my_attempts), '[]'::jsonb),
    'ad_attempt_available',
      exists (select 1 from my_attempts where ordinal = 1 and status <> 'issued')
      and not exists (select 1 from my_attempts where ordinal = 2),
    'result', public.get_my_daily_result((select play_date from today))
  );
$$;

revoke all on function public.expire_attempt(uuid) from public;
revoke all on function public.claim_rewarded_attempt() from public;
revoke all on function public.get_my_daily_result(date) from public;
revoke all on function public.submit_daily_score(uuid, integer, integer, integer) from public;
revoke all on function public.get_today_state() from public;

grant execute on function public.expire_attempt(uuid) to authenticated;
grant execute on function public.claim_rewarded_attempt() to authenticated;
grant execute on function public.get_my_daily_result(date) to authenticated;
grant execute on function public.submit_daily_score(uuid, integer, integer, integer) to authenticated;
grant execute on function public.get_today_state() to authenticated;

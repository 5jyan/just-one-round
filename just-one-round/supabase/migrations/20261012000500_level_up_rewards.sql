-- Change the cumulative XP curve to a 100 XP first level-up followed by
-- 150 XP increases (100, 250, 400, ...).  Existing profiles keep the
-- level they had under the old curve as their reward highwater mark.  The
-- same XP value is then replayed through the new server trigger so only the
-- newly reached levels receive challenge tickets.

alter table public.profiles
  add column level_rewarded_through integer not null default 1,
  add column level_celebration_seen_through integer not null default 1,
  add constraint profiles_level_rewarded_through_range
    check (level_rewarded_through >= 1),
  add constraint profiles_level_celebration_seen_through_range
    check (level_celebration_seen_through >= 1);

-- Snapshot the old curve before replacing public.experience_level.  The
-- columns are intentionally initialized to the old level so the migration
-- grants only the difference introduced by the new curve.
update public.profiles profile
set
  level_rewarded_through = floor(
    sqrt(greatest(profile.experience_points, 0)::numeric / 100)
  )::integer + 1,
  level_celebration_seen_through = floor(
    sqrt(greatest(profile.experience_points, 0)::numeric / 100)
  )::integer + 1;

-- The first XP threshold is 0.  For level L, n = L - 1 and the threshold is
-- n * (75*n + 25).  Keeping this in a small immutable helper makes the
-- inverse and the reward trigger use exactly the same boundaries.
create or replace function public.experience_threshold(target_level integer)
returns bigint
language sql
immutable
strict
security definer set search_path = ''
as $$
  select greatest(target_level - 1, 0)::bigint * (
    greatest(target_level - 1, 0)::bigint * 75 + 25
  );
$$;

create or replace function public.experience_level(total_experience bigint)
returns integer
language plpgsql
immutable
strict
security definer set search_path = ''
as $$
declare
  normalized_experience bigint := greatest(total_experience, 0);
  estimated_level integer;
begin
  -- Numeric sqrt gives a compact initial estimate.  The two correction
  -- loops make exact boundary behavior independent of floating point
  -- rounding and keep the function correct for every allowed XP value.
  estimated_level := floor(
    (
      sqrt(
        625::numeric + 300::numeric * normalized_experience::numeric
      ) - 25
    ) / 150
  )::integer + 1;

  while estimated_level > 1
    and public.experience_threshold(estimated_level)
      > normalized_experience
  loop
    estimated_level := estimated_level - 1;
  end loop;

  while public.experience_threshold(estimated_level + 1)
      <= normalized_experience
  loop
    estimated_level := estimated_level + 1;
  end loop;

  return estimated_level;
end;
$$;

create or replace function public.build_player_economy_json(
  total_coins bigint,
  total_experience bigint
)
returns jsonb
language sql
immutable
security definer set search_path = ''
as $$
  with values as (
    select
      greatest(total_coins, 0) as coins,
      greatest(total_experience, 0) as experience_points,
      public.experience_level(greatest(total_experience, 0)) as level
  )
  select jsonb_build_object(
    'coins', values.coins,
    'experience_points', values.experience_points,
    'level', values.level,
    'experience_to_next_level', greatest(
      0,
      public.experience_threshold(values.level + 1)
        - values.experience_points
    )
  )
  from values;
$$;

-- Grant one challenge ticket for every newly reached level.  This trigger is
-- the server-owned boundary for every XP source, including automatic daily
-- result settlement through apply_coin_transaction.
create or replace function public.grant_level_up_challenge_tickets()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  previous_rewarded_level integer;
  previous_seen_level integer;
  reached_level integer;
  reward_count integer;
  next_ticket_count integer;
begin
  if tg_op = 'INSERT' then
    previous_rewarded_level := 1;
    previous_seen_level := 1;
  else
    previous_rewarded_level := greatest(
      coalesce(old.level_rewarded_through, 1),
      1
    );
    previous_seen_level := greatest(
      coalesce(old.level_celebration_seen_through, 1),
      1
    );
  end if;

  reached_level := public.experience_level(
    greatest(coalesce(new.experience_points, 0), 0)
  );
  reward_count := greatest(reached_level - previous_rewarded_level, 0);
  next_ticket_count := coalesce(new.store_challenge_tickets, 0)
    + reward_count;

  if next_ticket_count > 9999 then
    raise exception 'level-up challenge ticket cap exceeded';
  end if;

  new.store_challenge_tickets := next_ticket_count;
  new.level_rewarded_through := greatest(
    previous_rewarded_level,
    reached_level
  );
  -- A new level is pending until the client explicitly acknowledges its
  -- celebration.  Never let an XP update lower an already seen highwater.
  new.level_celebration_seen_through := previous_seen_level;
  return new;
end;
$$;

revoke all on function public.experience_threshold(integer)
  from public, anon, authenticated, service_role;
revoke all on function public.experience_level(bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.build_player_economy_json(bigint, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.grant_level_up_challenge_tickets()
  from public, anon, authenticated, service_role;

drop trigger if exists profiles_grant_level_up_challenge_tickets
  on public.profiles;
create trigger profiles_grant_level_up_challenge_tickets
before insert or update of experience_points on public.profiles
for each row
execute function public.grant_level_up_challenge_tickets();

-- Replay the unchanged XP value through both the level reward trigger and the
-- existing nickname-color trigger.  This grants only new-curve level deltas
-- and reclassifies every profile's automatic nickname color atomically.
update public.profiles
set experience_points = experience_points;

create or replace function public.get_pending_level_up_reward()
returns jsonb
language plpgsql
stable
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  rewarded_level integer;
  seen_level integer;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select
    greatest(coalesce(profile.level_rewarded_through, 1), 1),
    greatest(coalesce(profile.level_celebration_seen_through, 1), 1)
  into rewarded_level, seen_level
  from public.profiles profile
  where profile.id = current_user_id;

  if rewarded_level is null or rewarded_level <= seen_level then
    return null;
  end if;

  return jsonb_build_object(
    'user_id', current_user_id,
    'from_level', seen_level,
    'to_level', rewarded_level,
    'challenge_tickets', rewarded_level - seen_level
  );
end;
$$;

create or replace function public.acknowledge_level_up_reward(
  through_level integer,
  expected_user_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  rewarded_level integer;
  seen_level integer;
  next_seen_level integer;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if expected_user_id is null or expected_user_id <> current_user_id then
    raise exception 'user mismatch';
  end if;
  if through_level is null or through_level < 1 then
    raise exception 'invalid level reward acknowledgement';
  end if;

  select
    greatest(coalesce(profile.level_rewarded_through, 1), 1),
    greatest(coalesce(profile.level_celebration_seen_through, 1), 1)
  into rewarded_level, seen_level
  from public.profiles profile
  where profile.id = current_user_id
  for update;

  if rewarded_level is null then
    raise exception 'profile not found';
  end if;
  if through_level > rewarded_level then
    raise exception 'invalid level reward acknowledgement';
  end if;

  next_seen_level := greatest(seen_level, through_level);
  update public.profiles profile
  set level_celebration_seen_through = next_seen_level,
      updated_at = now()
  where profile.id = current_user_id;

  if rewarded_level <= next_seen_level then
    return null;
  end if;

  return jsonb_build_object(
    'user_id', current_user_id,
    'from_level', next_seen_level,
    'to_level', rewarded_level,
    'challenge_tickets', rewarded_level - next_seen_level
  );
end;
$$;

revoke all on function public.get_pending_level_up_reward()
  from public, anon;
grant execute on function public.get_pending_level_up_reward()
  to authenticated;
revoke all on function public.acknowledge_level_up_reward(integer, uuid)
  from public, anon;
grant execute on function public.acknowledge_level_up_reward(integer, uuid)
  to authenticated;

-- Keep the established get_today_state guard/settlement chain intact and add
-- the two read-only highwater fields at the outermost response boundary.
alter function public.get_today_state()
rename to get_today_state_before_level_up_rewards;

create function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  state jsonb;
  rewarded_level integer;
  seen_level integer;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  state := public.get_today_state_before_level_up_rewards();
  select
    greatest(coalesce(profile.level_rewarded_through, 1), 1),
    greatest(coalesce(profile.level_celebration_seen_through, 1), 1)
  into rewarded_level, seen_level
  from public.profiles profile
  where profile.id = current_user_id;

  return state || jsonb_build_object(
    'level_rewarded_through', coalesce(rewarded_level, 1),
    'level_celebration_seen_through', coalesce(seen_level, 1)
  );
end;
$$;

revoke all on function public.get_today_state_before_level_up_rewards()
  from public, anon, authenticated, service_role;
revoke all on function public.get_today_state()
  from public, anon, service_role;
grant execute on function public.get_today_state() to authenticated;

comment on function public.experience_threshold(integer) is
  'Returns the cumulative XP threshold for a level under the 100-then-150 curve.';
comment on function public.experience_level(bigint) is
  'Maps cumulative XP to the level reached by the 100-then-150 curve.';
comment on column public.profiles.level_rewarded_through is
  'Highest level whose automatic challenge-ticket reward has been granted.';
comment on column public.profiles.level_celebration_seen_through is
  'Highest level whose client celebration has been acknowledged.';

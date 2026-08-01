begin;

select plan(1);

do $$
declare
  scheduled public.daily_games;
  cycle_value bigint;
  repeated_count integer;
begin
  -- Isolate the scheduler from repository seed data.
  delete from public.attempts where play_date >= date '2099-01-01';
  delete from public.daily_games where play_date >= date '2099-01-01';
  delete from public.daily_game_rotation_entries;
  update public.daily_game_rotation_state
  set current_cycle = 1, updated_at = now()
  where id;

  update public.games set is_active = false;
  insert into public.games (
    id, version, display_name, duration_seconds, is_active, minimum_app_build
  )
  values
    ('rotation_a', 1, 'A', 60, true, 1),
    ('rotation_b', 1, 'B', 60, true, 1),
    ('rotation_c', 1, 'C', 60, true, 1),
    ('rotation_d', 1, 'D', 60, true, 1)
  on conflict (id) do update set
    version = excluded.version,
    display_name = excluded.display_name,
    duration_seconds = excluded.duration_seconds,
    is_active = excluded.is_active,
    minimum_app_build = excluded.minimum_app_build;

  update public.app_runtime_config set minimum_supported_build = 1 where id;

  scheduled := public.ensure_daily_game(date '2099-01-01');
  if scheduled.game_id <> 'rotation_a' then
    raise exception 'expected A first, got %', scheduled.game_id;
  end if;

  scheduled := public.ensure_daily_game(date '2099-01-02');
  if scheduled.game_id <> 'rotation_b' then
    raise exception 'expected B second, got %', scheduled.game_id;
  end if;

  -- New games join after the unfinished C/D entries.
  insert into public.games (
    id, version, display_name, duration_seconds, is_active, minimum_app_build
  )
  values
    ('rotation_e', 1, 'E', 60, true, 1),
    ('rotation_f', 1, 'F', 60, true, 1)
  on conflict (id) do update set is_active = true;

  scheduled := public.ensure_daily_game(date '2099-01-03');
  if scheduled.game_id <> 'rotation_c' then
    raise exception 'expected C before new games, got %', scheduled.game_id;
  end if;
  scheduled := public.ensure_daily_game(date '2099-01-04');
  if scheduled.game_id <> 'rotation_d' then
    raise exception 'expected D before new games, got %', scheduled.game_id;
  end if;
  scheduled := public.ensure_daily_game(date '2099-01-05');
  if scheduled.game_id <> 'rotation_e' then
    raise exception 'expected E fifth, got %', scheduled.game_id;
  end if;
  scheduled := public.ensure_daily_game(date '2099-01-06');
  if scheduled.game_id <> 'rotation_f' then
    raise exception 'expected F sixth, got %', scheduled.game_id;
  end if;

  -- A new cycle contains all six exactly once.
  perform public.ensure_daily_game(date '2099-01-07');
  perform public.ensure_daily_game(date '2099-01-08');
  perform public.ensure_daily_game(date '2099-01-09');
  perform public.ensure_daily_game(date '2099-01-10');
  perform public.ensure_daily_game(date '2099-01-11');
  perform public.ensure_daily_game(date '2099-01-12');

  select count(*) - count(distinct game_id)
  into repeated_count
  from public.daily_games
  where play_date between date '2099-01-07' and date '2099-01-12';

  if repeated_count <> 0 then
    raise exception 'new cycle repeated a game';
  end if;

  select current_cycle into cycle_value
  from public.daily_game_rotation_state where id;
  if cycle_value <> 2 then
    raise exception 'expected cycle 2, got %', cycle_value;
  end if;

  -- Idempotency: asking for an existing date neither changes its game nor
  -- consumes another entry.
  scheduled := public.ensure_daily_game(date '2099-01-12');
  if scheduled.game_id <> (
    select game_id from public.daily_games where play_date = date '2099-01-12'
  ) then
    raise exception 'existing schedule was not preserved';
  end if;

  -- An inactive pending game is skipped, and reactivation appends it to the
  -- current cycle without replaying any already scheduled game.
  update public.games set is_active = false where id = 'rotation_b';
  perform public.ensure_daily_game(date '2099-01-13');
  update public.games set is_active = true where id = 'rotation_b';
  perform public.ensure_daily_game(date '2099-01-14');

  if (
    select count(*) - count(distinct game_id)
    from public.daily_games
    where play_date between date '2099-01-13' and date '2099-01-14'
  ) <> 0 then
    raise exception 'reactivation replayed a scheduled game';
  end if;
end;
$$;

select pass('daily game rotation remains fair and idempotent');
select * from finish();

rollback;

-- Persist daily-game rotation progress instead of recalculating the game from
-- date modulo the current game count. This keeps the unfinished part of a
-- round stable when compatible active games are added or removed.

create table public.daily_game_rotation_state (
  id boolean primary key default true,
  current_cycle bigint not null default 1,
  updated_at timestamptz not null default now(),
  constraint daily_game_rotation_state_singleton check (id),
  constraint daily_game_rotation_cycle_positive check (current_cycle > 0)
);

create table public.daily_game_rotation_entries (
  cycle_no bigint not null,
  game_id text not null references public.games (id),
  position integer not null,
  scheduled_date date,
  created_at timestamptz not null default now(),
  primary key (cycle_no, game_id),
  unique (cycle_no, position),
  unique (scheduled_date),
  constraint daily_game_rotation_entry_cycle_positive check (cycle_no > 0),
  constraint daily_game_rotation_entry_position_positive check (position > 0)
);

create index daily_game_rotation_pending_idx
  on public.daily_game_rotation_entries (cycle_no, position)
  where scheduled_date is null;

alter table public.daily_game_rotation_state enable row level security;
alter table public.daily_game_rotation_entries enable row level security;
revoke all on table public.daily_game_rotation_state from public;
revoke all on table public.daily_game_rotation_entries from public;

insert into public.daily_game_rotation_state (id, current_cycle)
values (true, 1);

-- Treat the two most recently scheduled compatible games as already played in
-- the first persisted cycle. This gives the migration a safe hand-off from the
-- old scheduler without immediately repeating yesterday's game.
with minimum_build as (
  select coalesce(
    (
      select config.minimum_supported_build
      from public.app_runtime_config config
      where config.id
    ),
    1
  ) as value
),
eligible_games as (
  select game.id
  from public.games game
  cross join minimum_build build
  where game.is_active
    and game.minimum_app_build <= build.value
),
latest_two as (
  select daily.play_date, daily.game_id
  from public.daily_games daily
  join eligible_games eligible on eligible.id = daily.game_id
  order by daily.play_date desc
  limit 2
),
recent_games as (
  select game_id, max(play_date) as play_date
  from latest_two
  group by game_id
),
ordered_games as (
  select
    eligible.id as game_id,
    recent.play_date as scheduled_date,
    row_number() over (
      order by
        case when recent.game_id is null then 1 else 0 end,
        recent.play_date nulls last,
        eligible.id
    )::integer as position
  from eligible_games eligible
  left join recent_games recent on recent.game_id = eligible.id
)
insert into public.daily_game_rotation_entries (
  cycle_no,
  game_id,
  position,
  scheduled_date
)
select 1, game_id, position, scheduled_date
from ordered_games;

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
  selected_entry public.daily_game_rotation_entries;
  current_cycle_no bigint;
  next_position integer;
  minimum_build integer;
  last_game_id text;
begin
  -- Every allocator waits on the same transaction lock. The old
  -- INSERT ... ON CONFLICT protected a date, but could still consume the same
  -- rotation entry for two different dates.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('public.ensure_daily_game.rotation')
  );

  select * into existing_schedule
  from public.daily_games
  where play_date = target_date;

  if existing_schedule is not null then
    return existing_schedule;
  end if;

  select coalesce(config.minimum_supported_build, 1)
  into minimum_build
  from public.app_runtime_config config
  where config.id;
  minimum_build := coalesce(minimum_build, 1);

  if not exists (
    select 1
    from public.games game
    where game.is_active
      and game.minimum_app_build <= minimum_build
  ) then
    raise exception 'no compatible active games available';
  end if;

  select state.current_cycle
  into current_cycle_no
  from public.daily_game_rotation_state state
  where state.id
  for update;

  if current_cycle_no is null then
    raise exception 'daily game rotation state is missing';
  end if;

  -- A newly compatible game joins the end of the unfinished current cycle.
  select coalesce(max(entry.position), 0)
  into next_position
  from public.daily_game_rotation_entries entry
  where entry.cycle_no = current_cycle_no;

  insert into public.daily_game_rotation_entries (
    cycle_no,
    game_id,
    position
  )
  select
    current_cycle_no,
    game.id,
    next_position + row_number() over (order by game.id)
  from public.games game
  where game.is_active
    and game.minimum_app_build <= minimum_build
    and not exists (
      select 1
      from public.daily_game_rotation_entries entry
      where entry.cycle_no = current_cycle_no
        and entry.game_id = game.id
    )
  order by game.id;

  select entry.* into selected_entry
  from public.daily_game_rotation_entries entry
  join public.games game on game.id = entry.game_id
  where entry.cycle_no = current_cycle_no
    and entry.scheduled_date is null
    and game.is_active
    and game.minimum_app_build <= minimum_build
  order by entry.position
  limit 1;

  if selected_entry is null then
    select daily.game_id
    into last_game_id
    from public.daily_games daily
    order by daily.play_date desc
    limit 1;

    current_cycle_no := current_cycle_no + 1;

    update public.daily_game_rotation_state
    set current_cycle = current_cycle_no,
        updated_at = now()
    where id;

    -- Start after the last scheduled id in lexical order. This prevents the
    -- same game appearing on both sides of a cycle boundary when at least two
    -- games are eligible, while keeping the order deterministic.
    insert into public.daily_game_rotation_entries (
      cycle_no,
      game_id,
      position
    )
    select
      current_cycle_no,
      game.id,
      row_number() over (
        order by
          case
            when last_game_id is null or game.id > last_game_id then 0
            else 1
          end,
          game.id
      )
    from public.games game
    where game.is_active
      and game.minimum_app_build <= minimum_build;

    select entry.* into selected_entry
    from public.daily_game_rotation_entries entry
    where entry.cycle_no = current_cycle_no
    order by entry.position
    limit 1;
  end if;

  select * into selected_game
  from public.games
  where id = selected_entry.game_id;

  insert into public.daily_games (play_date, game_id, game_version)
  values (target_date, selected_game.id, selected_game.version)
  returning * into existing_schedule;

  update public.daily_game_rotation_entries
  set scheduled_date = target_date
  where cycle_no = selected_entry.cycle_no
    and game_id = selected_entry.game_id;

  return existing_schedule;
end;
$$;

revoke all on function public.ensure_daily_game(date) from public;


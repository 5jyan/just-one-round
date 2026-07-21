create extension if not exists pgcrypto;

create type public.profile_gender as enum (
  'female',
  'male',
  'non_binary',
  'prefer_not_to_say'
);

create type public.attempt_status as enum (
  'issued',
  'submitted',
  'expired'
);

create type public.attempt_grant_type as enum (
  'daily',
  'rewarded_ad'
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text,
  birth_decade smallint,
  gender public.profile_gender,
  region_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_nickname_length
    check (nickname is null or char_length(nickname) between 2 and 16),
  constraint profiles_birth_decade_range
    check (birth_decade is null or birth_decade between 1920 and 2020),
  constraint profiles_region_code_format
    check (region_code is null or region_code ~ '^[A-Z]{2}$')
);

create table public.games (
  id text primary key,
  version integer not null default 1,
  display_name text not null,
  description text not null default '',
  duration_seconds smallint not null default 60,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint games_id_format check (id ~ '^[a-z0-9_]+$'),
  constraint games_version_positive check (version > 0),
  constraint games_duration_range check (duration_seconds between 10 and 180)
);

create table public.daily_games (
  play_date date primary key,
  game_id text not null references public.games (id),
  game_version integer not null,
  created_at timestamptz not null default now(),
  constraint daily_games_version_positive check (game_version > 0)
);

create table public.attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  play_date date not null,
  game_id text not null references public.games (id),
  game_version integer not null,
  ordinal smallint not null,
  grant_type public.attempt_grant_type not null,
  status public.attempt_status not null default 'issued',
  issued_at timestamptz not null default now(),
  submitted_at timestamptz,
  constraint attempts_ordinal_range check (ordinal between 1 and 2),
  constraint attempts_grant_matches_ordinal check (
    (ordinal = 1 and grant_type = 'daily') or
    (ordinal = 2 and grant_type = 'rewarded_ad')
  ),
  unique (user_id, play_date, ordinal)
);

create table public.scores (
  attempt_id uuid primary key references public.attempts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  play_date date not null,
  game_id text not null references public.games (id),
  game_version integer not null,
  raw_score bigint not null,
  duration_ms integer not null,
  submitted_at timestamptz not null default now(),
  constraint scores_raw_score_non_negative check (raw_score >= 0),
  constraint scores_duration_range check (duration_ms between 0 and 180000)
);

create index attempts_user_date_idx
  on public.attempts (user_id, play_date desc);

create index scores_daily_rank_idx
  on public.scores (play_date, game_id, raw_score desc, submitted_at asc);

create index scores_user_history_idx
  on public.scores (user_id, play_date desc);

alter table public.profiles enable row level security;
alter table public.games enable row level security;
alter table public.daily_games enable row level security;
alter table public.attempts enable row level security;
alter table public.scores enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = id);

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "games_read_active"
  on public.games for select
  to anon, authenticated
  using (is_active);

create policy "daily_games_read"
  on public.daily_games for select
  to anon, authenticated
  using (true);

create policy "attempts_select_own"
  on public.attempts for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "scores_select_own"
  on public.scores for select
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.claim_daily_attempt()
returns public.attempts
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  scheduled_game public.daily_games;
  claimed_attempt public.attempts;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into scheduled_game
  from public.daily_games
  where play_date = seoul_date;

  if scheduled_game is null then
    raise exception 'no game scheduled for today';
  end if;

  insert into public.attempts (
    user_id,
    play_date,
    game_id,
    game_version,
    ordinal,
    grant_type
  ) values (
    current_user_id,
    seoul_date,
    scheduled_game.game_id,
    scheduled_game.game_version,
    1,
    'daily'
  )
  on conflict (user_id, play_date, ordinal)
  do update set user_id = excluded.user_id
  returning * into claimed_attempt;

  return claimed_attempt;
end;
$$;

revoke all on function public.claim_daily_attempt() from public;
grant execute on function public.claim_daily_attempt() to authenticated;

grant select on public.games to anon, authenticated;
grant select on public.daily_games to anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.attempts to authenticated;
grant select on public.scores to authenticated;

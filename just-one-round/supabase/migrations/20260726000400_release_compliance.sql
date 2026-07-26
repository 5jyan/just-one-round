alter table public.profiles
  add column terms_version text,
  add column privacy_version text,
  add column age_confirmed_at timestamptz,
  add column legal_accepted_at timestamptz;

create table public.blocked_profiles (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocked_profiles_not_self check (blocker_id <> blocked_id)
);

create table public.nickname_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete cascade,
  reported_user_id uuid not null references auth.users (id) on delete cascade,
  nickname_snapshot text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  constraint nickname_reports_not_self check (reporter_id <> reported_user_id),
  constraint nickname_reports_status check (
    status in ('pending', 'actioned', 'dismissed')
  )
);

create unique index nickname_reports_open_unique_idx
  on public.nickname_reports (reporter_id, reported_user_id, nickname_snapshot)
  where status = 'pending';

alter table public.blocked_profiles enable row level security;
alter table public.nickname_reports enable row level security;

create policy "blocked_profiles_select_own"
  on public.blocked_profiles for select
  to authenticated
  using (blocker_id = (select auth.uid()));

create policy "nickname_reports_select_own"
  on public.nickname_reports for select
  to authenticated
  using (reporter_id = (select auth.uid()));

revoke all on table public.blocked_profiles from public;
revoke all on table public.nickname_reports from public;

create function public.accept_legal_documents(
  accepted_terms_version text,
  accepted_privacy_version text
)
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;
  if accepted_terms_version <> '2026-07-26-v1'
     or accepted_privacy_version <> '2026-07-26-v1' then
    raise exception 'unsupported legal document version';
  end if;

  update public.profiles
  set
    terms_version = accepted_terms_version,
    privacy_version = accepted_privacy_version,
    age_confirmed_at = coalesce(age_confirmed_at, now()),
    legal_accepted_at = now(),
    updated_at = now()
  where id = (select auth.uid());
end;
$$;

create function public.report_nickname(reported_user_id uuid)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  target_nickname text;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;
  if reported_user_id = (select auth.uid()) then
    raise exception 'cannot report yourself';
  end if;

  select nickname into target_nickname
  from public.profiles
  where id = reported_user_id;

  if target_nickname is null then
    raise exception 'reportable nickname not found';
  end if;

  insert into public.nickname_reports (
    reporter_id,
    reported_user_id,
    nickname_snapshot
  ) values (
    (select auth.uid()),
    reported_user_id,
    target_nickname
  )
  on conflict do nothing;
end;
$$;

create function public.block_user(blocked_user_id uuid)
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;
  if blocked_user_id = (select auth.uid()) then
    raise exception 'cannot block yourself';
  end if;
  if not exists (select 1 from public.profiles where id = blocked_user_id) then
    raise exception 'user not found';
  end if;

  insert into public.blocked_profiles (blocker_id, blocked_id)
  values ((select auth.uid()), blocked_user_id)
  on conflict do nothing;
end;
$$;

create or replace function public.set_my_nickname(new_nickname text)
returns public.profiles
language plpgsql
security definer set search_path = ''
as $$
declare
  normalized_nickname text := btrim(new_nickname);
  compact_nickname text;
  updated_profile public.profiles;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  if char_length(normalized_nickname) not between 2 and 12 then
    raise exception 'nickname must be between 2 and 12 characters';
  end if;
  if normalized_nickname ~ '[[:cntrl:]]' then
    raise exception 'nickname contains invalid characters';
  end if;

  compact_nickname := lower(
    regexp_replace(normalized_nickname, '[[:space:]._-]+', '', 'g')
  );
  if compact_nickname ~ '(시발|씨발|ㅅㅂ|병신|개새끼|좆|섹스|sex|fuck|nigger)' then
    raise exception 'nickname contains blocked language';
  end if;
  if normalized_nickname ~* '(https?://|www\.|@)'
     or normalized_nickname ~ '01[016789][[:space:]-]?[0-9]{3,4}[[:space:]-]?[0-9]{4}'
     or normalized_nickname ~ '(.)\1{4,}' then
    raise exception 'nickname contains contact or spam content';
  end if;

  begin
    update public.profiles
    set nickname = normalized_nickname, updated_at = now()
    where id = (select auth.uid())
    returning * into updated_profile;
  exception when unique_violation then
    raise exception 'nickname already taken' using errcode = '23505';
  end;

  return updated_profile;
end;
$$;

update public.profiles
set nickname = null, updated_at = now()
where lower(regexp_replace(nickname, '[[:space:]._-]+', '', 'g'))
  ~ '(시발|씨발|ㅅㅂ|병신|개새끼|좆|섹스|sex|fuck|nigger)';

drop function if exists public.enable_my_test_account();

revoke all on function public.accept_legal_documents(text, text) from public;
revoke all on function public.report_nickname(uuid) from public;
revoke all on function public.block_user(uuid) from public;
grant execute on function public.accept_legal_documents(text, text) to authenticated;
grant execute on function public.report_nickname(uuid) to authenticated;
grant execute on function public.block_user(uuid) to authenticated;

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
      and (filter_birth_decade is null or p.birth_decade = filter_birth_decade)
      and (filter_gender is null or p.gender = filter_gender)
      and not exists (
        select 1
        from public.blocked_profiles blocked
        where blocked.blocker_id = (select auth.uid())
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
    'best_score', (select raw_score from ranked where rank = 1),
    'nearby', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'rank', neighbors.rank,
          'user_id', neighbors.user_id,
          'nickname', coalesce(neighbors.nickname, '이름 미설정'),
          'score', neighbors.raw_score,
          'is_me', coalesce(neighbors.user_id = (select auth.uid()), false),
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
          'is_me', coalesce(leaders.user_id = (select auth.uid()), false),
          'is_npc', leaders.is_npc
        ) order by leaders.rank
      )
      from ranked leaders
      where leaders.rank <= 50
    ), '[]'::jsonb)
  ));
end;
$$;

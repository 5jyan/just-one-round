alter table public.profiles
  drop constraint profiles_nickname_length,
  add constraint profiles_nickname_length
    check (nickname is null or char_length(nickname) between 2 and 12);

create unique index profiles_nickname_unique_idx
  on public.profiles (lower(nickname))
  where nickname is not null;

create or replace function public.set_my_nickname(new_nickname text)
returns public.profiles
language plpgsql
security definer set search_path = ''
as $$
declare
  normalized_nickname text := btrim(new_nickname);
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

create or replace function public.update_my_demographics(
  new_birth_decade smallint,
  new_gender public.profile_gender
)
returns public.profiles
language plpgsql
security definer set search_path = ''
as $$
declare
  updated_profile public.profiles;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  update public.profiles
  set
    birth_decade = new_birth_decade,
    gender = new_gender,
    updated_at = now()
  where id = (select auth.uid())
  returning * into updated_profile;

  return updated_profile;
end;
$$;

create or replace function public.get_filtered_daily_result(
  target_date date default null,
  filter_birth_decade smallint default null,
  filter_gender public.profile_gender default null
)
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
      s.submitted_at,
      p.nickname
    from public.scores s
    join public.profiles p on p.id = s.user_id
    cross join requested r
    where s.play_date = r.play_date
      and (filter_birth_decade is null or p.birth_decade = filter_birth_decade)
      and (filter_gender is null or p.gender = filter_gender)
    order by s.user_id, s.raw_score desc, s.submitted_at asc
  ),
  ranked as (
    select
      user_id,
      nickname,
      raw_score,
      row_number() over (order by raw_score desc, submitted_at asc) as rank,
      count(*) over () as participants
    from best_per_user
  ),
  mine as (
    select * from ranked where user_id = (select auth.uid())
  ),
  bounds as (
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
    'participants', coalesce((select participants from mine), (select count(*) from ranked)),
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
    'nearby', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'rank', neighbors.rank,
          'nickname', coalesce(neighbors.nickname, '이름 미설정'),
          'score', neighbors.raw_score,
          'is_me', neighbors.user_id = (select auth.uid())
        ) order by neighbors.rank
      )
      from ranked neighbors, bounds b
      where neighbors.rank between b.first_rank and b.last_rank
    ), '[]'::jsonb)
  );
$$;

create or replace function public.get_my_daily_result(target_date date default null)
returns jsonb
language sql
security definer set search_path = ''
stable
as $$
  select public.get_filtered_daily_result(target_date, null, null);
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
  ),
  my_profile as (
    select nickname, birth_decade, gender
    from public.profiles
    where id = (select auth.uid())
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
    'profile', (select jsonb_build_object(
      'nickname', nickname,
      'birth_decade', birth_decade,
      'gender', gender
    ) from my_profile),
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

revoke all on function public.set_my_nickname(text) from public;
revoke all on function public.update_my_demographics(smallint, public.profile_gender) from public;
revoke all on function public.get_filtered_daily_result(date, smallint, public.profile_gender) from public;

grant execute on function public.set_my_nickname(text) to authenticated;
grant execute on function public.update_my_demographics(smallint, public.profile_gender) to authenticated;
grant execute on function public.get_filtered_daily_result(date, smallint, public.profile_gender) to authenticated;

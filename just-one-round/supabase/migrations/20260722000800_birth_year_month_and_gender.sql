alter table public.profiles
  add column birth_year smallint,
  add column birth_month smallint,
  add constraint profiles_birth_year_range
    check (birth_year is null or birth_year between 1900 and 2100),
  add constraint profiles_birth_month_range
    check (birth_month is null or birth_month between 1 and 12),
  add constraint profiles_birth_year_month_pair
    check ((birth_year is null) = (birth_month is null));

-- Values that are no longer offered are treated as "입력하지 않음".
update public.profiles
set gender = null
where gender::text in ('non_binary', 'prefer_not_to_say');

alter table public.profiles
  add constraint profiles_gender_supported
    check (
      gender is null or
      gender in ('male'::public.profile_gender, 'female'::public.profile_gender)
    );

drop function public.update_my_demographics(smallint, public.profile_gender);

create function public.update_my_demographics(
  new_birth_year smallint,
  new_birth_month smallint,
  new_gender public.profile_gender
)
returns public.profiles
language plpgsql
security definer set search_path = ''
as $$
declare
  today_in_seoul date := (now() at time zone 'Asia/Seoul')::date;
  updated_profile public.profiles;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  if (new_birth_year is null) <> (new_birth_month is null) then
    raise exception 'birth year and month must both be provided or omitted';
  end if;

  if new_birth_year is not null and
     make_date(new_birth_year, new_birth_month, 1) > today_in_seoul then
    raise exception 'birth year and month cannot be in the future';
  end if;

  if new_gender::text not in ('male', 'female') then
    raise exception 'unsupported gender';
  end if;

  update public.profiles
  set
    birth_year = new_birth_year,
    birth_month = new_birth_month,
    birth_decade = case
      when new_birth_year is null then null
      else (new_birth_year / 10) * 10
    end,
    gender = new_gender,
    updated_at = now()
  where id = (select auth.uid())
  returning * into updated_profile;

  return updated_profile;
end;
$$;

create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  seoul_date date := (now() at time zone 'Asia/Seoul')::date;
  is_test boolean := false;
begin
  perform public.ensure_daily_game(seoul_date);
  select p.is_test_account into is_test
  from public.profiles p
  where p.id = (select auth.uid());

  return (
    with scheduled as (
      select dg.play_date, g.*
      from public.daily_games dg
      join public.games g on g.id = dg.game_id
      where dg.play_date = seoul_date
    ), my_attempts as (
      select *
      from public.attempts
      where user_id = (select auth.uid()) and play_date = seoul_date
    ), my_profile as (
      select nickname, birth_year, birth_month, gender
      from public.profiles
      where id = (select auth.uid())
    )
    select jsonb_build_object(
      'play_date', seoul_date,
      'game', (select jsonb_build_object(
        'id', id,
        'version', version,
        'display_name', display_name,
        'description', description,
        'duration_seconds', duration_seconds
      ) from scheduled),
      'profile', (select jsonb_build_object(
        'nickname', nickname,
        'birth_year', birth_year,
        'birth_month', birth_month,
        'gender', gender
      ) from my_profile),
      'attempts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'ordinal', ordinal,
        'status', status,
        'grant_type', grant_type
      ) order by ordinal) from my_attempts), '[]'::jsonb),
      'test_mode', coalesce(is_test, false),
      'ad_attempt_available', false,
      'result', public.get_my_daily_result(seoul_date)
    )
  );
end;
$$;

revoke all on function public.update_my_demographics(
  smallint,
  smallint,
  public.profile_gender
) from public;
grant execute on function public.update_my_demographics(
  smallint,
  smallint,
  public.profile_gender
) to authenticated;

-- Order nonplayer profiles by experience first, then UUID.  Each request
-- resolves the cursor profile's current experience so changing the order
-- from UUID-only does not restart pagination when the cursor is present.
create or replace function public.get_daily_nonplayers(
  target_date date,
  target_game_id text,
  after_user_id uuid default null,
  page_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  requested_limit integer := least(
    greatest(coalesce(page_limit, 50), 1),
    100
  );
  anchor_experience_points bigint;
  result jsonb;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if after_user_id is not null then
    select coalesce(profile.experience_points, 0)
    into anchor_experience_points
    from public.profiles profile
    where profile.id = after_user_id;

    if not found then
      raise exception 'invalid cursor';
    end if;
  end if;

  with played_users as (
    select distinct session.user_id
    from public.daily_play_sessions session
    where session.started_at is not null
      and session.game_id = target_game_id
      and coalesce(session.target_game_date, session.play_date) = target_date
    union
    select distinct score.user_id
    from public.scores score
    where score.play_date = target_date
      and score.game_id = target_game_id
  ), candidates as (
    select
      profile.id as user_id,
      btrim(profile.nickname) as nickname,
      coalesce(profile.nickname_color, 'default') as nickname_color,
      public.experience_level(coalesce(profile.experience_points, 0)) as level,
      coalesce(profile.experience_points, 0) as experience_points
    from public.profiles profile
    where profile.id <> current_user_id
      and not coalesce(profile.is_test_account, false)
      and profile.nickname is not null
      and btrim(profile.nickname) <> ''
      and btrim(profile.nickname) !~ '^신원미상#[0-9]+$'
      and not exists (
        select 1
        from public.blocked_profiles blocked
        where blocked.blocker_id = current_user_id
          and blocked.blocked_id = profile.id
      )
      and not exists (
        select 1
        from played_users played
        where played.user_id = profile.id
      )
      and (
        after_user_id is null
        or coalesce(profile.experience_points, 0) < anchor_experience_points
        or (
          coalesce(profile.experience_points, 0) = anchor_experience_points
          and profile.id > after_user_id
        )
      )
    order by experience_points desc, profile.id
    limit requested_limit + 1
  ), page as (
    select *
    from candidates
    order by experience_points desc, user_id
    limit requested_limit
  )
  select jsonb_build_object(
    'players', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'user_id', page.user_id,
          'nickname', page.nickname,
          'nickname_color', page.nickname_color,
          'level', page.level
        ) order by page.experience_points desc, page.user_id
      )
      from page
    ), '[]'::jsonb),
    'next_cursor', case
      when exists (
        select 1
        from candidates
        offset requested_limit
        limit 1
      ) then (
        select last_page.user_id::text
        from page last_page
        order by last_page.experience_points asc, last_page.user_id desc
        limit 1
      )
      else null
    end
  ) into result;

  return result;
end;
$$;

revoke all on function public.get_daily_nonplayers(date, text, uuid, integer)
  from public, anon;
grant execute on function public.get_daily_nonplayers(date, text, uuid, integer)
  to authenticated;

comment on function public.get_daily_nonplayers(date, text, uuid, integer) is
  'Returns nickname-visible nonplayers ordered by current experience and UUID with a cursor.';

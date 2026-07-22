create or replace function public.get_my_play_history(history_limit integer default 30)
returns jsonb
language sql
security definer set search_path = ''
stable
as $$
  with best_per_user_day as (
    select distinct on (s.play_date, s.user_id)
      s.play_date,
      s.user_id,
      s.game_id,
      s.raw_score,
      s.submitted_at
    from public.scores s
    order by
      s.play_date,
      s.user_id,
      s.raw_score desc,
      s.submitted_at asc
  ),
  ranked as (
    select
      b.play_date,
      b.user_id,
      b.game_id,
      b.raw_score,
      row_number() over (
        partition by b.play_date
        order by b.raw_score desc, b.submitted_at asc
      ) as rank,
      count(*) over (partition by b.play_date) as participants
    from best_per_user_day b
  ),
  mine as (
    select
      r.play_date,
      r.game_id,
      g.display_name,
      r.raw_score,
      r.rank,
      r.participants
    from ranked r
    join public.games g on g.id = r.game_id
    where r.user_id = (select auth.uid())
    order by r.play_date desc
    limit least(greatest(history_limit, 1), 100)
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'play_date', play_date,
      'game_id', game_id,
      'display_name', display_name,
      'score', raw_score,
      'rank', rank,
      'participants', participants
    ) order by play_date desc
  ), '[]'::jsonb)
  from mine;
$$;

revoke all on function public.get_my_play_history(integer) from public;
grant execute on function public.get_my_play_history(integer) to authenticated;

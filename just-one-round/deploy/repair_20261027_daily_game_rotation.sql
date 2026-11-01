-- Run in the same transaction as 20261026000100_fair_daily_game_rotation_by_recency.sql.
-- Repair only the not-yet-played cycle that was allocated using lexical order.
select pg_advisory_xact_lock(hashtext('public.ensure_daily_game.rotation'));
lock table public.attempts in share mode;

do $$
begin
  if public.current_play_date() <> date '2026-10-26'
    or (select current_cycle from public.daily_game_rotation_state where id) <> 9
    or (select count(*) from public.daily_games where play_date > date '2026-10-26') <> 1
    or not exists (select 1 from public.daily_games where play_date = date '2026-10-27' and game_id = 'apple_game_v2')
    or exists (select 1 from public.attempts where play_date > date '2026-10-26')
    or exists (select 1 from public.scores where play_date > date '2026-10-26')
    or exists (select 1 from public.daily_game_rotation_entries where cycle_no = 9 and scheduled_date <= date '2026-10-26')
    or (select count(*) from public.daily_game_rotation_entries where cycle_no = 9) <> 13
  then
    raise exception 'rotation repair preconditions changed; refusing to rewrite the schedule';
  end if;
end;
$$;

-- Remember completed schedules so the transaction can prove they are unchanged.
create temporary table rotation_completed_before on commit drop as
select * from public.daily_games where play_date <= date '2026-10-26';

update public.daily_game_rotation_entries
set scheduled_date = null
where cycle_no = 9 and scheduled_date = date '2026-10-27';
delete from public.daily_games where play_date = date '2026-10-27';

create temporary table rotation_new_positions on commit drop as
select entry.game_id,
  row_number() over (order by max(daily.play_date) asc nulls first, entry.game_id)::integer as position
from public.daily_game_rotation_entries entry
left join public.daily_games daily on daily.game_id = entry.game_id
where entry.cycle_no = 9
group by entry.game_id;

-- Move to free positions first to preserve the immediate unique constraint.
update public.daily_game_rotation_entries entry
set position = new.position + 1000
from rotation_new_positions new
where entry.cycle_no = 9 and entry.game_id = new.game_id;
update public.daily_game_rotation_entries entry
set position = new.position
from rotation_new_positions new
where entry.cycle_no = 9 and entry.game_id = new.game_id;

select public.ensure_daily_game(date '2026-10-27');

do $$
begin
  if not exists (select 1 from public.daily_games where play_date = date '2026-10-27' and game_id = 'beat_the_dealer')
    or exists (
      (select * from rotation_completed_before except select * from public.daily_games where play_date <= date '2026-10-26')
      union all
      (select * from public.daily_games where play_date <= date '2026-10-26' except select * from rotation_completed_before)
    )
    or (select position from public.daily_game_rotation_entries where cycle_no = 9 and game_id = 'apple_game_v2') <> 11
  then
    raise exception 'rotation repair verification failed';
  end if;
end;
$$;

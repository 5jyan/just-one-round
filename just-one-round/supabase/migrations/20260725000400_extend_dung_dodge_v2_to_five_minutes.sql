alter table public.games
  drop constraint games_duration_range;

alter table public.games
  add constraint games_duration_range
    check (duration_seconds between 10 and 300);

update public.games
set duration_seconds = 300
where id = 'dung_dodge_v2';

-- The optional second challenge is a true retry: once it starts, the first
-- challenge score is removed and the next completed result becomes the day's
-- only ranked score.

create or replace function public.discard_previous_daily_challenge_score()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  if new.play_mode = 'challenge'
    and new.entitlement_source in ('rewarded_ad', 'store_ticket')
    and new.ordinal > 1 then
    delete from public.scores score
    where score.user_id = new.user_id
      and score.play_date = new.play_date;
  end if;
  return new;
end;
$$;

revoke all on function public.discard_previous_daily_challenge_score()
  from public, anon, authenticated, service_role;

drop trigger if exists daily_play_sessions_replace_score_before_extra_insert
  on public.daily_play_sessions;

create trigger daily_play_sessions_replace_score_before_extra_insert
before insert on public.daily_play_sessions
for each row
execute function public.discard_previous_daily_challenge_score();

comment on function public.discard_previous_daily_challenge_score() is
  'Deletes the previous daily ranked score when an optional extra challenge starts.';

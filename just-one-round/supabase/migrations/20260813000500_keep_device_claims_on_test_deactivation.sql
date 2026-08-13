-- Keep device-level daily limits intact on test-mode deactivation. Only
-- tester attempts that are not linked to a real daily play session are safe
-- to clear automatically.
create or replace function public.deactivate_test_mode()
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if not exists (
    select 1
    from public.profiles profile
    where profile.id = current_user_id
      and profile.is_test_account
  ) then
    raise exception 'test account required';
  end if;

  delete from public.attempts attempt
  where attempt.user_id = current_user_id
    and attempt.play_date = play_day
    and not exists (
      select 1
      from public.daily_play_sessions session
      where session.attempt_id = attempt.id
    );

  update public.profiles
  set
    is_test_account = false,
    test_game_id = null,
    updated_at = now()
  where id = current_user_id;
end;
$$;

revoke all on function public.deactivate_test_mode() from public;
grant execute on function public.deactivate_test_mode() to authenticated;

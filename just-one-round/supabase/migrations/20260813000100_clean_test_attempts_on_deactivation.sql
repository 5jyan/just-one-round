-- Test-mode attempts use the normal attempts table so the existing gameplay
-- and score paths can be exercised, but unlike real ranked challenges they
-- are not linked from daily_play_sessions. Remove only those tester-only
-- attempts when returning to normal mode. Otherwise an orphaned ordinal 1
-- can collide with the first real challenge claimed later the same day.
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

  -- A real challenge is referenced by daily_play_sessions. Test-mode
  -- attempts are deliberately unreferenced, so this preserves any genuine
  -- play made before test mode was activated while clearing tester residue.
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

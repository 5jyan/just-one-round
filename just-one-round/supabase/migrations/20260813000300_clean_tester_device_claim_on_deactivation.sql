-- A developer may switch identities on the same physical installation while
-- testing. The device-level daily claim is intentionally account-independent,
-- so a claim left by the previous identity can block the restored main
-- account even when that account has no play session. Test-mode deactivation
-- is privileged, so clear this orphan only when the restored account has no
-- real session for the play day.
create or replace function public.deactivate_test_mode()
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  play_day date := public.current_play_date();
  device_key text := public.current_device_hash();
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

  if device_key is not null and not exists (
    select 1
    from public.daily_play_sessions session
    where session.user_id = current_user_id
      and session.play_date = play_day
  ) then
    delete from public.device_daily_claims claim
    where claim.device_hash = device_key
      and claim.play_date = play_day;
  end if;

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

-- One-time repair for the affected main account, which had already left test
-- mode before the cleanup above was deployed. The session guard preserves a
-- legitimate claim if the account managed to start a real play meanwhile.
delete from public.device_daily_claims claim
using public.device_installations installation
where installation.device_hash = claim.device_hash
  and installation.user_id = '5545de67-4a30-481c-b568-783d64cff230'::uuid
  and claim.play_date = public.current_play_date()
  and not exists (
    select 1
    from public.daily_play_sessions session
    where session.user_id = installation.user_id
      and session.play_date = claim.play_date
  );

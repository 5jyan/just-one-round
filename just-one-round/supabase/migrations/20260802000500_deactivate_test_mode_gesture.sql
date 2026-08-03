-- Let a tester return this same authenticated profile to normal play mode
-- through the seven-tap version gesture, without exposing profile updates.
create function public.deactivate_test_mode()
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  update public.profiles
  set
    is_test_account = false,
    test_game_id = null,
    updated_at = now()
  where id = current_user_id;

  if not found then
    raise exception 'profile not found';
  end if;
end;
$$;

revoke all on function public.deactivate_test_mode() from public;
grant execute on function public.deactivate_test_mode() to authenticated;

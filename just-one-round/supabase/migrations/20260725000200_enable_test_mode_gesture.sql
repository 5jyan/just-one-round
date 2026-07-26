create function public.enable_my_test_account()
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
  set is_test_account = true, updated_at = now()
  where id = current_user_id;

  if not found then
    raise exception 'profile not found';
  end if;
end;
$$;

revoke all on function public.enable_my_test_account() from public;
grant execute on function public.enable_my_test_account() to authenticated;

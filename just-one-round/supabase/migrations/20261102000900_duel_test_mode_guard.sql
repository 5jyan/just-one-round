-- A profile cannot cross the test/normal isolation boundary while a duel is
-- open; finish or cancel the duel before changing the account mode.
create function public.guard_duel_test_mode_change()
returns trigger language plpgsql security definer set search_path = '' as $function$
begin
  if old.is_test_account is distinct from new.is_test_account and exists (
    select 1 from public.duel_matches m
    where old.id in (m.requester_id,m.opponent_id)
      and m.status in ('waiting','starting','playing')
  ) then
    raise exception 'finish or cancel the active duel before changing test mode';
  end if;
  return new;
end;
$function$;
revoke all on function public.guard_duel_test_mode_change() from public, anon, authenticated;
create trigger guard_duel_test_mode_change before update of is_test_account on public.profiles
  for each row execute function public.guard_duel_test_mode_change();

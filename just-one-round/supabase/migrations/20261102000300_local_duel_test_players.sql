-- Local-only test account picker. It never broadens the normal social/ranking
-- player list: non-test callers and production-default environments receive
-- an empty list.
create or replace function public.get_duel_test_players()
returns jsonb
language plpgsql
security definer set search_path = ''
stable
as $function$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if not exists (
    select 1
    from public.profiles profile
    where profile.id = current_user_id
      and profile.is_test_account
  ) or not exists (
    select 1
    from public.app_runtime_config config
    where config.id and config.local_duel_test_enabled
  ) then
    return '[]'::jsonb;
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', profile.id,
      'nickname', coalesce(nullif(btrim(profile.nickname), ''), '테스트 상대'),
      'test_game_id', profile.test_game_id
    ) order by profile.nickname nulls last, profile.id), '[]'::jsonb)
    from public.profiles profile
    where profile.is_test_account
      and profile.id <> current_user_id
  );
end;
$function$;

revoke all on function public.get_duel_test_players()
  from public, anon;
grant execute on function public.get_duel_test_players() to authenticated;

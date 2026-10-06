create or replace function public.set_my_nickname_color(new_color text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := (select auth.uid());
  updated public.profiles;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if new_color not in ('coral', 'mint', 'sky', 'violet', 'pink') then
    raise exception 'invalid nickname color';
  end if;

  update public.profiles
  set
    nickname_color = new_color,
    store_nickname_color_tickets = store_nickname_color_tickets - 1,
    updated_at = now()
  where id = current_user_id
    and nickname_color <> new_color
    and store_nickname_color_tickets > 0
  returning * into updated;

  if updated.id is null then
    raise exception 'nickname color ticket is not available';
  end if;

  return jsonb_build_object(
    'nickname_color', updated.nickname_color,
    'nickname_color_tickets', updated.store_nickname_color_tickets
  );
end; $$;

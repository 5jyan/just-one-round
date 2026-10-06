create or replace function public.purchase_nickname_color(
  new_color text,
  purchase_request_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  existing_purchase public.shop_purchases;
  transaction_result jsonb;
  updated_profile public.profiles;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if purchase_request_id is null then
    raise exception 'purchase request id required';
  end if;
  if new_color not in ('coral', 'mint', 'sky', 'violet', 'pink') then
    raise exception 'invalid nickname color';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext('ticket-shop')
  );

  select * into existing_purchase
  from public.shop_purchases purchase
  where purchase.user_id = current_user_id
    and purchase.request_id = purchase_request_id;

  if existing_purchase.id is not null then
    if existing_purchase.item_id <> 'nickname_color_ticket' then
      raise exception 'purchase request mismatch';
    end if;
    select * into updated_profile
    from public.profiles profile
    where profile.id = current_user_id;
    return public.build_player_economy_json(
      updated_profile.coin_balance,
      updated_profile.experience_points
    ) || jsonb_build_object(
      'item_id', existing_purchase.item_id,
      'quantity', existing_purchase.quantity,
      'coins_spent', existing_purchase.coins_spent,
      'practice_tickets', updated_profile.store_practice_tickets,
      'challenge_tickets', updated_profile.store_challenge_tickets,
      'nickname_color_tickets', updated_profile.store_nickname_color_tickets,
      'nickname_color', updated_profile.nickname_color
    );
  end if;

  select * into updated_profile
  from public.profiles profile
  where profile.id = current_user_id;
  if updated_profile.id is null then
    raise exception 'profile not found';
  end if;
  if updated_profile.nickname_color = new_color then
    raise exception 'nickname color is already selected';
  end if;

  transaction_result := public.apply_coin_transaction(
    current_user_id,
    -300,
    0,
    'shop_purchase',
    'shop:' || purchase_request_id::text,
    null,
    null,
    jsonb_build_object(
      'item_id', 'nickname_color_ticket',
      'quantity', 1,
      'nickname_color', new_color
    )
  );

  update public.profiles profile
  set nickname_color = new_color,
      updated_at = now()
  where profile.id = current_user_id
  returning * into updated_profile;

  insert into public.shop_purchases (
    user_id, request_id, item_id, quantity, coins_spent
  ) values (
    current_user_id, purchase_request_id, 'nickname_color_ticket', 1, 300
  );

  return transaction_result || jsonb_build_object(
    'item_id', 'nickname_color_ticket',
    'quantity', 1,
    'coins_spent', 300,
    'practice_tickets', updated_profile.store_practice_tickets,
    'challenge_tickets', updated_profile.store_challenge_tickets,
    'nickname_color_tickets', updated_profile.store_nickname_color_tickets,
    'nickname_color', updated_profile.nickname_color
  );
end;
$$;

revoke all on function public.purchase_nickname_color(text, uuid)
  from public, anon;
grant execute on function public.purchase_nickname_color(text, uuid)
  to authenticated;

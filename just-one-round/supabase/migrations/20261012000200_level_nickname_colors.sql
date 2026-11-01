-- Replace manually purchased nickname colors with level-earned colors.
--
-- This migration keeps the old profile/shop/social columns and response fields
-- so older clients can still decode historical rows.  Existing color tickets
-- are refunded once, then the ticket endpoints reject new color transactions.
-- A rollback must restore the old trigger/functions/constraint separately;
-- refunded coins are intentionally retained because reversing them would need
-- a new, explicitly authorized ledger transaction.

alter table public.profiles
  drop constraint if exists profiles_nickname_color_check;

alter table public.profiles
  add constraint profiles_nickname_color_check
  check (nickname_color in (
    'default',
    'coral',
    'mint',
    'cyan',
    'sky',
    'violet',
    'pink',
    'gold'
  ));

create or replace function public.nickname_color_for_level(player_level integer)
returns text
language sql
immutable
strict
security definer set search_path = ''
as $$
  select case
    when player_level >= 30 then 'gold'
    when player_level >= 25 then 'pink'
    when player_level >= 20 then 'violet'
    when player_level >= 15 then 'sky'
    when player_level >= 10 then 'cyan'
    when player_level >= 5 then 'mint'
    else 'default'
  end;
$$;

revoke all on function public.nickname_color_for_level(integer)
  from public, anon, authenticated, service_role;

create or replace function public.set_level_nickname_color()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  new.nickname_color := public.nickname_color_for_level(
    public.experience_level(coalesce(new.experience_points, 0))
  );
  return new;
end;
$$;

revoke all on function public.set_level_nickname_color()
  from public, anon, authenticated, service_role;

drop trigger if exists profiles_set_level_nickname_color
  on public.profiles;
create trigger profiles_set_level_nickname_color
before insert or update of experience_points, nickname_color
on public.profiles
for each row
execute function public.set_level_nickname_color();

-- Refund every held ticket through the canonical wallet primitive.  The row
-- lock makes the ticket count and refund amount one atomic decision; the fixed
-- reference key makes a retry idempotent per user.  A balance overflow raised
-- by apply_coin_transaction aborts the whole caller transaction.
create or replace function public.refund_nickname_color_tickets()
returns bigint
language plpgsql
security definer set search_path = ''
as $$
declare
  profile_row public.profiles;
  held_count integer;
  refunded_tickets bigint := 0;
begin
  for profile_row in
    select profile.*
    from public.profiles profile
    where profile.store_nickname_color_tickets > 0
    order by profile.id
    for update
  loop
    held_count := profile_row.store_nickname_color_tickets;

    perform public.apply_coin_transaction(
      profile_row.id,
      held_count::bigint * 300,
      0,
      'nickname_color_refund',
      'nickname-color-retirement:20261012',
      null,
      null,
      jsonb_build_object(
        'ticket_count', held_count,
        'unit_price', 300,
        'previous_color', coalesce(profile_row.nickname_color, 'default')
      )
    );

    update public.profiles profile
    set store_nickname_color_tickets = 0,
        updated_at = now()
    where profile.id = profile_row.id
      and profile.store_nickname_color_tickets = held_count;
    if not found then
      raise exception 'nickname color ticket count changed during refund';
    end if;

    refunded_tickets := refunded_tickets + held_count;
  end loop;

  return refunded_tickets;
end;
$$;

revoke all on function public.refund_nickname_color_tickets()
  from public, anon, authenticated;
grant execute on function public.refund_nickname_color_tickets()
  to service_role;

-- Run before the color backfill so refund metadata records the historical
-- color, including legacy coral rows.
do $$
begin
  perform public.refund_nickname_color_tickets();
end;
$$;

update public.profiles profile
set nickname_color = public.nickname_color_for_level(
      public.experience_level(coalesce(profile.experience_points, 0))
    ),
    updated_at = now()
where profile.nickname_color is distinct from public.nickname_color_for_level(
  public.experience_level(coalesce(profile.experience_points, 0))
);

-- Preserve the old RPC signatures for mixed-version clients, but prevent a
-- fresh manual color selection.  Authentication and historical idempotency
-- remain available to old callers without debiting or changing a profile.
create or replace function public.set_my_nickname_color(new_color text)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;
  raise exception 'nickname colors are determined by level';
end;
$$;

revoke all on function public.set_my_nickname_color(text) from public, anon;
grant execute on function public.set_my_nickname_color(text) to authenticated;

create or replace function public.purchase_shop_item(
  item_id text,
  purchase_request_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  price integer;
  existing_purchase public.shop_purchases;
  transaction_result jsonb;
  ticket_profile public.profiles;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if purchase_request_id is null then
    raise exception 'purchase request id required';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text), hashtext('ticket-shop')
  );

  select * into existing_purchase
  from public.shop_purchases purchase
  where purchase.user_id = current_user_id
    and purchase.request_id = purchase_request_id;

  if existing_purchase.id is not null then
    if existing_purchase.item_id <> item_id then
      raise exception 'purchase request mismatch';
    end if;
    select * into ticket_profile
    from public.profiles profile
    where profile.id = current_user_id;
    return public.build_player_economy_json(
      ticket_profile.coin_balance,
      ticket_profile.experience_points
    ) || jsonb_build_object(
      'item_id', existing_purchase.item_id,
      'quantity', existing_purchase.quantity,
      'coins_spent', existing_purchase.coins_spent,
      'practice_tickets', ticket_profile.store_practice_tickets,
      'challenge_tickets', ticket_profile.store_challenge_tickets,
      'nickname_color_tickets', ticket_profile.store_nickname_color_tickets,
      'nickname_change_tickets', ticket_profile.store_nickname_change_tickets
    );
  end if;

  if item_id = 'nickname_color_ticket' then
    raise exception 'nickname color tickets are retired';
  end if;

  price := case item_id
    when 'practice_ticket' then 100
    when 'challenge_ticket' then 250
    when 'nickname_change_ticket' then 500
    else null
  end;
  if price is null then
    raise exception 'unknown shop item';
  end if;

  transaction_result := public.apply_coin_transaction(
    current_user_id,
    -price,
    0,
    'shop_purchase',
    'shop:' || purchase_request_id::text,
    null,
    null,
    jsonb_build_object('item_id', item_id, 'quantity', 1)
  );

  update public.profiles profile
  set
    store_practice_tickets = profile.store_practice_tickets
      + case when item_id = 'practice_ticket' then 1 else 0 end,
    store_challenge_tickets = profile.store_challenge_tickets
      + case when item_id = 'challenge_ticket' then 1 else 0 end,
    store_nickname_change_tickets = profile.store_nickname_change_tickets
      + case when item_id = 'nickname_change_ticket' then 1 else 0 end,
    updated_at = now()
  where profile.id = current_user_id
  returning * into ticket_profile;

  insert into public.shop_purchases (
    user_id, request_id, item_id, quantity, coins_spent
  ) values (
    current_user_id, purchase_request_id, item_id, 1, price
  );

  return transaction_result || jsonb_build_object(
    'item_id', item_id,
    'quantity', 1,
    'coins_spent', price,
    'practice_tickets', ticket_profile.store_practice_tickets,
    'challenge_tickets', ticket_profile.store_challenge_tickets,
    'nickname_color_tickets', ticket_profile.store_nickname_color_tickets,
    'nickname_change_tickets', ticket_profile.store_nickname_change_tickets
  );
end;
$$;

revoke all on function public.purchase_shop_item(text, uuid) from public, anon;
grant execute on function public.purchase_shop_item(text, uuid) to authenticated;

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
  historical_color text;
  updated_profile public.profiles;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if purchase_request_id is null then
    raise exception 'purchase request id required';
  end if;
  if new_color not in (
    'coral', 'mint', 'cyan', 'sky', 'violet', 'pink', 'gold'
  ) then
    raise exception 'invalid nickname color';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text), hashtext('ticket-shop')
  );

  select * into existing_purchase
  from public.shop_purchases purchase
  where purchase.user_id = current_user_id
    and purchase.request_id = purchase_request_id;

  if existing_purchase.id is not null then
    if existing_purchase.item_id <> 'nickname_color_ticket' then
      raise exception 'purchase request mismatch';
    end if;

    select transaction.metadata->>'nickname_color'
      into historical_color
    from public.coin_transactions transaction
    where transaction.user_id = current_user_id
      and transaction.reference_key = 'shop:' || purchase_request_id::text;
    if historical_color is not null and historical_color <> new_color then
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
      'nickname_change_tickets', updated_profile.store_nickname_change_tickets,
      'nickname_color', updated_profile.nickname_color
    );
  end if;

  raise exception 'nickname color purchases are retired';
end;
$$;

revoke all on function public.purchase_nickname_color(text, uuid)
  from public, anon;
grant execute on function public.purchase_nickname_color(text, uuid)
  to authenticated;

create or replace function public.gift_shop_item(
  target_user_id uuid,
  item_id text,
  gift_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
  created public.social_notifications;
  existing_notification public.social_notifications;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  -- Keep this guard before idempotency, locks, inventory debit, and recipient
  -- credit.  Test accounts cannot use a historical replay as a side effect.
  if exists (
    select 1
    from public.profiles profile
    where profile.id = current_user_id
      and coalesce(profile.is_test_account, false)
  ) then
    raise exception 'social gifts unavailable for test accounts';
  end if;

  if target_user_id is null or target_user_id = current_user_id then
    raise exception 'invalid recipient';
  end if;
  if item_id not in (
    'practice_ticket',
    'challenge_ticket',
    'nickname_color_ticket',
    'nickname_change_ticket'
  ) then
    raise exception 'invalid gift item';
  end if;
  if not exists (
    select 1
    from public.profiles
    where id = target_user_id
      and not coalesce(is_test_account, false)
  ) then
    raise exception 'recipient unavailable';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text),
    hashtext('social-gift')
  );

  select * into existing_notification
  from public.social_notifications notification
  where notification.sender_id = current_user_id
    and notification.request_id = gift_request_id;

  if existing_notification.id is not null then
    if existing_notification.recipient_id is distinct from target_user_id
      or existing_notification.action_type is distinct from 'gift'
      or existing_notification.gift_item_id is distinct from item_id then
      raise exception 'gift request mismatch';
    end if;
    return existing_notification.id;
  end if;

  if item_id = 'nickname_color_ticket' then
    raise exception 'nickname color gifts are retired';
  end if;

  update public.profiles
  set
    store_practice_tickets = store_practice_tickets
      - case when item_id = 'practice_ticket' then 1 else 0 end,
    store_challenge_tickets = store_challenge_tickets
      - case when item_id = 'challenge_ticket' then 1 else 0 end,
    store_nickname_change_tickets = store_nickname_change_tickets
      - case when item_id = 'nickname_change_ticket' then 1 else 0 end,
    updated_at = now()
  where id = current_user_id
    and (item_id <> 'practice_ticket' or store_practice_tickets > 0)
    and (item_id <> 'challenge_ticket' or store_challenge_tickets > 0)
    and (item_id <> 'nickname_change_ticket'
      or store_nickname_change_tickets > 0);
  if not found then
    raise exception 'gift item is not available';
  end if;

  update public.profiles
  set
    store_practice_tickets = store_practice_tickets
      + case when item_id = 'practice_ticket' then 1 else 0 end,
    store_challenge_tickets = store_challenge_tickets
      + case when item_id = 'challenge_ticket' then 1 else 0 end,
    store_nickname_change_tickets = store_nickname_change_tickets
      + case when item_id = 'nickname_change_ticket' then 1 else 0 end,
    updated_at = now()
  where id = target_user_id;

  insert into public.social_notifications(
    sender_id,
    recipient_id,
    action_type,
    gift_item_id,
    request_id
  ) values (
    current_user_id,
    target_user_id,
    'gift',
    item_id,
    gift_request_id
  ) returning * into created;

  perform public.enqueue_social_push(created);
  return created.id;
end;
$function$;

revoke all on function public.gift_shop_item(uuid, text, uuid)
  from public, anon;
grant execute on function public.gift_shop_item(uuid, text, uuid)
  to authenticated;

comment on function public.nickname_color_for_level(integer) is
  'Maps public.experience_level output to the automatic nickname color.';
comment on function public.refund_nickname_color_tickets() is
  'One-time service-role refund for retired nickname color tickets.';

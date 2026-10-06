-- Add a persistent 500-coin ticket for changing an existing nickname.
-- The automatically assigned 신원미상#... nickname can still be replaced once
-- for free, so first-time nickname setup remains part of the core experience.

alter table public.profiles
  add column if not exists store_nickname_change_tickets integer not null default 0;

alter table public.profiles
  drop constraint if exists profiles_store_nickname_change_tickets_range;
alter table public.profiles
  add constraint profiles_store_nickname_change_tickets_range
  check (store_nickname_change_tickets between 0 and 9999);

alter table public.shop_purchases
  drop constraint if exists shop_purchases_item_id_check;
alter table public.shop_purchases
  add constraint shop_purchases_item_id_check
  check (item_id in (
    'practice_ticket',
    'challenge_ticket',
    'nickname_color_ticket',
    'nickname_change_ticket'
  ));

alter table public.social_notifications
  drop constraint if exists social_notifications_gift_item_id_check;
alter table public.social_notifications
  add constraint social_notifications_gift_item_id_check
  check (gift_item_id in (
    'practice_ticket',
    'challenge_ticket',
    'nickname_color_ticket',
    'nickname_change_ticket'
  ));

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
  if current_user_id is null then raise exception 'authentication required'; end if;
  if purchase_request_id is null then raise exception 'purchase request id required'; end if;

  price := case item_id
    when 'practice_ticket' then 100
    when 'challenge_ticket' then 250
    when 'nickname_color_ticket' then 300
    when 'nickname_change_ticket' then 500
    else null
  end;
  if price is null then raise exception 'unknown shop item'; end if;

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
    store_nickname_color_tickets = profile.store_nickname_color_tickets
      + case when item_id = 'nickname_color_ticket' then 1 else 0 end,
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
  transaction_result jsonb;
  updated_profile public.profiles;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if purchase_request_id is null then raise exception 'purchase request id required'; end if;
  if new_color not in ('coral', 'mint', 'sky', 'violet', 'pink') then
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

  select * into updated_profile
  from public.profiles profile
  where profile.id = current_user_id;
  if updated_profile.id is null then raise exception 'profile not found'; end if;
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
  set nickname_color = new_color, updated_at = now()
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
    'nickname_change_tickets', updated_profile.store_nickname_change_tickets,
    'nickname_color', updated_profile.nickname_color
  );
end;
$$;

revoke all on function public.purchase_nickname_color(text, uuid)
  from public, anon;
grant execute on function public.purchase_nickname_color(text, uuid)
  to authenticated;

create or replace function public.set_my_nickname(new_nickname text)
returns public.profiles
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  normalized_nickname text := btrim(new_nickname);
  compact_nickname text;
  current_profile public.profiles;
  updated_profile public.profiles;
  requires_change_ticket boolean;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if normalized_nickname is null
     or char_length(normalized_nickname) not between 2 and 12 then
    raise exception 'nickname must be between 2 and 12 characters';
  end if;
  if normalized_nickname ~ '[[:cntrl:]]' then
    raise exception 'nickname contains invalid characters';
  end if;
  if normalized_nickname ~ '^신원미상#[0-9]+$' then
    raise exception 'nickname is reserved';
  end if;

  compact_nickname := lower(
    regexp_replace(normalized_nickname, '[[:space:]._-]+', '', 'g')
  );
  if compact_nickname ~ '(시발|씨발|ㅅㅂ|병신|개새끼|좆|섹스|sex|fuck|nigger)' then
    raise exception 'nickname contains blocked language';
  end if;
  if normalized_nickname ~* '(https?://|www\.|@)'
     or normalized_nickname ~ '01[016789][[:space:]-]?[0-9]{3,4}[[:space:]-]?[0-9]{4}'
     or normalized_nickname ~ '(.)\1{4,}' then
    raise exception 'nickname contains contact or spam content';
  end if;

  select * into current_profile
  from public.profiles profile
  where profile.id = current_user_id
  for update;
  if current_profile.id is null then raise exception 'profile not found'; end if;

  requires_change_ticket := current_profile.nickname is not null
    and current_profile.nickname !~ '^신원미상#[0-9]+$'
    and current_profile.nickname <> normalized_nickname;

  begin
    if requires_change_ticket then
      update public.profiles profile
      set
        nickname = normalized_nickname,
        store_nickname_change_tickets =
          profile.store_nickname_change_tickets - 1,
        updated_at = now()
      where profile.id = current_user_id
        and profile.store_nickname_change_tickets > 0
      returning * into updated_profile;
      if updated_profile.id is null then
        raise exception 'nickname change ticket is not available';
      end if;
    else
      update public.profiles profile
      set nickname = normalized_nickname, updated_at = now()
      where profile.id = current_user_id
      returning * into updated_profile;
    end if;
  exception when unique_violation then
    raise exception 'nickname already taken' using errcode = '23505';
  end;

  return updated_profile;
end;
$$;

revoke all on function public.set_my_nickname(text) from public, anon;
grant execute on function public.set_my_nickname(text) to authenticated;

-- Keep the latest auto-settlement wrapper and add the new inventory field.
create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  state jsonb;
begin
  perform public.auto_claim_expired_daily_result_rewards();
  state := public.get_today_state_before_auto_settlement();
  return state || jsonb_build_object(
    'store_nickname_change_tickets', (
      select profile.store_nickname_change_tickets
      from public.profiles profile
      where profile.id = (select auth.uid())
    )
  );
end;
$$;

revoke all on function public.get_today_state() from public, anon;
grant execute on function public.get_today_state() to authenticated;

create or replace function public.enqueue_social_push(
  target_notification public.social_notifications
)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  sender_name text;
  message_body text;
begin
  select coalesce(nickname, '이름 미설정') into sender_name
  from public.profiles
  where id = target_notification.sender_id;

  message_body := case target_notification.action_type
    when 'poke' then sender_name || '님이 콕 찔렀어요. 이건 못 참죠?'
    when 'boast' then sender_name || '님은 기록 ' ||
      coalesce(target_notification.sender_score::text, '-') || '로 오늘 ' ||
      coalesce(target_notification.sender_rank::text, '-') ||
      '등이에요. 이 기록도 못 넘겠어요?'
    when 'gift' then sender_name || '님이 ' || case target_notification.gift_item_id
      when 'practice_ticket' then '연습권'
      when 'challenge_ticket' then '도전권'
      when 'nickname_color_ticket' then '닉네임 색상권'
      else '닉네임 변경권'
    end || ' 1장을 선물했습니다.'
  end;

  if exists(
    select 1 from public.profiles
    where id = target_notification.recipient_id
      and social_notifications_enabled
  ) then
    insert into public.push_notification_outbox(
      notification_id, recipient_id, title, body, payload
    ) values (
      target_notification.id,
      target_notification.recipient_id,
      '딱한판만',
      message_body,
      jsonb_build_object(
        'schema_version', '1',
        'notification_id', target_notification.id,
        'action_type', target_notification.action_type,
        'destination', 'today_game'
      )
    ) on conflict(notification_id) do nothing;
  end if;
end;
$$;

create or replace function public.gift_shop_item(
  target_user_id uuid,
  item_id text,
  gift_request_id uuid
)
returns uuid
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  created public.social_notifications;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
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
  if not exists(
    select 1 from public.profiles
    where id = target_user_id and not is_test_account
  ) then
    raise exception 'recipient unavailable';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(current_user_id::text), hashtext('social-gift')
  );
  if exists(
    select 1 from public.social_notifications
    where sender_id = current_user_id and request_id = gift_request_id
  ) then
    return (
      select id from public.social_notifications
      where sender_id = current_user_id and request_id = gift_request_id
    );
  end if;

  update public.profiles
  set
    store_practice_tickets = store_practice_tickets
      - case when item_id = 'practice_ticket' then 1 else 0 end,
    store_challenge_tickets = store_challenge_tickets
      - case when item_id = 'challenge_ticket' then 1 else 0 end,
    store_nickname_color_tickets = store_nickname_color_tickets
      - case when item_id = 'nickname_color_ticket' then 1 else 0 end,
    store_nickname_change_tickets = store_nickname_change_tickets
      - case when item_id = 'nickname_change_ticket' then 1 else 0 end,
    updated_at = now()
  where id = current_user_id
    and (item_id <> 'practice_ticket' or store_practice_tickets > 0)
    and (item_id <> 'challenge_ticket' or store_challenge_tickets > 0)
    and (item_id <> 'nickname_color_ticket'
      or store_nickname_color_tickets > 0)
    and (item_id <> 'nickname_change_ticket'
      or store_nickname_change_tickets > 0);
  if not found then raise exception 'gift item is not available'; end if;

  update public.profiles
  set
    store_practice_tickets = store_practice_tickets
      + case when item_id = 'practice_ticket' then 1 else 0 end,
    store_challenge_tickets = store_challenge_tickets
      + case when item_id = 'challenge_ticket' then 1 else 0 end,
    store_nickname_color_tickets = store_nickname_color_tickets
      + case when item_id = 'nickname_color_ticket' then 1 else 0 end,
    store_nickname_change_tickets = store_nickname_change_tickets
      + case when item_id = 'nickname_change_ticket' then 1 else 0 end,
    updated_at = now()
  where id = target_user_id;

  insert into public.social_notifications(
    sender_id, recipient_id, action_type, gift_item_id, request_id
  ) values (
    current_user_id, target_user_id, 'gift', item_id, gift_request_id
  ) returning * into created;

  perform public.enqueue_social_push(created);
  return created.id;
end;
$$;

revoke all on function public.gift_shop_item(uuid, text, uuid) from public, anon;
grant execute on function public.gift_shop_item(uuid, text, uuid) to authenticated;

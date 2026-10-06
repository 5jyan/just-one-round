-- Nickname cosmetics, gifts, social interactions, and a durable push outbox.
-- A remote worker can consume the outbox after APNs/FCM credentials are set.

alter table public.profiles
  add column if not exists nickname_color text not null default 'default'
    check (nickname_color in ('default', 'coral', 'mint', 'sky', 'violet', 'pink')),
  add column if not exists store_nickname_color_tickets integer not null default 0
    check (store_nickname_color_tickets between 0 and 9999),
  add column if not exists social_notifications_enabled boolean not null default true;

alter table public.shop_purchases drop constraint shop_purchases_item_id_check;
alter table public.shop_purchases add constraint shop_purchases_item_id_check
  check (item_id in ('practice_ticket', 'challenge_ticket', 'nickname_color_ticket'));

create or replace function public.purchase_shop_item(item_id text, purchase_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := (select auth.uid());
  price integer;
  existing_purchase public.shop_purchases;
  transaction_result jsonb;
  ticket_profile public.profiles;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if purchase_request_id is null then raise exception 'purchase request id required'; end if;
  price := case item_id when 'practice_ticket' then 100 when 'challenge_ticket' then 250
    when 'nickname_color_ticket' then 300 else null end;
  if price is null then raise exception 'unknown shop item'; end if;
  perform pg_advisory_xact_lock(hashtext(current_user_id::text), hashtext('ticket-shop'));
  select * into existing_purchase from public.shop_purchases purchase
  where purchase.user_id = current_user_id and purchase.request_id = purchase_request_id;
  if existing_purchase.id is not null then
    if existing_purchase.item_id <> item_id then raise exception 'purchase request mismatch'; end if;
    select * into ticket_profile from public.profiles where id = current_user_id;
    return public.build_player_economy_json(ticket_profile.coin_balance, ticket_profile.experience_points)
      || jsonb_build_object('item_id', existing_purchase.item_id, 'quantity', 1,
        'coins_spent', existing_purchase.coins_spent,
        'practice_tickets', ticket_profile.store_practice_tickets,
        'challenge_tickets', ticket_profile.store_challenge_tickets,
        'nickname_color_tickets', ticket_profile.store_nickname_color_tickets);
  end if;
  transaction_result := public.apply_coin_transaction(current_user_id, -price, 0,
    'shop_purchase', 'shop:' || purchase_request_id::text, null, null,
    jsonb_build_object('item_id', item_id, 'quantity', 1));
  update public.profiles profile set
    store_practice_tickets = profile.store_practice_tickets + case when item_id = 'practice_ticket' then 1 else 0 end,
    store_challenge_tickets = profile.store_challenge_tickets + case when item_id = 'challenge_ticket' then 1 else 0 end,
    store_nickname_color_tickets = profile.store_nickname_color_tickets + case when item_id = 'nickname_color_ticket' then 1 else 0 end,
    updated_at = now()
  where profile.id = current_user_id returning * into ticket_profile;
  insert into public.shop_purchases(user_id, request_id, item_id, quantity, coins_spent)
  values(current_user_id, purchase_request_id, item_id, 1, price);
  return transaction_result || jsonb_build_object('item_id', item_id, 'quantity', 1,
    'coins_spent', price, 'practice_tickets', ticket_profile.store_practice_tickets,
    'challenge_tickets', ticket_profile.store_challenge_tickets,
    'nickname_color_tickets', ticket_profile.store_nickname_color_tickets);
end; $$;

create function public.set_my_nickname_color(new_color text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare current_user_id uuid := (select auth.uid()); updated public.profiles;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if new_color not in ('default', 'coral', 'mint', 'sky', 'violet', 'pink') then raise exception 'invalid nickname color'; end if;
  if new_color = 'default' then
    update public.profiles set nickname_color = 'default', updated_at = now()
    where id = current_user_id returning * into updated;
  else
    update public.profiles set nickname_color = new_color,
      store_nickname_color_tickets = store_nickname_color_tickets - 1, updated_at = now()
    where id = current_user_id and nickname_color <> new_color
      and store_nickname_color_tickets > 0 returning * into updated;
    if updated.id is null then raise exception 'nickname color ticket is not available'; end if;
  end if;
  return jsonb_build_object('nickname_color', updated.nickname_color,
    'nickname_color_tickets', updated.store_nickname_color_tickets);
end; $$;

create table public.social_notifications (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  action_type text not null check (action_type in ('poke', 'boast', 'gift')),
  gift_item_id text check (gift_item_id in ('practice_ticket', 'challenge_ticket', 'nickname_color_ticket')),
  sender_rank integer,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  seen_at timestamptz,
  check (sender_id <> recipient_id), unique(sender_id, request_id)
);
create index social_notifications_recipient_unseen_idx
  on public.social_notifications(recipient_id, created_at) where seen_at is null;
alter table public.social_notifications enable row level security;
revoke all on table public.social_notifications from public, anon, authenticated;

create table public.push_device_tokens (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('ios', 'android')), token text not null,
  enabled boolean not null default true, updated_at timestamptz not null default now(), unique(platform, token)
);
alter table public.push_device_tokens enable row level security;
revoke all on table public.push_device_tokens from public, anon, authenticated;

create table public.push_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.social_notifications(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  title text not null, body text not null, payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), sent_at timestamptz,
  attempt_count integer not null default 0, last_error text, unique(notification_id)
);
create index push_notification_outbox_pending_idx on public.push_notification_outbox(created_at) where sent_at is null;
alter table public.push_notification_outbox enable row level security;
revoke all on table public.push_notification_outbox from public, anon, authenticated;
grant select, update on table public.push_notification_outbox to service_role;
grant select, update on table public.push_device_tokens to service_role;

create function public.enqueue_social_push(target_notification public.social_notifications)
returns void language plpgsql security definer set search_path = '' as $$
declare sender_name text; message_body text;
begin
  select coalesce(nickname, '이름 미설정') into sender_name from public.profiles where id = target_notification.sender_id;
  message_body := case target_notification.action_type
    when 'poke' then sender_name || '님이 찔렀습니다.'
    when 'boast' then sender_name || '님이 오늘 ' || target_notification.sender_rank || '등 기록을 자랑했습니다. 도전해 보세요!'
    when 'gift' then sender_name || '님이 ' || case target_notification.gift_item_id
      when 'practice_ticket' then '연습권' when 'challenge_ticket' then '도전권'
      else '닉네임 색상권' end || ' 1장을 선물했습니다.' end;
  if exists(select 1 from public.profiles where id = target_notification.recipient_id and social_notifications_enabled) then
    insert into public.push_notification_outbox(notification_id, recipient_id, title, body, payload)
    values(target_notification.id, target_notification.recipient_id, '딱한판만', message_body,
      jsonb_build_object('notification_id', target_notification.id, 'action_type', target_notification.action_type))
    on conflict(notification_id) do nothing;
  end if;
end; $$;

create function public.send_social_action(target_user_id uuid, social_action text, action_request_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare current_user_id uuid := (select auth.uid()); created public.social_notifications; current_rank integer;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if target_user_id is null or target_user_id = current_user_id then raise exception 'invalid recipient'; end if;
  if social_action not in ('poke', 'boast') then raise exception 'invalid social action'; end if;
  if exists(select 1 from public.social_notifications where sender_id = current_user_id and request_id = action_request_id) then
    return (select id from public.social_notifications where sender_id = current_user_id and request_id = action_request_id);
  end if;
  if not exists(select 1 from public.profiles where id = target_user_id and not is_test_account) then raise exception 'recipient unavailable'; end if;
  if (select count(*) from public.social_notifications where sender_id = current_user_id and created_at >= now() - interval '24 hours') >= 10 then raise exception 'daily social action limit reached'; end if;
  if exists(select 1 from public.social_notifications where sender_id = current_user_id and recipient_id = target_user_id
      and action_type = social_action and created_at >= now() - interval '6 hours') then raise exception 'social action cooldown'; end if;
  if social_action = 'boast' then
    select rank into current_rank from (
      select best.user_id, row_number() over(order by best.raw_score desc, best.submitted_at asc, best.user_id)::integer rank
      from (
        select distinct on (score.user_id) score.user_id, score.raw_score, score.submitted_at
        from public.scores score join public.profiles profile on profile.id = score.user_id
        where score.play_date = public.current_play_date() and not profile.is_test_account
        order by score.user_id, score.raw_score desc, score.submitted_at asc
      ) best
    ) ranked where user_id = current_user_id;
    if current_rank is null then raise exception 'today rank is not available'; end if;
  end if;
  insert into public.social_notifications(sender_id, recipient_id, action_type, sender_rank, request_id)
  values(current_user_id, target_user_id, social_action, current_rank, action_request_id)
  on conflict(sender_id, request_id) do update set request_id = excluded.request_id returning * into created;
  perform public.enqueue_social_push(created); return created.id;
end; $$;

create function public.gift_shop_item(target_user_id uuid, item_id text, gift_request_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare current_user_id uuid := (select auth.uid()); created public.social_notifications;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if target_user_id is null or target_user_id = current_user_id then raise exception 'invalid recipient'; end if;
  if item_id not in ('practice_ticket', 'challenge_ticket', 'nickname_color_ticket') then raise exception 'invalid gift item'; end if;
  if not exists(select 1 from public.profiles where id = target_user_id and not is_test_account) then raise exception 'recipient unavailable'; end if;
  perform pg_advisory_xact_lock(hashtext(current_user_id::text), hashtext('social-gift'));
  if exists(select 1 from public.social_notifications where sender_id = current_user_id and request_id = gift_request_id) then
    return (select id from public.social_notifications where sender_id = current_user_id and request_id = gift_request_id);
  end if;
  update public.profiles set
    store_practice_tickets = store_practice_tickets - case when item_id = 'practice_ticket' then 1 else 0 end,
    store_challenge_tickets = store_challenge_tickets - case when item_id = 'challenge_ticket' then 1 else 0 end,
    store_nickname_color_tickets = store_nickname_color_tickets - case when item_id = 'nickname_color_ticket' then 1 else 0 end,
    updated_at = now() where id = current_user_id
    and (item_id <> 'practice_ticket' or store_practice_tickets > 0)
    and (item_id <> 'challenge_ticket' or store_challenge_tickets > 0)
    and (item_id <> 'nickname_color_ticket' or store_nickname_color_tickets > 0);
  if not found then raise exception 'gift item is not available'; end if;
  update public.profiles set
    store_practice_tickets = store_practice_tickets + case when item_id = 'practice_ticket' then 1 else 0 end,
    store_challenge_tickets = store_challenge_tickets + case when item_id = 'challenge_ticket' then 1 else 0 end,
    store_nickname_color_tickets = store_nickname_color_tickets + case when item_id = 'nickname_color_ticket' then 1 else 0 end,
    updated_at = now() where id = target_user_id;
  insert into public.social_notifications(sender_id, recipient_id, action_type, gift_item_id, request_id)
  values(current_user_id, target_user_id, 'gift', item_id, gift_request_id) returning * into created;
  perform public.enqueue_social_push(created); return created.id;
end; $$;

create function public.get_unseen_social_notifications(notification_limit integer default 10)
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'action_type', n.action_type,
    'gift_item_id', n.gift_item_id, 'sender_nickname', coalesce(p.nickname, '이름 미설정'),
    'sender_rank', n.sender_rank, 'created_at', n.created_at) order by n.created_at), '[]'::jsonb)
  from (select * from public.social_notifications where recipient_id = (select auth.uid()) and seen_at is null
    order by created_at limit least(greatest(notification_limit, 1), 20)) n join public.profiles p on p.id = n.sender_id;
$$;
create function public.acknowledge_social_notifications(notification_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare changed integer; begin
  update public.social_notifications set seen_at = now() where recipient_id = (select auth.uid())
    and id = any(notification_ids) and seen_at is null;
  get diagnostics changed = row_count; return changed;
end; $$;
create function public.register_push_device(device_platform text, device_token text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  if device_platform not in ('ios', 'android') or length(trim(device_token)) < 20 then raise exception 'invalid push device'; end if;
  insert into public.push_device_tokens(user_id, platform, token) values((select auth.uid()), device_platform, trim(device_token))
  on conflict(platform, token) do update set user_id = excluded.user_id, enabled = true, updated_at = now();
end; $$;
create function public.set_social_notifications_enabled(enabled boolean)
returns void language sql security definer set search_path = '' as $$
  update public.profiles set social_notifications_enabled = enabled, updated_at = now() where id = (select auth.uid());
$$;

revoke all on function public.set_my_nickname_color(text), public.send_social_action(uuid,text,uuid),
  public.gift_shop_item(uuid,text,uuid), public.get_unseen_social_notifications(integer),
  public.acknowledge_social_notifications(uuid[]), public.register_push_device(text,text),
  public.set_social_notifications_enabled(boolean) from public, anon;
grant execute on function public.set_my_nickname_color(text), public.send_social_action(uuid,text,uuid),
  public.gift_shop_item(uuid,text,uuid), public.get_unseen_social_notifications(integer),
  public.acknowledge_social_notifications(uuid[]), public.register_push_device(text,text),
  public.set_social_notifications_enabled(boolean) to authenticated;

alter function public.get_today_state() rename to get_today_state_before_nickname_colors;
create function public.get_today_state() returns jsonb language sql security definer set search_path = '' as $$
  select public.get_today_state_before_nickname_colors() || jsonb_build_object(
    'nickname_color', p.nickname_color, 'store_nickname_color_tickets', p.store_nickname_color_tickets,
    'social_notifications_enabled', p.social_notifications_enabled)
  from public.profiles p where p.id = (select auth.uid());
$$;
revoke all on function public.get_today_state_before_nickname_colors() from public, anon, authenticated, service_role;
revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

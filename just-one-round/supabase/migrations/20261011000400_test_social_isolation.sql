-- Keep automated store/test sessions from creating social side effects.
--
-- Test accounts still use the normal game APIs.  This migration only blocks
-- social actions and gifts at the server boundary, before a ticket transfer or
-- notification can be written.  The enqueue guard is a second line of
-- defence for maintenance jobs or older callers that insert a notification
-- directly.

create or replace function public.enqueue_social_push(
  target_notification public.social_notifications
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  sender_name text;
  message_body text;
  formatted_score text;
begin
  -- A test sender or recipient must never create a remotely delivered push.
  -- Keep this check before formatting or inserting into the outbox so direct
  -- calls from old jobs are harmless too.
  if exists (
    select 1
    from public.profiles profile
    where profile.id in (
      target_notification.sender_id,
      target_notification.recipient_id
    )
      and coalesce(profile.is_test_account, false)
  ) then
    return;
  end if;

  select coalesce(nickname, '이름 미설정')
  into sender_name
  from public.profiles
  where id = target_notification.sender_id;

  formatted_score := public.format_social_score(
    target_notification.sender_game_id,
    target_notification.sender_score
  );

  message_body := case target_notification.action_type
    when 'poke' then sender_name || '님이 콕 찔렀어요. 이건 못 참죠?'
    when 'boast' then sender_name || '님은 기록이 '
      || formatted_score
      || '로 오늘 '
      || coalesce(target_notification.sender_rank::text, '-')
      || '등으로 자랑했어요.'
    when 'gift' then sender_name || '님이 ' || case
      when target_notification.gift_item_id = 'practice_ticket' then '연습권'
      when target_notification.gift_item_id = 'challenge_ticket' then '도전권'
      when target_notification.gift_item_id = 'nickname_change_ticket'
        then '닉네임 변경권'
      else '닉네임 색상권'
    end || ' 1장을 선물했습니다.'
  end;

  if exists (
    select 1
    from public.profiles profile
    where profile.id = target_notification.recipient_id
      and not coalesce(profile.is_test_account, false)
      and profile.social_notifications_enabled
  ) then
    insert into public.push_notification_outbox(
      notification_id,
      recipient_id,
      title,
      body,
      payload
    ) values (
      target_notification.id,
      target_notification.recipient_id,
      '딱한판만',
      message_body,
      jsonb_build_object(
        'schema_version', '1',
        'notification_id', target_notification.id,
        'action_type', target_notification.action_type,
        'destination', 'today_game',
        'sender_score_label', formatted_score
      )
    )
    on conflict(notification_id) do nothing;
  end if;
end;
$function$;

create or replace function public.send_social_action(
  target_user_id uuid,
  social_action text,
  action_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
  created public.social_notifications;
  current_rank integer;
  current_score integer;
  current_game_id text;
  today_seoul date := (now() at time zone 'Asia/Seoul')::date;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  -- Check the sender before idempotency, rate-limit reads, or any insert.  A
  -- crawler replay therefore cannot create an in-app notification either.
  if exists (
    select 1
    from public.profiles profile
    where profile.id = current_user_id
      and coalesce(profile.is_test_account, false)
  ) then
    raise exception 'social actions unavailable for test accounts';
  end if;

  if target_user_id is null or target_user_id = current_user_id then
    raise exception 'invalid recipient';
  end if;
  if social_action not in ('poke', 'boast') then
    raise exception 'invalid social action';
  end if;
  if exists (
    select 1
    from public.social_notifications
    where sender_id = current_user_id
      and request_id = action_request_id
  ) then
    return (
      select id
      from public.social_notifications
      where sender_id = current_user_id
        and request_id = action_request_id
    );
  end if;
  if not exists (
    select 1
    from public.profiles
    where id = target_user_id
      and not coalesce(is_test_account, false)
  ) then
    raise exception 'recipient unavailable';
  end if;
  if (
    select count(*)
    from public.social_notifications
    where sender_id = current_user_id
      and created_at >= now() - interval '24 hours'
  ) >= 10 then
    raise exception 'daily social action limit reached';
  end if;
  if (
    select count(*)
    from public.social_notifications
    where sender_id = current_user_id
      and action_type = social_action
      and (created_at at time zone 'Asia/Seoul')::date = today_seoul
  ) >= 3 then
    if social_action = 'poke' then
      raise exception 'daily poke limit reached';
    else
      raise exception 'daily boast limit reached';
    end if;
  end if;
  if social_action <> 'poke' and exists (
    select 1
    from public.social_notifications
    where sender_id = current_user_id
      and recipient_id = target_user_id
      and action_type = social_action
      and created_at >= now() - interval '6 hours'
  ) then
    raise exception 'social action cooldown';
  end if;
  if social_action = 'boast' then
    select ranked.rank, ranked.raw_score, ranked.game_id
      into current_rank, current_score, current_game_id
    from (
      select best.user_id, best.raw_score, best.game_id,
        row_number() over (
          order by best.raw_score desc, best.submitted_at asc, best.user_id
        )::integer rank
      from (
        select distinct on (score.user_id)
          score.user_id, score.raw_score, score.game_id, score.submitted_at
        from public.scores score
        join public.profiles profile on profile.id = score.user_id
        where score.play_date = public.current_play_date()
          and not profile.is_test_account
        order by score.user_id, score.raw_score desc, score.submitted_at asc
      ) best
    ) ranked
    where ranked.user_id = current_user_id;
    if current_rank is null then
      raise exception 'today rank is not available';
    end if;
  end if;
  insert into public.social_notifications(
    sender_id,
    recipient_id,
    action_type,
    sender_rank,
    sender_score,
    sender_game_id,
    request_id
  )
  values (
    current_user_id,
    target_user_id,
    social_action,
    current_rank,
    current_score,
    current_game_id,
    action_request_id
  )
  on conflict(sender_id, request_id)
  do update set request_id = excluded.request_id
  returning * into created;
  perform public.enqueue_social_push(created);
  return created.id;
end;
$function$;

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
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  -- This guard must precede the advisory lock, inventory debit, recipient
  -- credit, and notification insert.  Test accounts cannot spend tickets as
  -- an unintended side effect of automated UI exploration.
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
  if exists (
    select 1
    from public.social_notifications
    where sender_id = current_user_id
      and request_id = gift_request_id
  ) then
    return (
      select id
      from public.social_notifications
      where sender_id = current_user_id
        and request_id = gift_request_id
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
    and (item_id <> 'nickname_color_ticket' or store_nickname_color_tickets > 0)
    and (item_id <> 'nickname_change_ticket' or store_nickname_change_tickets > 0);
  if not found then
    raise exception 'gift item is not available';
  end if;
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

create or replace function public.claim_push_notification_jobs(
  batch_limit integer default 50
)
returns setof public.push_notification_outbox
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- An account can be marked as a test account after its notification was
  -- queued.  Suppress those rows before leasing any work so a later worker
  -- restart cannot deliver the stale push.
  update public.push_notification_outbox outbox
  set suppressed_at = now(),
      processing_until = null,
      lease_token = null,
      last_error = 'suppressed for test account'
  from public.social_notifications notification
  join public.profiles sender_profile
    on sender_profile.id = notification.sender_id
  join public.profiles recipient_profile
    on recipient_profile.id = notification.recipient_id
  where outbox.notification_id = notification.id
    and outbox.sent_at is null
    and outbox.suppressed_at is null
    and (
      coalesce(sender_profile.is_test_account, false)
      or coalesce(recipient_profile.is_test_account, false)
    );

  return query
  with candidates as (
    select id
    from public.push_notification_outbox
    where sent_at is null
      and suppressed_at is null
      and attempt_count < 5
      and (processing_until is null or processing_until < now())
    order by created_at
    for update skip locked
    limit least(greatest(coalesce(batch_limit, 50), 1), 50)
  )
  update public.push_notification_outbox outbox
  set processing_until = now() + interval '10 minutes',
      lease_token = gen_random_uuid()
  from candidates
  where outbox.id = candidates.id
    and outbox.sent_at is null
    and outbox.suppressed_at is null
  returning outbox.*;
end;
$function$;

create or replace function public.suppress_social_pushes_for_test_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not coalesce(new.is_test_account, false)
     or coalesce(old.is_test_account, false) then
    return new;
  end if;

  -- Revoke an already-issued lease as well as suppressing ordinary pending
  -- rows.  The worker's lease check then stops before any FCM request.
  update public.push_notification_outbox outbox
  set suppressed_at = now(),
      processing_until = null,
      lease_token = null,
      last_error = 'suppressed for test account'
  where outbox.sent_at is null
    and outbox.suppressed_at is null
    and (
      outbox.recipient_id = new.id
      or exists (
        select 1
        from public.social_notifications notification
        where notification.id = outbox.notification_id
          and notification.sender_id = new.id
      )
    );

  return new;
end;
$function$;

drop trigger if exists profiles_suppress_social_pushes_for_test_account
  on public.profiles;
create trigger profiles_suppress_social_pushes_for_test_account
after update of is_test_account on public.profiles
for each row
when (new.is_test_account is true and old.is_test_account is distinct from true)
execute function public.suppress_social_pushes_for_test_account();

revoke all on function public.suppress_social_pushes_for_test_account()
  from public, anon, authenticated, service_role;

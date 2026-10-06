-- Give every profile one nickname-change ticket once.
--
-- 20260909000100 added the inventory column with a zero default so that it
-- could be deployed safely before the initial grant was decided.  Keep the
-- grant separate: this migration is additive for existing inventory and the
-- marker makes a manually repeated deployment harmless.

alter table public.profiles
  alter column store_nickname_change_tickets set default 1;

create table if not exists public.nickname_change_ticket_initial_grant (
  id boolean primary key default true
    constraint nickname_change_ticket_initial_grant_singleton check (id),
  applied_at timestamptz not null default now()
);

alter table public.nickname_change_ticket_initial_grant enable row level security;
revoke all on table public.nickname_change_ticket_initial_grant
  from public, anon, authenticated, service_role;

do $migration$
declare
  initial_grant_applied boolean;
begin
  -- Serialize an operator retry with the one-time marker insert.  The
  -- profile row locks taken by the update below serialize with nickname and
  -- ticket mutations as well.
  perform pg_advisory_xact_lock(
    hashtext('nickname-change-ticket-initial-grant')
  );

  insert into public.nickname_change_ticket_initial_grant (id)
  values (true)
  on conflict (id) do nothing
  returning true into initial_grant_applied;

  if coalesce(initial_grant_applied, false) then
    update public.profiles profile
    set
      store_nickname_change_tickets = least(
        coalesce(profile.store_nickname_change_tickets, 0) + 1,
        9999
      ),
      updated_at = now();
  end if;
end;
$migration$;

comment on table public.nickname_change_ticket_initial_grant is
  'Private one-time marker for the initial nickname-change ticket grant.';

-- 20260909000100 temporarily replaced the latest social push formatter while
-- adding the new gift item. Restore the formatted score and opt-out-safe
-- outbox payload, adding only the nickname-change gift label.
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
    from public.profiles
    where id = target_notification.recipient_id
      and social_notifications_enabled
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


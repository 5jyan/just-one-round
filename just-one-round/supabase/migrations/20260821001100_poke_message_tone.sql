-- Keep in-app and push poke copy in sync after the tone adjustment.

create or replace function public.enqueue_social_push(target_notification public.social_notifications)
returns void language plpgsql security definer set search_path = '' as $$
declare sender_name text; message_body text;
begin
  select coalesce(nickname, '이름 미설정') into sender_name
  from public.profiles where id = target_notification.sender_id;
  message_body := case target_notification.action_type
    when 'poke' then sender_name || '님이 콕 찔렀어요. 이건 못 참죠?'
    when 'boast' then sender_name || '님은 기록이 ' ||
      coalesce(target_notification.sender_score::text, '-') || '로 오늘 ' ||
      coalesce(target_notification.sender_rank::text, '-') ||
      '등이에요. 이 기록도 못 넘겠어요?'
    when 'gift' then sender_name || '님이 ' || case target_notification.gift_item_id
      when 'practice_ticket' then '연습권' when 'challenge_ticket' then '도전권'
      else '닉네임 색상권' end || ' 1장을 선물했습니다.' end;
  if exists(select 1 from public.profiles
    where id = target_notification.recipient_id and social_notifications_enabled) then
    insert into public.push_notification_outbox(notification_id, recipient_id, title, body, payload)
    values(target_notification.id, target_notification.recipient_id, '딱한판만', message_body,
      jsonb_build_object('notification_id', target_notification.id,
        'action_type', target_notification.action_type))
    on conflict(notification_id) do nothing;
  end if;
end; $$;

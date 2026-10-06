-- Include the sender's actual record and game in boast notifications so the
-- popup can show a playful, specific challenge instead of a generic alert.

alter table public.social_notifications
  add column if not exists sender_score integer,
  add column if not exists sender_game_id text;

create or replace function public.enqueue_social_push(target_notification public.social_notifications)
returns void language plpgsql security definer set search_path = '' as $$
declare sender_name text; message_body text;
begin
  select coalesce(nickname, '이름 미설정') into sender_name
  from public.profiles where id = target_notification.sender_id;
  message_body := case target_notification.action_type
    when 'poke' then sender_name || '님이 찔렀습니다.'
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

create or replace function public.send_social_action(target_user_id uuid, social_action text, action_request_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := (select auth.uid());
  created public.social_notifications;
  current_rank integer;
  current_score integer;
  current_game_id text;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if target_user_id is null or target_user_id = current_user_id then raise exception 'invalid recipient'; end if;
  if social_action not in ('poke', 'boast') then raise exception 'invalid social action'; end if;
  if exists(select 1 from public.social_notifications
    where sender_id = current_user_id and request_id = action_request_id) then
    return (select id from public.social_notifications
      where sender_id = current_user_id and request_id = action_request_id);
  end if;
  if not exists(select 1 from public.profiles where id = target_user_id and not is_test_account) then
    raise exception 'recipient unavailable';
  end if;
  if (select count(*) from public.social_notifications
    where sender_id = current_user_id and created_at >= now() - interval '24 hours') >= 10 then
    raise exception 'daily social action limit reached';
  end if;
  if exists(select 1 from public.social_notifications
    where sender_id = current_user_id and recipient_id = target_user_id
      and action_type = social_action and created_at >= now() - interval '6 hours') then
    raise exception 'social action cooldown';
  end if;
  if social_action = 'boast' then
    select ranked.rank, ranked.raw_score, ranked.game_id
      into current_rank, current_score, current_game_id
    from (
      select best.user_id, best.raw_score, best.game_id,
        row_number() over(order by best.raw_score desc, best.submitted_at asc,
          best.user_id)::integer rank
      from (
        select distinct on (score.user_id)
          score.user_id, score.raw_score, score.game_id, score.submitted_at
        from public.scores score
        join public.profiles profile on profile.id = score.user_id
        where score.play_date = public.current_play_date() and not profile.is_test_account
        order by score.user_id, score.raw_score desc, score.submitted_at asc
      ) best
    ) ranked where ranked.user_id = current_user_id;
    if current_rank is null then raise exception 'today rank is not available'; end if;
  end if;
  insert into public.social_notifications(
    sender_id, recipient_id, action_type, sender_rank, sender_score, sender_game_id, request_id)
  values(current_user_id, target_user_id, social_action, current_rank,
    current_score, current_game_id, action_request_id)
  on conflict(sender_id, request_id) do update set request_id = excluded.request_id
  returning * into created;
  perform public.enqueue_social_push(created);
  return created.id;
end; $$;

create or replace function public.get_unseen_social_notifications(notification_limit integer default 10)
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id, 'action_type', n.action_type, 'gift_item_id', n.gift_item_id,
    'sender_nickname', coalesce(p.nickname, '이름 미설정'),
    'sender_rank', n.sender_rank, 'sender_score', n.sender_score,
    'sender_game_id', n.sender_game_id, 'created_at', n.created_at
  ) order by n.created_at), '[]'::jsonb)
  from (
    select * from public.social_notifications
    where recipient_id = (select auth.uid()) and seen_at is null
    order by created_at limit least(greatest(notification_limit, 1), 20)
  ) n join public.profiles p on p.id = n.sender_id;
$$;

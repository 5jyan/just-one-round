-- Keep push boast scores identical to the game result formatter.
-- Scores are stored as integers, but their unit depends on the game.

create or replace function public.format_social_score(
  target_game_id text,
  target_score integer
)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  safe_score integer;
  elapsed_milliseconds integer;
  centiseconds integer;
begin
  if target_score is null then
    return '-';
  end if;

  safe_score := greatest(target_score, 0);

  case target_game_id
    when 'dung_dodge_v2', 'dung_dodge', 'star_dodge', 'gravity_switch' then
      return to_char(
        safe_score::numeric / 1000,
        'FM9999999990.00'
      ) || '초';

    when 'number_rush' then
      if target_score = 0 then
        return '0점';
      end if;
      elapsed_milliseconds := greatest(
        least(3600000 - target_score, 3599999),
        1
      );
      centiseconds := round(elapsed_milliseconds::numeric / 10)::integer;
      return to_char(
        centiseconds::numeric / 100,
        'FM9999999990.00'
      ) || '초';

    when 'ramen_timer' then
      if target_score = 0 then
        return '시간 초과';
      end if;
      -- Ramen Timer accepts scores from 3,525,750 through 3,600,000.
      -- Keep malformed historical rows readable instead of breaking a push.
      if target_score < 3525750 or target_score > 3600000 then
        return to_char(safe_score, 'FM999,999,999,990') || '점';
      end if;
      elapsed_milliseconds := 3600000 - target_score;
      centiseconds := round(elapsed_milliseconds::numeric / 10)::integer;
      return '총 오차 ' || to_char(
        centiseconds::numeric / 100,
        'FM9999999990.00'
      ) || '초';

    when 'ten_pitch_slugger' then
      return to_char(
        safe_score::numeric / 100,
        'FM999,999,999,990.00'
      ) || 'm';

    when 'apple_game_v2', 'apple_game' then
      return safe_score::text || '개';

    when 'sausage_dachshund', 'midnight_snake' then
      return safe_score::text || '개';

    when 'beat_the_dealer' then
      return least(safe_score, 925)::text || '코인';

    when 'failed_bakery' then
      return safe_score::text || '층';

    when 'mama_duck_trail', 'bathhouse_sort', 'lily_frog', 'net_boat' then
      return to_char(safe_score, 'FM999,999,999,990') || '점';

    else
      -- Unknown historical games still get a readable, grouped score.
      return to_char(safe_score, 'FM999,999,999,990') || '점';
  end case;
end;
$$;

revoke all on function public.format_social_score(text, integer)
  from public, anon, authenticated, service_role;

comment on function public.format_social_score(text, integer) is
  'Formats a stored game score for social inbox and push messages.';

create or replace function public.enqueue_social_push(
  target_notification public.social_notifications
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

-- Correct only queued boast pushes. Already delivered notifications must not
-- be rewritten after the fact.
update public.push_notification_outbox outbox
set body = coalesce(sender_profile.nickname, '이름 미설정')
  || '님은 기록이 '
  || public.format_social_score(
    notification.sender_game_id,
    notification.sender_score
  )
  || '로 오늘 '
  || coalesce(notification.sender_rank::text, '-')
  || '등으로 자랑했어요.'
from public.social_notifications notification
join public.profiles sender_profile
  on sender_profile.id = notification.sender_id
where outbox.notification_id = notification.id
  and notification.action_type = 'boast'
  and outbox.sent_at is null
  and outbox.suppressed_at is null;

create or replace function public.get_unseen_social_notifications(
  notification_limit integer default 10
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id,
    'action_type', n.action_type,
    'gift_item_id', n.gift_item_id,
    'sender_nickname', coalesce(p.nickname, '이름 미설정'),
    'sender_rank', n.sender_rank,
    'sender_score', n.sender_score,
    'sender_score_label', public.format_social_score(
      n.sender_game_id,
      n.sender_score
    ),
    'sender_game_id', n.sender_game_id,
    'created_at', n.created_at
  ) order by n.created_at), '[]'::jsonb)
  from (
    select *
    from public.social_notifications
    where recipient_id = (select auth.uid())
      and seen_at is null
    order by created_at
    limit least(greatest(notification_limit, 1), 20)
  ) n
  join public.profiles p on p.id = n.sender_id;
$$;

begin;

select plan(16);

select is(
  public.format_social_score('ten_pitch_slugger', 10465),
  '104.65m',
  'ten pitch scores use meters and preserve two decimals'
);
select is(
  public.format_social_score('ten_pitch_slugger', 15000),
  '150.00m',
  'ten pitch scores keep trailing meter decimals'
);
select is(
  public.format_social_score('dung_dodge_v2', 10465),
  '10.47초',
  'survival scores use seconds'
);
select is(
  public.format_social_score('gravity_switch', 12340),
  '12.34초',
  'gravity survival scores use seconds'
);
select is(
  public.format_social_score('number_rush', 3589535),
  '10.47초',
  'number rush ranking scores decode to elapsed seconds'
);
select is(
  public.format_social_score('number_rush', 0),
  '0점',
  'number rush timeout keeps its zero-score label'
);
select is(
  public.format_social_score('ramen_timer', 3589535),
  '총 오차 10.47초',
  'ramen timer ranking scores decode to total error seconds'
);
select is(
  public.format_social_score('ramen_timer', 0),
  '시간 초과',
  'ramen timer timeout keeps its label'
);
select is(
  public.format_social_score('apple_game_v2', 42),
  '42개',
  'apple scores use item counts'
);
select is(
  public.format_social_score('midnight_snake', 12),
  '12개',
  'snake scores use item counts'
);
select is(
  public.format_social_score('beat_the_dealer', 925),
  '925코인',
  'blackjack scores use coins'
);
select is(
  public.format_social_score('net_boat', 12345),
  '12,345점',
  'point scores use thousands separators'
);
select is(
  public.format_social_score('failed_bakery', 27),
  '27층',
  'historical bakery scores keep floors'
);
select is(
  public.format_social_score('unknown_legacy_game', 10465),
  '10,465점',
  'unknown historical scores remain readable'
);

insert into auth.users(id, is_anonymous) values
  ('52525252-5252-4252-8252-525252525252', true),
  ('53535353-5353-4353-8353-535353535353', true);
update public.profiles
set nickname = '포맷테스트'
where id = '52525252-5252-4252-8252-525252525252';
update public.profiles
set nickname = '푸시수신자'
where id = '53535353-5353-4353-8353-535353535353';

insert into public.social_notifications(
  id,
  sender_id,
  recipient_id,
  action_type,
  sender_rank,
  sender_score,
  sender_game_id,
  request_id
) values (
  '54545454-5454-4454-8454-545454545454',
  '52525252-5252-4252-8252-525252525252',
  '53535353-5353-4353-8353-535353535353',
  'boast',
  1,
  10465,
  'ten_pitch_slugger',
  '55555555-5555-4555-8555-555555555555'
);
select public.enqueue_social_push(notification)
from public.social_notifications notification
where notification.id = '54545454-5454-4454-8454-545454545454';
select is(
  (
    select body
    from public.push_notification_outbox
    where notification_id = '54545454-5454-4454-8454-545454545454'
  ),
  '포맷테스트님은 기록이 104.65m로 오늘 1등으로 자랑했어요.',
  'push boasts use the same formatted meter score'
);

insert into public.social_notifications(
  id,
  sender_id,
  recipient_id,
  action_type,
  gift_item_id,
  request_id
) values (
  '56565656-5656-4656-8656-565656565656',
  '52525252-5252-4252-8252-525252525252',
  '53535353-5353-4353-8353-535353535353',
  'gift',
  'nickname_change_ticket',
  '57575757-5757-4757-8757-575757575757'
);
select public.enqueue_social_push(notification)
from public.social_notifications notification
where notification.id = '56565656-5656-4656-8656-565656565656';
select is(
  (
    select body
    from public.push_notification_outbox
    where notification_id = '56565656-5656-4656-8656-565656565656'
  ),
  '포맷테스트님이 닉네임 변경권 1장을 선물했습니다.',
  'push gifts use the nickname change ticket label'
);

select * from finish();
rollback;

begin;

select plan(36);

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
  public.format_social_score('western_duel', 999999),
  '0.001초',
  'western duel formats the fastest valid reaction with three decimals'
);
select is(
  public.format_social_score('western_duel', 999650),
  '0.350초',
  'western duel decodes a stored score into seconds'
);
select is(
  public.format_social_score('western_duel', 998500),
  '1.500초',
  'western duel formats the slowest valid reaction'
);
select is(
  public.format_social_score('western_duel', 0),
  '기록 없음',
  'western duel timeout scores have no ranking record'
);
select is(
  public.format_social_score('western_duel', 998499),
  '기록 없음',
  'western duel scores below the valid range have no record'
);
select is(
  public.format_social_score('western_duel', 1000000),
  '기록 없음',
  'western duel scores at the ranking ceiling have no record'
);
select is(
  public.format_social_score('western_duel', null),
  '-',
  'western duel null scores keep the legacy placeholder'
);
select is(
  public.format_social_score('mole_reaction', 999998),
  '2ms',
  'mole reaction formats the minimum valid weighted time'
);
select is(
  public.format_social_score('mole_reaction', 999650),
  '350ms',
  'mole reaction decodes a stored score into milliseconds'
);
select is(
  public.format_social_score('mole_reaction', 1),
  '999,999ms',
  'mole reaction groups long valid times with commas'
);
select is(
  public.format_social_score('mole_reaction', 0),
  '시간 초과',
  'mole reaction timeout keeps its label'
);
select is(
  public.format_social_score('mole_reaction', 999999),
  '999,999점',
  'mole reaction scores below the minimum valid total use the legacy fallback'
);
select is(
  public.format_social_score('mole_reaction', 1000000),
  '1,000,000점',
  'mole reaction scores at the ranking ceiling use the legacy fallback'
);
select is(
  public.format_social_score('mole_reaction', null),
  '-',
  'mole reaction null scores keep the legacy placeholder'
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
  sender_rank,
  sender_score,
  sender_game_id,
  request_id
) values (
  '58585858-5858-4858-8858-585858585858',
  '52525252-5252-4252-8252-525252525252',
  '53535353-5353-4353-8353-535353535353',
  'boast',
  2,
  999650,
  'western_duel',
  '59595959-5959-4959-8959-595959595959'
);
select public.enqueue_social_push(notification)
from public.social_notifications notification
where notification.id = '58585858-5858-4858-8858-585858585858';
select is(
  (
    select body
    from public.push_notification_outbox
    where notification_id = '58585858-5858-4858-8858-585858585858'
  ),
  '포맷테스트님은 기록이 0.350초로 오늘 2등으로 자랑했어요.',
  'western duel boast bodies use reaction seconds'
);
select is(
  (
    select payload->>'sender_score_label'
    from public.push_notification_outbox
    where notification_id = '58585858-5858-4858-8858-585858585858'
  ),
  '0.350초',
  'western duel push payloads carry the formatted reaction label'
);

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
  '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a',
  '52525252-5252-4252-8252-525252525252',
  '53535353-5353-4353-8353-535353535353',
  'boast',
  3,
  999650,
  'mole_reaction',
  '5b5b5b5b-5b5b-4b5b-8b5b-5b5b5b5b5b5b'
);
select public.enqueue_social_push(notification)
from public.social_notifications notification
where notification.id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a';
select is(
  (
    select body
    from public.push_notification_outbox
    where notification_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a'
  ),
  '포맷테스트님은 기록이 350ms로 오늘 3등으로 자랑했어요.',
  'mole reaction boast bodies use grouped milliseconds'
);
select is(
  (
    select payload->>'sender_score_label'
    from public.push_notification_outbox
    where notification_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a'
  ),
  '350ms',
  'mole reaction push payloads carry the formatted reaction label'
);

select set_config(
  'request.jwt.claim.sub',
  '53535353-5353-4353-8353-535353535353',
  true
);
set local role authenticated;
select ok(
  public.get_unseen_social_notifications(20) @>
    jsonb_build_array(jsonb_build_object(
      'sender_game_id', 'western_duel',
      'sender_score_label', '0.350초'
    )),
  'unseen inbox entries expose the western duel reaction label'
);
select ok(
  public.get_unseen_social_notifications(20) @>
    jsonb_build_array(jsonb_build_object(
      'sender_game_id', 'mole_reaction',
      'sender_score_label', '350ms'
    )),
  'unseen inbox entries expose the mole reaction label'
);
reset role;

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

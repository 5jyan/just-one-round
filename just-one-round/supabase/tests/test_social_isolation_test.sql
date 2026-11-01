begin;

select plan(20);

insert into auth.users(id, is_anonymous)
values
  ('51515151-5151-4515-8515-515151515151', true),
  ('52525252-5252-4525-8525-525252525252', true),
  ('53535353-5353-4535-8535-535353535353', true),
  ('54545454-5454-4545-8545-545454545454', true),
  ('55555555-5555-4555-8555-555555555555', true);

update public.profiles
set
  nickname = '자동화 테스트 발신자',
  is_test_account = true,
  store_practice_tickets = 1,
  store_challenge_tickets = 1,
  store_nickname_color_tickets = 1,
  store_nickname_change_tickets = 1
where id = '51515151-5151-4515-8515-515151515151';

update public.profiles
set nickname = '일반 수신자', is_test_account = false
where id = '52525252-5252-4525-8525-525252525252';

update public.profiles
set
  nickname = '일반 발신자',
  is_test_account = false,
  store_practice_tickets = 1
where id = '53535353-5353-4535-8535-535353535353';

update public.profiles
set nickname = '자동화 테스트 수신자', is_test_account = true
where id = '54545454-5454-4545-8545-545454545454';

update public.profiles
set nickname = '전환 테스트 수신자', is_test_account = false
where id = '55555555-5555-4555-8555-555555555555';

select set_config(
  'request.jwt.claim.sub',
  '51515151-5151-4515-8515-515151515151',
  true
);
set local role authenticated;

select throws_ok(
  $$ select public.send_social_action(
    '52525252-5252-4525-8525-525252525252',
    'poke',
    'a1010101-0101-4101-8101-010101010101'
  ) $$,
  'P0001',
  'social actions unavailable for test accounts',
  'a test sender cannot send a social action'
);
reset role;
select is(
  (select count(*)::text from public.social_notifications
   where sender_id = '51515151-5151-4515-8515-515151515151'),
  '0',
  'a blocked social action creates no notification'
);
select is(
  (select count(*)::text from public.push_notification_outbox
   where recipient_id = '52525252-5252-4525-8525-525252525252'),
  '0',
  'a blocked social action creates no push job'
);

set local role authenticated;
select throws_ok(
  $$ select public.gift_shop_item(
    '52525252-5252-4525-8525-525252525252',
    'practice_ticket',
    'a2020202-0202-4202-8202-020202020202'
  ) $$,
  'P0001',
  'social gifts unavailable for test accounts',
  'a test sender cannot gift a ticket'
);
reset role;
select is(
  (select store_practice_tickets::text from public.profiles
   where id = '51515151-5151-4515-8515-515151515151'),
  '1',
  'a blocked gift does not debit the test sender'
);
select is(
  (select store_practice_tickets::text from public.profiles
   where id = '52525252-5252-4525-8525-525252525252'),
  '0',
  'a blocked gift does not credit the recipient'
);
select is(
  (select count(*)::text from public.social_notifications
   where sender_id = '51515151-5151-4515-8515-515151515151'),
  '0',
  'a blocked gift creates no notification'
);

-- Direct maintenance or legacy callers cannot bypass the centralized push
-- guard even if a notification row already exists.
insert into public.social_notifications(
  id, sender_id, recipient_id, action_type, request_id
) values
  (
    'a3030303-0303-4303-8303-030303030303',
    '51515151-5151-4515-8515-515151515151',
    '52525252-5252-4525-8525-525252525252',
    'poke',
    'a3040404-0404-4404-8404-040404040404'
  ),
  (
    'a3050505-0505-4505-8505-050505050505',
    '53535353-5353-4535-8535-535353535353',
    '54545454-5454-4545-8545-545454545454',
    'poke',
    'a3060606-0606-4606-8606-060606060606'
  );

select public.enqueue_social_push(notification)
from public.social_notifications notification
where notification.id in (
  'a3030303-0303-4303-8303-030303030303',
  'a3050505-0505-4505-8505-050505050505'
);
select is(
  (select count(*)::text from public.push_notification_outbox
   where notification_id in (
     'a3030303-0303-4303-8303-030303030303',
     'a3050505-0505-4505-8505-050505050505'
   )),
  '0',
  'test senders and recipients cannot create push jobs through enqueue'
);

select set_config(
  'request.jwt.claim.sub',
  '53535353-5353-4535-8535-535353535353',
  true
);
set local role authenticated;
select ok(
  public.send_social_action(
    '52525252-5252-4525-8525-525252525252',
    'poke',
    'a3070707-0707-4707-8707-070707070707'
  ) is not null,
  'a normal sender can still send a social action'
);
select ok(
  public.gift_shop_item(
    '52525252-5252-4525-8525-525252525252',
    'practice_ticket',
    'a3080808-0808-4808-8808-080808080808'
  ) is not null,
  'a normal sender can still gift a ticket'
);
reset role;

select is(
  (select store_practice_tickets::text from public.profiles
   where id = '53535353-5353-4535-8535-535353535353'),
  '0',
  'a normal gift still debits the sender'
);
select is(
  (select store_practice_tickets::text from public.profiles
   where id = '52525252-5252-4525-8525-525252525252'),
  '1',
  'a normal gift still credits the recipient'
);
select is(
  (select count(*)::text
   from public.push_notification_outbox outbox
   join public.social_notifications notification
     on notification.id = outbox.notification_id
   where notification.sender_id = '53535353-5353-4535-8535-535353535353'
     and notification.recipient_id = '52525252-5252-4525-8525-525252525252'),
  '2',
  'normal social actions still create push jobs'
);

-- Verify that rows queued before a profile is marked as a test account are
-- suppressed during claim, while a normal row remains claimable.
insert into public.social_notifications(
  id, sender_id, recipient_id, action_type, request_id
) values
  (
    'a3090909-0909-4909-8909-090909090909',
    '51515151-5151-4515-8515-515151515151',
    '52525252-5252-4525-8525-525252525252',
    'poke',
    'a3101010-1010-4101-8101-010101010101'
  ),
  (
    'a3111111-1111-4111-8111-111111111111',
    '53535353-5353-4535-8535-535353535353',
    '52525252-5252-4525-8525-525252525252',
    'poke',
    'a3121212-1212-4212-8212-121212121212'
  );

insert into public.push_notification_outbox(
  notification_id, recipient_id, title, body
)
select notification.id, notification.recipient_id, '딱한판만', 'claim test'
from public.social_notifications notification
where notification.id in (
  'a3090909-0909-4909-8909-090909090909',
  'a3111111-1111-4111-8111-111111111111'
);

update public.push_notification_outbox outbox
set processing_until = now() + interval '1 hour'
where outbox.notification_id in (
  select notification.id
  from public.social_notifications notification
  where notification.sender_id = '53535353-5353-4535-8535-535353535353'
    and notification.request_id in (
      'a3070707-0707-4707-8707-070707070707',
      'a3080808-0808-4808-8808-080808080808'
    )
);

set local role service_role;
select is(
  (select count(*)::text from public.claim_push_notification_jobs(50)),
  '1',
  'claim skips and suppresses stale test-account push jobs'
);
reset role;

select ok(
  (select suppressed_at is not null
   from public.push_notification_outbox
   where notification_id = 'a3090909-0909-4909-8909-090909090909'),
  'a stale test-account push job is marked suppressed'
);
select is(
  (select last_error from public.push_notification_outbox
   where notification_id = 'a3090909-0909-4909-8909-090909090909'),
  'suppressed for test account',
  'the suppression reason is recorded for operators'
);
select ok(
  (select lease_token is not null
   from public.push_notification_outbox
   where notification_id = 'a3111111-1111-4111-8111-111111111111'),
  'a normal queued push job remains claimable'
);

-- A profile can become a test account after a worker has already leased its
-- notification.  The profile trigger must revoke that lease before FCM.
insert into public.social_notifications(
  id, sender_id, recipient_id, action_type, request_id
) values (
  'a3131313-1313-4313-8313-131313131313',
  '53535353-5353-4535-8535-535353535353',
  '55555555-5555-4555-8555-555555555555',
  'poke',
  'a3141414-1414-4414-8414-141414141414'
);
insert into public.push_notification_outbox(
  notification_id, recipient_id, title, body
)
values (
  'a3131313-1313-4313-8313-131313131313',
  '55555555-5555-4555-8555-555555555555',
  '딱한판만',
  'claimed transition test'
);
set local role service_role;
select is(
  (select count(*)::text from public.claim_push_notification_jobs(50)),
  '1',
  'a normal queued transition job can be claimed before the flag changes'
);
reset role;
update public.profiles
set is_test_account = true, updated_at = now()
where id = '55555555-5555-4555-8555-555555555555';
select ok(
  (select suppressed_at is not null
   from public.push_notification_outbox
   where notification_id = 'a3131313-1313-4313-8313-131313131313'),
  'marking the recipient as a test account suppresses its claimed push'
);
select ok(
  (select processing_until is null and lease_token is null
   from public.push_notification_outbox
   where notification_id = 'a3131313-1313-4313-8313-131313131313'),
  'marking the recipient as a test account revokes its push lease'
);

select * from finish();
rollback;

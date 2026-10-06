begin;

select plan(6);

insert into auth.users(id, is_anonymous) values
  ('29292929-2929-4292-8292-292929292929', true),
  ('29292929-2929-4292-8292-292929292930', true);

insert into public.social_notifications(
  sender_id,
  recipient_id,
  action_type,
  request_id
)
values (
  '29292929-2929-4292-8292-292929292929',
  '29292929-2929-4292-8292-292929292930',
  'poke',
  '29292929-2929-4292-8292-292929292931'
);

insert into public.push_notification_outbox(
  notification_id,
  recipient_id,
  title,
  body
)
select
  id,
  recipient_id,
  '딱한판만',
  '테스트 알림'
from public.social_notifications
where request_id = '29292929-2929-4292-8292-292929292931';

set local role service_role;
select is(
  (select count(*)::text from public.claim_push_notification_jobs(50)
    where recipient_id = '29292929-2929-4292-8292-292929292930'),
  '1',
  'a pending outbox row is claimed'
);
select ok(
  (select processing_until > now()
   from public.push_notification_outbox
   where recipient_id = '29292929-2929-4292-8292-292929292930'),
  'claiming sets a future processing lease'
);
select is(
  (select count(*)::text from public.claim_push_notification_jobs(50)
    where recipient_id = '29292929-2929-4292-8292-292929292930'),
  '0',
  'a leased row cannot be claimed again immediately'
);

update public.push_notification_outbox
set processing_until = now() - interval '1 second'
where recipient_id = '29292929-2929-4292-8292-292929292930';
select is(
  (select count(*)::text from public.claim_push_notification_jobs(null)
    where recipient_id = '29292929-2929-4292-8292-292929292930'),
  '1',
  'an expired lease can be claimed again and null uses the safe default batch'
);

update public.push_notification_outbox
set attempt_count = 5,
    processing_until = now() - interval '1 second'
where recipient_id = '29292929-2929-4292-8292-292929292930';
select is(
  (select count(*)::text from public.claim_push_notification_jobs(50)
    where recipient_id = '29292929-2929-4292-8292-292929292930'),
  '0',
  'rows at the retry limit are not claimed'
);
reset role;

set local role authenticated;
select throws_ok(
  $$ select * from public.claim_push_notification_jobs(50) $$,
  '42501',
  'permission denied for function claim_push_notification_jobs',
  'client roles cannot claim push jobs'
);

select * from finish();
rollback;

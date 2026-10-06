begin;

select plan(1);

insert into auth.users(id, is_anonymous) values
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1', true),
  ('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2', true);

update public.profiles
set social_notifications_enabled = false
where id = 'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2';

insert into public.social_notifications(
  id,
  sender_id,
  recipient_id,
  action_type,
  request_id
) values (
  'b3b3b3b3-b3b3-43b3-83b3-b3b3b3b3b3b3',
  'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1',
  'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2',
  'poke',
  'b4b4b4b4-b4b4-44b4-84b4-b4b4b4b4b4b4'
);

select public.enqueue_social_push(notification)
from public.social_notifications notification
where notification.id = 'b3b3b3b3-b3b3-43b3-83b3-b3b3b3b3b3b3';

select is(
  (select count(*)::text from public.push_notification_outbox
   where notification_id = 'b3b3b3b3-b3b3-43b3-83b3-b3b3b3b3b3b3'),
  '0',
  'nickname-ticket enqueue keeps strict opt-out behavior'
);

select * from finish();
rollback;

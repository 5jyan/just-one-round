begin;

select plan(16);

insert into auth.users(id, is_anonymous)
values
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', true),
  ('a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2', true),
  ('a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3', true);

insert into public.social_notifications(
  sender_id,
  recipient_id,
  action_type,
  request_id
)
values
  (
    'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1',
    'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2',
    'poke',
    'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1'
  ),
  (
    'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1',
    'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2',
    'poke',
    'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2'
  ),
  (
    'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1',
    'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2',
    'poke',
    'b3b3b3b3-b3b3-43b3-83b3-b3b3b3b3b3b3'
  ),
  (
    'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1',
    'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3',
    'poke',
    'b4b4b4b4-b4b4-44b4-84b4-b4b4b4b4b4b4'
  );

insert into public.push_notification_outbox(
  notification_id,
  recipient_id,
  title,
  body,
  processing_until,
  sent_at,
  attempt_count
)
select
  notification.id,
  notification.recipient_id,
  '딱한판만',
  'strict opt-out test',
  case when notification.request_id = 'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2'::uuid
    then now() + interval '10 minutes' end,
  case when notification.request_id = 'b3b3b3b3-b3b3-43b3-83b3-b3b3b3b3b3b3'::uuid
    then now() end,
  0
from public.social_notifications notification
where notification.request_id in (
  'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1'::uuid,
  'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2'::uuid,
  'b3b3b3b3-b3b3-43b3-83b3-b3b3b3b3b3b3'::uuid,
  'b4b4b4b4-b4b4-44b4-84b4-b4b4b4b4b4b4'::uuid
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'push_notification_outbox'
      and column_name = 'suppressed_at'
  ),
  'the push outbox has a suppression timestamp'
);

select is(
  (
    select count(*)::text
    from public.push_notification_outbox
    where recipient_id = 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2'
      and sent_at is null
  ),
  '2',
  'the opt-out recipient starts with two unsent rows'
);

select set_config(
  'request.jwt.claim.sub',
  'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2',
  true
);
set local role authenticated;
select public.set_social_notifications_enabled(false);
reset role;

select is(
  (
    select count(*)::text
    from public.push_notification_outbox
    where recipient_id = 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2'
      and sent_at is null
      and suppressed_at is not null
  ),
  '2',
  'disabling social notifications suppresses every unsent recipient row'
);

select ok(
  (
    select processing_until is null
    from public.push_notification_outbox outbox
    join public.social_notifications notification
      on notification.id = outbox.notification_id
    where notification.request_id = 'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2'
  ),
  'suppressing a leased row releases its lease'
);

select is(
  (
    select count(*)::text
    from public.push_notification_outbox
    where recipient_id = 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2'
      and sent_at is not null
      and suppressed_at is not null
  ),
  '0',
  'a previously sent row is not marked suppressed'
);

select is(
  (
    select count(*)::text
    from public.push_notification_outbox
    where recipient_id = 'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3'
      and suppressed_at is not null
  ),
  '0',
  'opt-out only affects the current recipient'
);

set local role authenticated;
select public.set_social_notifications_enabled(true);
reset role;

select is(
  (
    select count(*)::text
    from public.push_notification_outbox
    where recipient_id = 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2'
      and suppressed_at is not null
  ),
  '2',
  're-enabling notifications does not resurrect suppressed rows'
);

set local role service_role;

select is(
  (select count(*)::text from public.claim_push_notification_jobs(50)),
  '1',
  'claiming ignores suppressed rows and returns the remaining pending row'
);

select ok(
  (
    select lease_token is not null
    from public.push_notification_outbox
    where recipient_id = 'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3'
  ),
  'a claim receives a unique lease token'
);

select is(
  (
    select recipient_id::text
    from public.push_notification_outbox
    where recipient_id = 'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3'
      and processing_until > now()
  ),
  'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3',
  'the unsuppressed row receives a lease'
);

select ok(
  not exists (
    select 1
    from public.push_notification_outbox
    where recipient_id = 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2'
      and processing_until is not null
  ),
  'suppressed rows do not receive a claim lease'
);

update public.push_notification_outbox
set processing_until = null,
    lease_token = null
where recipient_id = 'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3'
  and lease_token = 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid;
select ok(
  (
    select processing_until > now()
    from public.push_notification_outbox
    where recipient_id = 'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3'
  ),
  'a stale lease token cannot release an active claim'
);

select is(
  (select count(*)::text from public.claim_push_notification_jobs(50)),
  '0',
  'an active lease cannot be claimed again immediately'
);

update public.push_notification_outbox
set processing_until = now() - interval '1 second'
where recipient_id = 'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3';

select is(
  (select count(*)::text from public.claim_push_notification_jobs(50)),
  '1',
  'an expired lease remains retryable'
);

update public.push_notification_outbox
set attempt_count = 5,
    processing_until = now() - interval '1 second'
where recipient_id = 'a3a3a3a3-a3a3-43a3-83a3-a3a3a3a3a3a3';

select is(
  (select count(*)::text from public.claim_push_notification_jobs(50)),
  '0',
  'the existing retry limit still excludes exhausted rows'
);

update public.push_notification_outbox
set sent_at = now(),
    processing_until = null
where recipient_id = 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2'
  and sent_at is null
  and suppressed_at is null;

select ok(
  not exists (
    select 1
    from public.push_notification_outbox
    where recipient_id = 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2'
      and suppressed_at is not null
      and sent_at is not null
  ),
  'a guarded completion update cannot turn a suppressed row into sent'
);

reset role;
select * from finish();

rollback;

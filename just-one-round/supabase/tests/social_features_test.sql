begin;

select plan(18);

insert into auth.users(id, is_anonymous) values
  ('25252525-2525-4252-8252-252525252525', true),
  ('26262626-2626-4262-8262-262626262626', true);

update public.profiles set nickname = '보내는사람', coin_balance = 600
where id = '25252525-2525-4252-8252-252525252525';
update public.profiles set nickname = '받는사람'
where id = '26262626-2626-4262-8262-262626262626';
select set_config('request.jwt.claim.sub', '25252525-2525-4252-8252-252525252525', true);
set local role authenticated;

select is(public.purchase_nickname_color('mint',
  'bbbbbbbb-0000-4000-8000-000000000001')->>'coins', '300',
  'choosing a nickname color spends 300 coins');
select is(public.purchase_nickname_color('mint',
  'bbbbbbbb-0000-4000-8000-000000000001')->>'nickname_color', 'mint',
  'a color purchase applies a permanent nickname color');
select is((select store_nickname_color_tickets::text from public.profiles
  where id = '25252525-2525-4252-8252-252525252525'), '0',
  'applying a color consumes one ticket');
select throws_ok(
  $$ select public.set_my_nickname_color('default') $$,
  'P0001', 'invalid nickname color',
  'a selected nickname color cannot be reset for free');

select public.purchase_shop_item('practice_ticket',
  'bbbbbbbb-0000-4000-8000-000000000002');
select ok(public.gift_shop_item('26262626-2626-4262-8262-262626262626',
  'practice_ticket', 'bbbbbbbb-0000-4000-8000-000000000003') is not null,
  'a held ticket can be gifted');
reset role;

select is((select store_practice_tickets::text from public.profiles
  where id = '25252525-2525-4252-8252-252525252525'), '0',
  'gift removes the sender inventory');
select is((select store_practice_tickets::text from public.profiles
  where id = '26262626-2626-4262-8262-262626262626'), '1',
  'gift adds the recipient inventory');
select is((select count(*)::text from public.push_notification_outbox
  where recipient_id = '26262626-2626-4262-8262-262626262626'), '1',
  'gift creates a remote push outbox record');
select is(
  (select payload->>'destination' from public.push_notification_outbox
    where recipient_id = '26262626-2626-4262-8262-262626262626' limit 1),
  'today_game',
  'push payload opens the daily-game home without spending a round'
);

set local role authenticated;
select ok(public.send_social_action('26262626-2626-4262-8262-262626262626',
  'poke', 'bbbbbbbb-0000-4000-8000-000000000004') is not null,
  'poke creates a notification');
select ok(public.send_social_action('26262626-2626-4262-8262-262626262626',
  'poke', 'bbbbbbbb-0000-4000-8000-000000000004') is not null,
  'retrying the same poke request is idempotent');
select ok(public.send_social_action('26262626-2626-4262-8262-262626262626',
  'poke', 'bbbbbbbb-0000-4000-8000-000000000005') is not null,
  'a second poke to the same recipient is allowed before the daily limit');
select throws_ok(
  $$ select public.send_social_action('25252525-2525-4252-8252-252525252525',
    'poke', 'bbbbbbbb-0000-4000-8000-000000000006') $$,
  'P0001', 'invalid recipient', 'users cannot poke themselves');

select set_config('request.jwt.claim.sub', '26262626-2626-4262-8262-262626262626', true);
select is(jsonb_array_length(public.get_unseen_social_notifications())::text, '2',
  'recipient inbox contains the gift and poke');
select is((public.get_unseen_social_notifications()->0->>'sender_nickname'), '보내는사람',
  'inbox includes the sender nickname');
select is(public.acknowledge_social_notifications(array(
  select (entry->>'id')::uuid from jsonb_array_elements(public.get_unseen_social_notifications()) entry
)), 2, 'recipient acknowledges displayed notifications');
select is(jsonb_array_length(public.get_unseen_social_notifications())::text, '0',
  'acknowledged notifications no longer appear');
select throws_ok($$ select * from public.social_notifications $$, '42501',
  'permission denied for table social_notifications', 'clients cannot read notification storage directly');

select * from finish();
rollback;

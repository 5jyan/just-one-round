-- Run after 20261012000300_adjust_level_nickname_colors.sql inside a transaction.
begin;

select plan(32);

insert into auth.users(id, is_anonymous)
values
  ('72000000-0000-4000-8000-000000000001', true),
  ('72000000-0000-4000-8000-000000000002', true),
  ('72000000-0000-4000-8000-000000000003', true),
  ('72000000-0000-4000-8000-000000000004', true),
  ('72000000-0000-4000-8000-000000000005', true),
  ('72000000-0000-4000-8000-000000000006', true),
  ('72000000-0000-4000-8000-000000000007', true),
  ('72000000-0000-4000-8000-000000000008', true);

-- The 100-then-150 XP curve reaches levels 5, 10, 15, 20, 25, and 30 at
-- 1,300, 6,300, 15,050, 27,550, 43,800, and 63,800 XP.
do $$
declare
  level_user uuid := '72000000-0000-4000-8000-000000000001';
  expected text;
  boundary record;
begin
  for boundary in
    select * from (values
      (1299::bigint, 'default'::text),
      (1300::bigint, 'yellow'::text),
      (6299::bigint, 'yellow'::text),
      (6300::bigint, 'mint'::text),
      (15049::bigint, 'mint'::text),
      (15050::bigint, 'sky'::text),
      (27549::bigint, 'sky'::text),
      (27550::bigint, 'violet'::text),
      (43799::bigint, 'violet'::text),
      (43800::bigint, 'pink'::text),
      (63799::bigint, 'pink'::text),
      (63800::bigint, 'gold'::text)
    ) as values(xp, color)
  loop
    update public.profiles
    set experience_points = boundary.xp
    where id = level_user;
    select profile.nickname_color into expected
    from public.profiles profile
    where profile.id = level_user;
    if expected <> boundary.color then
      raise exception 'XP % expected % but got %',
        boundary.xp, boundary.color, expected;
    end if;
  end loop;
end;
$$;
select pass('all level color boundaries map to the contracted tokens');

update public.profiles
set experience_points = 1600,
    nickname_color = 'gold'
where id = '72000000-0000-4000-8000-000000000001';
select is(
  (select nickname_color from public.profiles
   where id = '72000000-0000-4000-8000-000000000001'),
  'yellow',
  'an explicit color cannot override the level color during an XP update'
);
update public.profiles
set nickname_color = 'coral'
where id = '72000000-0000-4000-8000-000000000001';
select is(
  (select nickname_color from public.profiles
   where id = '72000000-0000-4000-8000-000000000001'),
  'yellow',
  'a manual nickname color update is normalized by the profile trigger'
);

select ok(
  position('coral' in pg_get_constraintdef(constraint_row.oid)) > 0
    and position('cyan' in pg_get_constraintdef(constraint_row.oid)) > 0
    and position('yellow' in pg_get_constraintdef(constraint_row.oid)) > 0
    and position('gold' in pg_get_constraintdef(constraint_row.oid)) > 0,
  'the profile constraint keeps legacy coral and includes the new tokens'
)
from pg_constraint constraint_row
where constraint_row.conrelid = 'public.profiles'::regclass
  and constraint_row.conname = 'profiles_nickname_color_check';

update public.profiles
set coin_balance = 100,
    experience_points = 900,
    store_nickname_color_tickets = 3,
    nickname_color = 'coral'
where id = '72000000-0000-4000-8000-000000000002';
select set_config(
  'request.jwt.claim.sub',
  '72000000-0000-4000-8000-000000000002',
  true
);
set local role service_role;
select is(
  public.refund_nickname_color_tickets(),
  3::bigint,
  'the refund operation returns the number of tickets settled'
);
reset role;

select is(
  (select store_nickname_color_tickets::text from public.profiles
   where id = '72000000-0000-4000-8000-000000000002'),
  '0',
  'refunded tickets are cleared atomically'
);
select is(
  (select coin_balance::text from public.profiles
   where id = '72000000-0000-4000-8000-000000000002'),
  '1000',
  'each held ticket refunds 300 coins'
);
select is(
  (select experience_points::text from public.profiles
   where id = '72000000-0000-4000-8000-000000000002'),
  '900',
  'the refund does not change experience'
);
select is(
  (select count(*)::text from public.coin_transactions
   where user_id = '72000000-0000-4000-8000-000000000002'
     and transaction_type = 'nickname_color_refund'
     and reference_key = 'nickname-color-retirement:20261012'),
  '1',
  'the refund writes one fixed-reference ledger row'
);
select is(
  (select coin_delta::text from public.coin_transactions
   where user_id = '72000000-0000-4000-8000-000000000002'
     and reference_key = 'nickname-color-retirement:20261012'),
  '900',
  'the refund ledger amount matches ticket quantity times unit price'
);
select is(
  (select metadata->>'previous_color' from public.coin_transactions
   where user_id = '72000000-0000-4000-8000-000000000002'
     and reference_key = 'nickname-color-retirement:20261012'),
  'default',
  'refund metadata records the pre-backfill color value'
);

set local role service_role;
select is(
  public.refund_nickname_color_tickets(),
  0::bigint,
  'a second refund run finds no held tickets'
);
reset role;
select is(
  (select count(*)::text from public.coin_transactions
   where user_id = '72000000-0000-4000-8000-000000000002'
     and reference_key = 'nickname-color-retirement:20261012'),
  '1',
  'a second refund run cannot duplicate the ledger row'
);

update public.profiles
set coin_balance = 1000000000,
    store_nickname_color_tickets = 1
where id = '72000000-0000-4000-8000-000000000003';
set local role service_role;
select throws_ok(
  $$ select public.refund_nickname_color_tickets() $$,
  'P0001',
  'economy balance limit exceeded',
  'coin cap overflow rejects the refund without clamping'
);
reset role;
select is(
  (select store_nickname_color_tickets::text from public.profiles
   where id = '72000000-0000-4000-8000-000000000003'),
  '1',
  'a failed overflow refund leaves the ticket held'
);

update public.profiles
set coin_balance = 500
where id = '72000000-0000-4000-8000-000000000004';
select set_config(
  'request.jwt.claim.sub',
  '72000000-0000-4000-8000-000000000004',
  true
);
set local role authenticated;
select throws_ok(
  $$ select public.purchase_shop_item(
    'nickname_color_ticket',
    '72111111-1111-4111-8111-111111111111'
  ) $$,
  'P0001',
  'nickname color tickets are retired',
  'new shop color-ticket purchases are rejected'
);
select throws_ok(
  $$ select public.purchase_nickname_color(
    'mint',
    '72111111-1111-4111-8111-111111111112'
  ) $$,
  'P0001',
  'nickname color purchases are retired',
  'the legacy color purchase RPC is retired'
);
select throws_ok(
  $$ select public.set_my_nickname_color('mint') $$,
  'P0001',
  'nickname colors are determined by level',
  'the legacy color selection RPC is retired'
);
reset role;
select is(
  (select coin_balance::text from public.profiles
   where id = '72000000-0000-4000-8000-000000000004'),
  '500',
  'rejected color purchase paths do not debit coins'
);

select set_config(
  'request.jwt.claim.sub',
  '72000000-0000-4000-8000-000000000004',
  true
);
set local role authenticated;
select is(
  public.purchase_shop_item(
    'practice_ticket',
    '72111111-1111-4111-8111-111111111113'
  )->>'coins',
  '400',
  'other shop tickets continue to purchase normally'
);
reset role;

insert into public.shop_purchases(
  user_id, request_id, item_id, quantity, coins_spent
) values (
  '72000000-0000-4000-8000-000000000004',
  '72111111-1111-4111-8111-111111111114',
  'nickname_color_ticket',
  1,
  300
);
select set_config(
  'request.jwt.claim.sub',
  '72000000-0000-4000-8000-000000000004',
  true
);
set local role authenticated;
select is(
  public.purchase_shop_item(
    'nickname_color_ticket',
    '72111111-1111-4111-8111-111111111114'
  )->>'item_id',
  'nickname_color_ticket',
  'a historical shop color request remains idempotent'
);
reset role;

update public.profiles
set store_nickname_color_tickets = 1
where id = '72000000-0000-4000-8000-000000000005';
select set_config(
  'request.jwt.claim.sub',
  '72000000-0000-4000-8000-000000000005',
  true
);
set local role authenticated;
select throws_ok(
  $$ select public.gift_shop_item(
    '72000000-0000-4000-8000-000000000006',
    'nickname_color_ticket',
    '72222222-2222-4222-8222-222222222221'
  ) $$,
  'P0001',
  'nickname color gifts are retired',
  'new color-ticket gifts are rejected'
);
reset role;
select is(
  (select store_nickname_color_tickets::text from public.profiles
   where id = '72000000-0000-4000-8000-000000000005'),
  '1',
  'a rejected color gift does not debit inventory'
);
select is(
  (select count(*)::text from public.social_notifications
   where sender_id = '72000000-0000-4000-8000-000000000005'
     and request_id = '72222222-2222-4222-8222-222222222221'),
  '0',
  'a rejected color gift creates no social row'
);

update public.profiles
set is_test_account = true,
    store_nickname_color_tickets = 1
where id = '72000000-0000-4000-8000-000000000007';
select set_config(
  'request.jwt.claim.sub',
  '72000000-0000-4000-8000-000000000007',
  true
);
set local role authenticated;
select throws_ok(
  $$ select public.gift_shop_item(
    '72000000-0000-4000-8000-000000000006',
    'nickname_color_ticket',
    '72222222-2222-4222-8222-222222222222'
  ) $$,
  'P0001',
  'social gifts unavailable for test accounts',
  'the existing test-account gift guard runs before retirement logic'
);
reset role;
select is(
  (select store_nickname_color_tickets::text from public.profiles
   where id = '72000000-0000-4000-8000-000000000007'),
  '1',
  'the test-account guard prevents a color gift debit'
);

update public.profiles
set is_test_account = false,
    store_practice_tickets = 1
where id = '72000000-0000-4000-8000-000000000005';
insert into public.social_notifications(
  id, sender_id, recipient_id, action_type, gift_item_id, request_id
) values (
  '72222222-2222-4222-8222-222222222223',
  '72000000-0000-4000-8000-000000000005',
  '72000000-0000-4000-8000-000000000006',
  'gift',
  'nickname_color_ticket',
  '72222222-2222-4222-8222-222222222224'
);
select set_config(
  'request.jwt.claim.sub',
  '72000000-0000-4000-8000-000000000005',
  true
);
set local role authenticated;
select ok(
  public.gift_shop_item(
    '72000000-0000-4000-8000-000000000006',
    'nickname_color_ticket',
    '72222222-2222-4222-8222-222222222224'
  ) = '72222222-2222-4222-8222-222222222223'::uuid,
  'a matching historical color gift request remains idempotent'
);
select throws_ok(
  $$ select public.gift_shop_item(
    '72000000-0000-4000-8000-000000000006',
    'practice_ticket',
    '72222222-2222-4222-8222-222222222224'
  ) $$,
  'P0001',
  'gift request mismatch',
  'a historical gift request cannot be replayed as another item'
);
select throws_ok(
  $$ select public.gift_shop_item(
    '72000000-0000-4000-8000-000000000004',
    'nickname_color_ticket',
    '72222222-2222-4222-8222-222222222224'
  ) $$,
  'P0001',
  'gift request mismatch',
  'a historical gift request cannot be replayed for another recipient'
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  '72000000-0000-4000-8000-000000000005',
  true
);
set local role authenticated;
select ok(
  public.gift_shop_item(
    '72000000-0000-4000-8000-000000000006',
    'practice_ticket',
    '72222222-2222-4222-8222-222222222225'
  ) is not null,
  'other ticket gifts continue to work'
);
reset role;
select is(
  (select store_practice_tickets::text from public.profiles
   where id = '72000000-0000-4000-8000-000000000005'),
  '0',
  'a normal gift debits the sender inventory'
);
select is(
  (select store_practice_tickets::text from public.profiles
   where id = '72000000-0000-4000-8000-000000000006'),
  '1',
  'a normal gift credits the recipient inventory'
);

select * from finish();
rollback;

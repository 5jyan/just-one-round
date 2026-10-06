begin;

select plan(23);

insert into auth.users (id, is_anonymous)
values ('31313131-3131-4131-8131-313131313131', true);

select is(
  (select store_nickname_change_tickets::text from public.profiles
   where id = '31313131-3131-4131-8131-313131313131'),
  '1',
  'new profiles receive one nickname change ticket'
);

update public.profiles
set coin_balance = 500, nickname = '첫번째닉'
where id = '31313131-3131-4131-8131-313131313131';

select set_config(
  'request.jwt.claim.sub',
  '31313131-3131-4131-8131-313131313131',
  true
);

select is(
  public.purchase_shop_item(
    'nickname_change_ticket',
    'aaaaaaaa-0000-4000-8000-000000000701'
  )->>'coins',
  '0',
  'a nickname change ticket costs 500 coins'
);
select is(
  public.purchase_shop_item(
    'nickname_change_ticket',
    'aaaaaaaa-0000-4000-8000-000000000701'
  )->>'nickname_change_tickets',
  '2',
  'a nickname change purchase is idempotent'
);
select is(
  (select coin_balance::text from public.profiles
  where id = '31313131-3131-4131-8131-313131313131'),
  '0',
  'a nickname change ticket purchase spends 500 coins once'
);

select is(
  (public.set_my_nickname('두번째닉')).nickname,
  '두번째닉',
  'an existing nickname can be changed with a ticket'
);
select is(
  (select store_nickname_change_tickets::text from public.profiles
   where id = '31313131-3131-4131-8131-313131313131'),
  '1',
  'changing a nickname consumes one ticket'
);

select is(
  (public.set_my_nickname('두번째닉')).nickname,
  '두번째닉',
  'saving the current nickname is a no-op'
);
select is(
  (select store_nickname_change_tickets::text from public.profiles
   where id = '31313131-3131-4131-8131-313131313131'),
  '1',
  'a no-op does not consume a ticket'
);

insert into auth.users (id, is_anonymous)
values ('33333333-3333-4333-8333-333333333333', true);
select set_config(
  'request.jwt.claim.sub',
  '33333333-3333-4333-8333-333333333333',
  true
);
select is(
  (public.set_my_nickname('중복닉')).nickname,
  '중복닉',
  'another profile can claim the duplicate test nickname'
);

select set_config(
  'request.jwt.claim.sub',
  '31313131-3131-4131-8131-313131313131',
  true
);
select throws_ok(
  $$ select public.set_my_nickname('중복닉') $$,
  '23505',
  'nickname already taken',
  'a duplicate nickname is rejected'
);
select is(
  (select nickname from public.profiles
   where id = '31313131-3131-4131-8131-313131313131'),
  '두번째닉',
  'a duplicate nickname leaves the old nickname in place'
);
select is(
  (select store_nickname_change_tickets::text from public.profiles
   where id = '31313131-3131-4131-8131-313131313131'),
  '1',
  'a duplicate nickname leaves the ticket available'
);

select is(
  (public.set_my_nickname('세번째닉')).nickname,
  '세번째닉',
  'a successful rename can use the remaining ticket'
);
select is(
  (select store_nickname_change_tickets::text from public.profiles
   where id = '31313131-3131-4131-8131-313131313131'),
  '0',
  'the second rename consumes the remaining ticket'
);
select throws_ok(
  $$ select public.set_my_nickname('네번째닉') $$,
  'P0001',
  'nickname change ticket is not available',
  'a second nickname change needs another ticket'
);

insert into auth.users (id, is_anonymous)
values ('32323232-3232-4232-8232-323232323232', true);

select is(
  (select store_nickname_change_tickets::text from public.profiles
   where id = '32323232-3232-4232-8232-323232323232'),
  '1',
  'a second new profile also receives one ticket'
);

select set_config(
  'request.jwt.claim.sub',
  '32323232-3232-4232-8232-323232323232',
  true
);

select is(
  (public.set_my_nickname('처음설정')).nickname,
  '처음설정',
  'the first nickname replaces the generated nickname for free'
);
select is(
  (select store_nickname_change_tickets::text from public.profiles
   where id = '32323232-3232-4232-8232-323232323232'),
  '1',
  'free first-time nickname setup does not consume a ticket'
);

update public.profiles
set coin_balance = 499
where id = '32323232-3232-4232-8232-323232323232';

select throws_ok(
  $$ select public.purchase_shop_item(
    'nickname_change_ticket',
    'aaaaaaaa-0000-4000-8000-000000000702'
  ) $$,
  'P0001',
  'insufficient coin balance',
  'a nickname change ticket requires 500 coins'
);
select is(
  (select store_nickname_change_tickets::text from public.profiles
   where id = '32323232-3232-4232-8232-323232323232'),
  '1',
  'an insufficient-funds purchase leaves inventory unchanged'
);

select throws_ok(
  $$ select public.set_my_nickname(null) $$,
  'P0001',
  'nickname must be between 2 and 12 characters',
  'a null nickname is rejected before the anonymous-name trigger runs'
);
select is(
  (select nickname from public.profiles
   where id = '32323232-3232-4232-8232-323232323232'),
  '처음설정',
  'a null nickname leaves the current nickname unchanged'
);
select is(
  (select store_nickname_change_tickets::text from public.profiles
   where id = '32323232-3232-4232-8232-323232323232'),
  '1',
  'a rejected null nickname leaves the ticket available'
);

select * from finish();
rollback;

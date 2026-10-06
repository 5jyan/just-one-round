begin;

select plan(7);

insert into auth.users (id, is_anonymous)
values ('24242424-2424-4242-8242-242424242424', true);

select set_config(
  'request.jwt.claim.sub',
  '24242424-2424-4242-8242-242424242424',
  true
);

set local role authenticated;

select ok(
  public.submit_support_inquiry('게임이 자꾸 멈춰요', '1.2.3', 45) is not null,
  'an authenticated user can submit an inquiry'
);

reset role;

select is(
  (select message from public.support_inquiries limit 1),
  '게임이 자꾸 멈춰요',
  'the inquiry message is stored'
);

select is(
  (select app_version from public.support_inquiries limit 1),
  '1.2.3',
  'the app version is stored'
);

select is(
  (select build_number from public.support_inquiries limit 1),
  45,
  'the build number is stored'
);

select is(
  (select status from public.support_inquiries limit 1),
  'pending',
  'a new inquiry starts pending'
);

set local role authenticated;

select throws_ok(
  $$ select public.submit_support_inquiry(' 짧음 ', '1.2.3', 45) $$,
  'P0001',
  'inquiry must be between 5 and 1000 characters',
  'short inquiries are rejected'
);

select throws_ok(
  $$ select * from public.support_inquiries $$,
  '42501',
  'permission denied for table support_inquiries',
  'clients cannot read the operations inquiry table directly'
);

select * from finish();
rollback;

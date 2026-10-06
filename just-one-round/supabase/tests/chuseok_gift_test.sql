begin;

select plan(10);

insert into auth.users (id, is_anonymous)
values ('52525252-5252-4252-8252-525252525252', true);

select set_config(
  'test.chuseok_active',
  public.chuseok_event_active()::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '52525252-5252-4252-8252-525252525252',
  true
);
set local role authenticated;

select is(
  (public.get_chuseok_gift_status()->>'eligible'),
  current_setting('test.chuseok_active'),
  'status is controlled by the Seoul-time event cutoff'
);
select is(
  (public.get_chuseok_gift_status()->>'claimed'),
  'false',
  'a new account has not claimed the gift'
);
select is(
  (public.claim_chuseok_gift()->>'granted'),
  current_setting('test.chuseok_active'),
  'the first claim grants only while the event is active'
);
select is(
  (public.claim_chuseok_gift()->>'claimed'),
  current_setting('test.chuseok_active'),
  'a repeated active claim is idempotently marked claimed'
);

reset role;

select is(
  (select count(*)::integer
   from public.chuseok_gift_claims
   where user_id = '52525252-5252-4252-8252-525252525252'),
  case when current_setting('test.chuseok_active') = 'true' then 1 else 0 end,
  'the unique claim row is created at most once'
);
select is(
  (select store_challenge_tickets::integer
   from public.profiles
   where id = '52525252-5252-4252-8252-525252525252'),
  case when current_setting('test.chuseok_active') = 'true' then 1 else 0 end,
  'the first claim adds one challenge ticket'
);

set local role authenticated;

select is(
  (public.claim_chuseok_gift()->>'granted'),
  'false',
  'a retry never grants a second ticket'
);
select is(
  (public.claim_chuseok_gift()->>'claimed'),
  current_setting('test.chuseok_active'),
  'a retry reports the existing claim while the event is active'
);

reset role;

select is(
  (select count(*)::integer
   from public.chuseok_gift_claims
   where user_id = '52525252-5252-4252-8252-525252525252'),
  case when current_setting('test.chuseok_active') = 'true' then 1 else 0 end,
  'retries do not add another claim row'
);
select is(
  (select store_challenge_tickets::integer
   from public.profiles
   where id = '52525252-5252-4252-8252-525252525252'),
  case when current_setting('test.chuseok_active') = 'true' then 1 else 0 end,
  'retries leave the ticket balance unchanged'
);

select * from finish();
rollback;

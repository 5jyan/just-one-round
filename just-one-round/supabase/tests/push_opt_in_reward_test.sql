begin;

select plan(43);

insert into auth.users (id, is_anonymous)
values
  ('71717171-7171-4171-8171-717171717171', true),
  ('72727272-7272-4272-8272-727272727272', true),
  ('73737373-7373-4373-8373-737373737373', true),
  ('74747474-7474-4474-8474-747474747474', true);

select set_config(
  'request.jwt.claim.sub',
  '71717171-7171-4171-8171-717171717171',
  true
);
set local role authenticated;

select is(
  (public.get_push_opt_in_reward_status()->>'should_show'),
  'true',
  'a new account is due for the push opt-in offer'
);
select is(
  (public.get_push_opt_in_reward_status()->>'accepted'),
  'false',
  'a new account has not accepted the offer'
);
select is(
  (public.get_push_opt_in_reward_status()->>'claimed'),
  'false',
  'a new account has not claimed the reward'
);
reset role;
select ok(
  not exists (
    select 1
    from public.push_opt_in_rewards
    where user_id = '71717171-7171-4171-8171-717171717171'
  ),
  'reading status does not create or consume a prompt reservation'
);
set local role authenticated;

select is(
  (public.record_push_opt_in_reward_prompt(false)->>'should_show'),
  'true',
  'the first prompt call reserves the due offer'
);
reset role;
select set_config(
  'test.push_opt_in_prompted_at',
  (
    select last_prompted_at::text
    from public.push_opt_in_rewards
    where user_id = '71717171-7171-4171-8171-717171717171'
  ),
  true
);
set local role authenticated;
select is(
  (public.record_push_opt_in_reward_prompt(false)->>'should_show'),
  'false',
  'a duplicate prompt call does not reserve again during the cooldown'
);
reset role;
select is(
  (
    select last_prompted_at::text
    from public.push_opt_in_rewards
    where user_id = '71717171-7171-4171-8171-717171717171'
  ),
  current_setting('test.push_opt_in_prompted_at'),
  'a duplicate prompt call leaves the cooldown timestamp unchanged'
);
set local role authenticated;
select is(
  (public.get_push_opt_in_reward_status()->>'should_show'),
  'false',
  'status remains hidden during the prompt cooldown'
);

reset role;
update public.push_opt_in_rewards
set last_prompted_at = now() - interval '30 days' + interval '1 second'
where user_id = '71717171-7171-4171-8171-717171717171';
set local role authenticated;
select is(
  (public.get_push_opt_in_reward_status()->>'should_show'),
  'false',
  'a prompt one second before thirty days is not due'
);

reset role;
update public.push_opt_in_rewards
set last_prompted_at = now() - interval '30 days'
where user_id = '71717171-7171-4171-8171-717171717171';
set local role authenticated;
select is(
  (public.get_push_opt_in_reward_status()->>'should_show'),
  'true',
  'a prompt at the thirty-day boundary is due'
);
select is(
  (public.record_push_opt_in_reward_prompt(false)->>'should_show'),
  'true',
  'a due prompt can be reserved again after thirty days'
);
reset role;
select set_config(
  'test.push_opt_in_prompted_at',
  (
    select last_prompted_at::text
    from public.push_opt_in_rewards
    where user_id = '71717171-7171-4171-8171-717171717171'
  ),
  true
);
set local role authenticated;

select is(
  (public.record_push_opt_in_reward_prompt(true)->>'accepted'),
  'true',
  'acceptance records an earlier reserved offer'
);
select is(
  (public.record_push_opt_in_reward_prompt(true)->>'should_show'),
  'false',
  'acceptance does not return another offer'
);
reset role;
select is(
  (
    select last_prompted_at::text
    from public.push_opt_in_rewards
    where user_id = '71717171-7171-4171-8171-717171717171'
  ),
  current_setting('test.push_opt_in_prompted_at'),
  'acceptance does not reset the prompt cooldown timestamp'
);
set local role authenticated;
select is(
  (public.record_push_opt_in_reward_prompt(false)->>'should_show'),
  'false',
  'an accepted unclaimed account receives no second prompt'
);
reset role;
update public.push_opt_in_rewards
set last_prompted_at = now() - interval '30 days'
where user_id = '71717171-7171-4171-8171-717171717171';
set local role authenticated;
select is(
  (public.record_push_opt_in_reward_prompt(false)->>'should_show'),
  'true',
  'an accepted but unclaimed account can be prompted again after thirty days'
);

select is(
  (public.claim_push_opt_in_reward()->>'granted'),
  'false',
  'a claim without a registered push token is rejected'
);

reset role;
insert into public.push_device_tokens (user_id, platform, token, updated_at)
values (
  '71717171-7171-4171-8171-717171717171',
  'ios',
  'push-opt-in-u1-old-token-717171717171',
  now() - interval '31 days'
);
set local role authenticated;
select is(
  (public.claim_push_opt_in_reward()->>'granted'),
  'false',
  'a token older than acceptance cannot claim the reward'
);

reset role;
insert into public.push_device_tokens (user_id, platform, token)
values (
  '71717171-7171-4171-8171-717171717171',
  'android',
  'push-opt-in-u1-fresh-token-717171717171'
);
set local role authenticated;
select is(
  (public.claim_push_opt_in_reward()->>'tickets_granted'),
  '1',
  'an enabled token registered after acceptance earns one ticket'
);
select is(
  (public.claim_push_opt_in_reward()->>'claimed'),
  'true',
  'a successful claim is marked claimed'
);
select is(
  (public.claim_push_opt_in_reward()->>'granted'),
  'false',
  'a repeated claim does not grant again'
);
select is(
  (
    select store_challenge_tickets::text
    from public.profiles
    where id = '71717171-7171-4171-8171-717171717171'
  ),
  '1',
  'the account balance increases exactly once'
);

reset role;
update public.profiles
set social_notifications_enabled = false
where id = '71717171-7171-4171-8171-717171717171';
set local role authenticated;
select is(
  (public.claim_push_opt_in_reward()->>'claimed'),
  'true',
  'a committed claim remains idempotent after push opt-out'
);
select is(
  (public.claim_push_opt_in_reward()->>'granted'),
  'false',
  'an idempotent retry does not grant another ticket'
);
reset role;
select is(
  (
    select claimed_at is not null
    from public.push_opt_in_rewards
    where user_id = '71717171-7171-4171-8171-717171717171'
  )::text,
  'true',
  'the first account claim stays committed'
);
set local role authenticated;

select set_config(
  'request.jwt.claim.sub',
  '72727272-7272-4272-8272-727272727272',
  true
);
select is(
  (public.record_push_opt_in_reward_prompt(false)->>'should_show'),
  'true',
  'a second account receives its own prompt reservation'
);
select is(
  (public.record_push_opt_in_reward_prompt(true)->>'accepted'),
  'true',
  'the second account can accept its reserved prompt'
);
reset role;
insert into public.push_device_tokens (user_id, platform, token)
values
  (
    '72727272-7272-4272-8272-727272727272',
    'ios',
    'push-opt-in-u2-ios-token-727272727272'
  ),
  (
    '72727272-7272-4272-8272-727272727272',
    'android',
    'push-opt-in-u2-android-token-727272727272'
  );
set local role authenticated;
select is(
  (public.claim_push_opt_in_reward()->>'granted'),
  'true',
  'multiple fresh device tokens still produce one grant'
);
select is(
  (public.claim_push_opt_in_reward()->>'granted'),
  'false',
  'retries after the first grant do not grant again'
);
select is(
  (
    select store_challenge_tickets::text
    from public.profiles
    where id = '72727272-7272-4272-8272-727272727272'
  ),
  '1',
  'multiple devices leave the second account with one ticket'
);
reset role;
update public.profiles
set social_notifications_enabled = false
where id = '72727272-7272-4272-8272-727272727272';
set local role authenticated;
select is(
  (public.claim_push_opt_in_reward()->>'claimed'),
  'true',
  'the second account retry remains idempotent after disabling push'
);

select set_config(
  'request.jwt.claim.sub',
  '73737373-7373-4373-8373-737373737373',
  true
);
select is(
  (public.record_push_opt_in_reward_prompt(false)->>'should_show'),
  'true',
  'a full-capacity account can reserve the offer'
);
select is(
  (public.record_push_opt_in_reward_prompt(true)->>'accepted'),
  'true',
  'the full-capacity account can accept the offer'
);
reset role;
insert into public.push_device_tokens (user_id, platform, token)
values (
  '73737373-7373-4373-8373-737373737373',
  'ios',
  'push-opt-in-u3-fresh-token-737373737373'
);
set local role authenticated;
reset role;
update public.profiles
set store_challenge_tickets = 9999
where id = '73737373-7373-4373-8373-737373737373';
set local role authenticated;
select is(
  (public.claim_push_opt_in_reward()->>'granted'),
  'false',
  'a full challenge-ticket balance cannot claim'
);
select is(
  (public.claim_push_opt_in_reward()->>'claimed'),
  'false',
  'a full-capacity rejection remains retryable'
);
reset role;
select is(
  (
    select claimed_at is null
    from public.push_opt_in_rewards
    where user_id = '73737373-7373-4373-8373-737373737373'
  )::text,
  'true',
  'capacity rejection does not mark the reward claimed'
);
set local role authenticated;
reset role;
update public.profiles
set store_challenge_tickets = 9998
where id = '73737373-7373-4373-8373-737373737373';
set local role authenticated;
select is(
  (public.claim_push_opt_in_reward()->>'granted'),
  'true',
  'a capacity rejection can be retried after space is available'
);

select set_config(
  'request.jwt.claim.sub',
  '74747474-7474-4474-8474-747474747474',
  true
);
select is(
  (public.record_push_opt_in_reward_prompt(true)->>'accepted'),
  'false',
  'acceptance without a reserved offer is ignored'
);
select is(
  (public.record_push_opt_in_reward_prompt(true)->>'should_show'),
  'false',
  'an invalid acceptance does not create an offer'
);
select is(
  (public.record_push_opt_in_reward_prompt(false)->>'should_show'),
  'true',
  'an invalid acceptance leaves the account eligible for its first prompt'
);

select set_config(
  'request.jwt.claim.sub',
  '71717171-7171-4171-8171-717171717171',
  true
);
select throws_ok(
  $$ select * from public.push_opt_in_rewards $$,
  '42501',
  'permission denied for table push_opt_in_rewards',
  'clients cannot read push opt-in reward storage directly'
);
select throws_ok(
  $$ insert into public.push_opt_in_rewards (user_id)
     values ('71717171-7171-4171-8171-717171717171') $$,
  '42501',
  'permission denied for table push_opt_in_rewards',
  'clients cannot insert push opt-in reward storage directly'
);
select throws_ok(
  $$ update public.push_opt_in_rewards
     set accepted_at = now()
     where user_id = '71717171-7171-4171-8171-717171717171' $$,
  '42501',
  'permission denied for table push_opt_in_rewards',
  'clients cannot update push opt-in reward storage directly'
);

select * from finish();
rollback;

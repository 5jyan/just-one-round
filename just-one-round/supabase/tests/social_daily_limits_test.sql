begin;

select plan(4);

insert into auth.users(id, is_anonymous) values
  ('37373737-3737-4373-8373-373737373737', true),
  ('38383838-3838-4383-8383-383838383838', true),
  ('39393939-3939-4393-8393-393939393939', true),
  ('40404040-4040-4404-8404-404040404040', true),
  ('41414141-4141-4414-8414-414141414141', true);

update public.profiles set is_test_account = false
where id in (
  '37373737-3737-4373-8373-373737373737',
  '38383838-3838-4383-8383-383838383838',
  '39393939-3939-4393-8393-393939393939',
  '40404040-4040-4404-8404-404040404040',
  '41414141-4141-4414-8414-414141414141'
);

select set_config('request.jwt.claim.sub', '37373737-3737-4373-8373-373737373737', true);
set local role authenticated;

select ok(public.send_social_action('38383838-3838-4383-8383-383838383838', 'poke',
  'cccccccc-0000-4000-8000-000000000001') is not null, 'first poke is allowed');
select ok(public.send_social_action('39393939-3939-4393-8393-393939393939', 'poke',
  'cccccccc-0000-4000-8000-000000000002') is not null, 'second poke is allowed');
select ok(public.send_social_action('40404040-4040-4404-8404-404040404040', 'poke',
  'cccccccc-0000-4000-8000-000000000003') is not null, 'third poke is allowed');
select throws_ok($$ select public.send_social_action(
  '41414141-4141-4414-8414-414141414141', 'poke',
  'cccccccc-0000-4000-8000-000000000004') $$,
  'P0001', 'daily poke limit reached', 'fourth poke is blocked');

select * from finish();
rollback;

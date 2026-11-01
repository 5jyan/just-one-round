-- Run after 20261012000500_level_up_rewards.sql inside a transaction.
begin;

select plan(21);

select is(
  public.experience_threshold(1),
  0::bigint,
  'level 1 starts at zero XP'
);
select is(
  public.experience_threshold(2),
  100::bigint,
  'the first level-up costs 100 XP'
);
select is(
  public.experience_threshold(3),
  350::bigint,
  'the second threshold adds 250 XP'
);
select is(
  public.experience_threshold(5),
  1300::bigint,
  'level 5 uses the 100-then-150 curve'
);
select is(
  public.experience_threshold(30),
  63800::bigint,
  'level 30 threshold is exact'
);

select is(public.experience_level(99), 1, '99 XP remains level 1');
select is(public.experience_level(100), 2, '100 XP reaches level 2');
select is(public.experience_level(349), 2, '349 XP remains level 2');
select is(public.experience_level(350), 3, '350 XP reaches level 3');
select is(public.experience_level(1299), 4, '1299 XP remains level 4');
select is(public.experience_level(1300), 5, '1300 XP reaches level 5');
select is(
  public.build_player_economy_json(0, 100)->>'experience_to_next_level',
  '250',
  'economy JSON reports the new next-level XP delta at level 2'
);
select is(
  public.build_player_economy_json(0, 350)->>'experience_to_next_level',
  '400',
  'economy JSON reports the new next-level XP delta at level 3'
);

do $$
declare
  existing_user uuid := '68000000-0000-4000-8000-000000000001';
  new_user uuid := '68000000-0000-4000-8000-000000000002';
  cap_user uuid := '68000000-0000-4000-8000-000000000003';
begin
  insert into auth.users(id, is_anonymous)
  values (existing_user, true), (new_user, true), (cap_user, true);

  -- Simulate an account that existed before this migration: at 1,300 XP the
  -- old curve reported level 4 while the new curve reports level 5.
  update public.profiles
  set level_rewarded_through = 4,
      level_celebration_seen_through = 4
  where id = existing_user;
  update public.profiles
  set experience_points = 1300
  where id = existing_user;

  if (select experience_points from public.profiles where id = existing_user)
      <> 1300 then
    raise exception 'XP changed while granting the migration delta';
  end if;
  if (select store_challenge_tickets from public.profiles where id = existing_user)
      <> 1 then
    raise exception 'existing account should receive only one newly reached ticket';
  end if;
  if (select nickname_color from public.profiles where id = existing_user)
      <> 'yellow' then
    raise exception 'new XP curve did not normalize the level color';
  end if;

  perform set_config('request.jwt.claim.sub', existing_user::text, true);
  if public.get_pending_level_up_reward() <> jsonb_build_object(
    'user_id', existing_user,
    'from_level', 4,
    'to_level', 5,
    'challenge_tickets', 1
  ) then
    raise exception 'unexpected initial pending reward: %',
      public.get_pending_level_up_reward();
  end if;

  -- Acknowledgement only advances the celebration highwater; it never adds
  -- another ticket and it requires the caller to bind the expected user.
  if public.acknowledge_level_up_reward(5, existing_user) is not null then
    raise exception 'full acknowledgement should clear the pending reward';
  end if;
  if public.get_pending_level_up_reward() is not null then
    raise exception 'acknowledgement did not clear the pending reward';
  end if;

  update public.profiles
  set experience_points = 2000
  where id = existing_user;
  if (select store_challenge_tickets from public.profiles where id = existing_user)
      <> 2 then
    raise exception 'a newly reached level did not add exactly one ticket';
  end if;
  if public.get_pending_level_up_reward() <> jsonb_build_object(
    'user_id', existing_user,
    'from_level', 5,
    'to_level', 6,
    'challenge_tickets', 1
  ) then
    raise exception 'new higher-level pending payload is incorrect';
  end if;

  -- Replaying the same XP, spending coins with zero XP, and dropping then
  -- restoring XP must not replay an already rewarded level.
  update public.profiles
  set coin_balance = 100
  where id = existing_user;
  update public.profiles
  set experience_points = 2000
  where id = existing_user;
  perform public.apply_coin_transaction(
    existing_user, -10, 0, 'level_up_test_spend',
    'level-up-test-spend:680000000001'
  );
  perform public.apply_coin_transaction(
    existing_user, -10, 0, 'level_up_test_spend',
    'level-up-test-spend:680000000001'
  );
  update public.profiles set experience_points = 100 where id = existing_user;
  update public.profiles set experience_points = 2000 where id = existing_user;
  if (select experience_points from public.profiles where id = existing_user)
      <> 2000
    or (select coin_balance from public.profiles where id = existing_user)
      <> 90
    or (select store_challenge_tickets from public.profiles where id = existing_user)
      <> 2
    or (select level_rewarded_through from public.profiles where id = existing_user)
      <> 6 then
    raise exception 'replayed XP or a zero-XP coin transaction changed rewards';
  end if;

  -- A newly inserted profile starts at level 1, so a high XP grant earns all
  -- levels reached by that account.
  update public.profiles
  set experience_points = 2000
  where id = new_user;
  if (select store_challenge_tickets from public.profiles where id = new_user)
      <> 5
    or (select level_rewarded_through from public.profiles where id = new_user)
      <> 6 then
    raise exception 'new high-XP account did not receive all level rewards';
  end if;
  perform set_config('request.jwt.claim.sub', new_user::text, true);
  if public.get_pending_level_up_reward() <> jsonb_build_object(
    'user_id', new_user,
    'from_level', 1,
    'to_level', 6,
    'challenge_tickets', 5
  ) then
    raise exception 'new account pending payload is incorrect';
  end if;
  if public.acknowledge_level_up_reward(3, new_user) <> jsonb_build_object(
    'user_id', new_user,
    'from_level', 3,
    'to_level', 6,
    'challenge_tickets', 3
  ) then
    raise exception 'partial acknowledgement did not return the remaining levels';
  end if;
  update public.profiles
  set experience_points = 2850
  where id = new_user;
  if (select store_challenge_tickets from public.profiles where id = new_user)
      <> 6
    or public.get_pending_level_up_reward() <> jsonb_build_object(
      'user_id', new_user,
      'from_level', 3,
      'to_level', 7,
      'challenge_tickets', 4
    ) then
    raise exception 'a higher level did not extend the partial pending reward';
  end if;
  if public.acknowledge_level_up_reward(7, new_user) is not null
    or public.acknowledge_level_up_reward(7, new_user) is not null then
    raise exception 'repeated acknowledgement returned or granted again';
  end if;

  update public.profiles
  set store_challenge_tickets = 9999
  where id = cap_user;
  begin
    update public.profiles set experience_points = 100 where id = cap_user;
    raise exception 'ticket cap overflow was not rejected';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'level-up challenge ticket cap exceeded' then
        raise;
      end if;
  end;
  if (select experience_points from public.profiles where id = cap_user) <> 0
    or (select store_challenge_tickets from public.profiles where id = cap_user)
      <> 9999
    or (select level_rewarded_through from public.profiles where id = cap_user)
      <> 1 then
    raise exception 'failed level reward did not roll back atomically';
  end if;
end;
$$;

select pass('level-up XP, ticket, highwater, and rollback behavior is correct');
select set_config(
  'request.jwt.claim.sub', '68000000-0000-4000-8000-000000000001', true
);
select throws_ok(
  $$ select public.acknowledge_level_up_reward(
    6, '68000000-0000-4000-8000-000000000002'
  ) $$,
  'P0001',
  'user mismatch',
  'acknowledgement binds to the expected authenticated user'
);
select set_config(
  'request.headers',
  '{"x-app-build":"27","x-app-platform":"ios"}',
  true
);
select is(
  public.get_today_state()->>'level_rewarded_through',
  '6',
  'today state exposes the rewarded level highwater'
);
select is(
  public.get_today_state()->>'level_celebration_seen_through',
  '5',
  'today state exposes the celebration highwater'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_pending_level_up_reward()',
    'execute'
  ),
  'authenticated can read pending level rewards'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.acknowledge_level_up_reward(integer,uuid)',
    'execute'
  ),
  'authenticated can acknowledge level rewards'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.acknowledge_level_up_reward(integer,uuid)',
    'execute'
  ),
  'anon cannot acknowledge level rewards'
);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$ select public.get_pending_level_up_reward() $$,
  'P0001',
  'authentication required',
  'unauthenticated callers cannot read level rewards'
);

select * from finish();
rollback;

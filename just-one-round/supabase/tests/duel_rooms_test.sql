begin;

select plan(43);

insert into auth.users(id, is_anonymous) values
  ('a1111111-1111-4111-8111-111111111111', true),
  ('a2222222-2222-4222-8222-222222222222', true),
  ('a3333333-3333-4333-8333-333333333333', true);

update public.profiles set nickname = '방 만든사람', coin_balance = 500
  , is_test_account = true
where id = 'a1111111-1111-4111-8111-111111111111';
update public.profiles set nickname = '입장한사람', coin_balance = 500
  , is_test_account = true
where id = 'a2222222-2222-4222-8222-222222222222';
update public.profiles set nickname = '일반사용자', coin_balance = 500
where id = 'a3333333-3333-4333-8333-333333333333';
update public.games set duel_enabled = true where id = 'dung_dodge_v2';
update public.app_runtime_config set local_duel_test_enabled = true where id;

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);

select is(
  (select count(*)::text
   from jsonb_array_elements(public.get_duel_test_players()) player
   where player->>'user_id' = 'a2222222-2222-4222-8222-222222222222'),
  '1',
  'local test account picker returns the isolated test opponent'
);
select is(
  (select player->>'nickname'
   from jsonb_array_elements(public.get_duel_test_players()) player
   where player->>'user_id' = 'a2222222-2222-4222-8222-222222222222'),
  '입장한사람',
  'local test account picker returns nickname and no normal players'
);
select set_config(
  'request.jwt.claim.sub',
  'a3333333-3333-4333-8333-333333333333',
  true
);
select is(
  jsonb_array_length(public.get_duel_test_players())::text,
  '0',
  'normal account cannot use the local test account picker'
);
select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);

select ok(
  jsonb_array_length(public.get_duel_options()) > 0,
  'active duel options are available'
);
select is(
  (select count(*)::text from jsonb_array_elements(public.get_duel_options())
    option where option->>'game_id' in ('wind_darts', 'western_duel')),
  '0',
  'pub darts and just one shot are excluded'
);

select ok(
  public.create_duel(
    'a2222222-2222-4222-8222-222222222222',
    'dung_dodge_v2',
    1,
    100,
    'a0000000-0000-4000-8000-000000000001'
  )->>'id' is not null,
  'request creates a waiting room'
);

select is(
  (public.get_duel((select id from public.duel_matches
    where client_request_id = 'a0000000-0000-4000-8000-000000000001'))
    ->>'game_name'),
  '똥피하기',
  'room snapshot includes the selected game display name'
);
select is(
  (public.get_duel((select id from public.duel_matches
    where client_request_id = 'a0000000-0000-4000-8000-000000000001'))
    ->'runs'->0->>'nickname'),
  '입장한사람',
  'room snapshot includes the opponent nickname'
);
select is(
  (public.get_duels()->0->>'game_display_name'),
  '똥피하기',
  'duel list carries the game display name'
);

select throws_ok(
  $$ select public.set_duel_ready(
    (select id from public.duel_matches
      where client_request_id = 'a0000000-0000-4000-8000-000000000001'),
    true, true,
    (public.get_duel((select id from public.duel_matches
      where client_request_id = 'a0000000-0000-4000-8000-000000000001'))
      ->>'viewer_session_token')::uuid
  ) $$,
  'P0001',
  'both players must join before ready',
  'READY is rejected while the opponent has not entered the room'
);
select is(
  (public.get_duel((select id from public.duel_matches
    where client_request_id = 'a0000000-0000-4000-8000-000000000001'))
    ->>'viewer_ready'),
  'false',
  'rejected READY does not mutate the requester state'
);

select is(
  (select coin_balance::text from public.profiles
    where id = 'a1111111-1111-4111-8111-111111111111'),
  '500',
  'request does not charge the requester'
);
select is(
  (select status from public.duel_matches
    where requester_id = 'a1111111-1111-4111-8111-111111111111'),
  'waiting',
  'new room waits for both players'
);
select is(
  (select count(*)::text from public.duel_runs
    where duel_id = (select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111')),
  '2',
  'room has two participant rows'
);

select throws_ok(
  $$ select public.create_duel(
    'a2222222-2222-4222-8222-222222222222',
    'western_duel', 1, 100,
    'a0000000-0000-4000-8000-000000000002'
  ) $$,
  'P0001',
  'game is not available for duels',
  'excluded games are rejected at the server boundary'
);

select set_config(
  'request.jwt.claim.sub',
  'a2222222-2222-4222-8222-222222222222',
  true
);

select ok(
  (public.join_duel(
    (select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111')
  )->>'viewer_joined')::boolean,
  'opponent can enter the invitation room'
);

select is(
  (select coin_balance::text from public.profiles
    where id = 'a2222222-2222-4222-8222-222222222222'),
  '500',
  'joining does not charge the opponent'
);

select ok(
  (public.set_duel_ready(
    (select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'),
    true, true,
    (public.get_duel((select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'))
      ->>'viewer_session_token')::uuid
  )->>'viewer_ready')::boolean,
  'first READY is recorded without starting'
);

select is(
  (select status from public.duel_matches
    where requester_id = 'a1111111-1111-4111-8111-111111111111'),
  'waiting',
  'one READY leaves the room waiting'
);

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);

select ok(
  (public.set_duel_ready(
    (select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'),
    true, true,
    (public.get_duel((select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'))
      ->>'viewer_session_token')::uuid
  )->>'viewer_ready')::boolean,
  'requester READY is recorded'
);

select is(
  (select coin_balance::text from public.profiles
    where id = 'a1111111-1111-4111-8111-111111111111'),
  '400',
  'second READY charges requester stake'
);
select is(
  (select coin_balance::text from public.profiles
    where id = 'a2222222-2222-4222-8222-222222222222'),
  '400',
  'second READY charges opponent stake'
);
select is(
  (select status from public.duel_matches
    where requester_id = 'a1111111-1111-4111-8111-111111111111'),
  'starting',
  'second READY starts the common countdown'
);

select throws_ok(
  $$ select public.submit_duel_result(
    (select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'),
    (public.get_duel((select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'))
      ->>'viewer_run_id')::uuid,
    (public.get_duel((select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'))
      ->>'viewer_run_token')::uuid,
    1, 0, 'valid'
  ) $$,
  'P0001',
  'duel has not started',
  'result submission cannot predate the server start timestamp'
);

update public.duel_matches
set start_at = now() - interval '1 second'
where requester_id = 'a1111111-1111-4111-8111-111111111111'
  and status = 'starting';

select throws_ok(
  $$ select public.submit_duel_result(
    (select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'),
    (public.get_duel((select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'))
      ->>'viewer_run_id')::uuid,
    (public.get_duel((select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'))
      ->>'viewer_run_token')::uuid,
    1, 120000, 'valid'
  ) $$,
  'P0001',
  'duel duration exceeds server elapsed time',
  'claimed duration cannot outrun server wall-clock elapsed time'
);

select throws_ok(
  $$ select public.submit_duel_result(
    (select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'),
    (public.get_duel((select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'))
      ->>'viewer_run_id')::uuid,
    (public.get_duel((select id from public.duel_matches
      where requester_id = 'a1111111-1111-4111-8111-111111111111'))
      ->>'viewer_run_token')::uuid,
    999999999, 1000, 'valid'
  ) $$,
  'P0001',
  'duel score is outside the game contract',
  'score submission is bounded by the selected game validator'
);

select is(
  (select count(*)::text from public.coin_transactions
    where transaction_type = 'duel_escrow'
      and metadata->>'duel_id' = (select id::text from public.duel_matches
        where client_request_id = 'a0000000-0000-4000-8000-000000000001')),
  '2',
  'both escrow ledger entries are idempotently recorded'
);

select is(
  (select count(*)::text from public.duel_matches
    where requester_id = 'a1111111-1111-4111-8111-111111111111'
      and game_id = 'western_duel'),
  '0',
  'excluded game request did not create a room'
);

select throws_ok(
  $$ select public.create_duel(
    'a3333333-3333-4333-8333-333333333333',
    'dung_dodge_v2', 1, 100,
    'a0000000-0000-4000-8000-000000000004'
  ) $$,
  'P0001',
  'duels unavailable for test accounts',
  'local test-duel mode still blocks normal/test interaction'
);

update public.duel_matches set submit_deadline = now() - interval '1 second'
where requester_id = 'a1111111-1111-4111-8111-111111111111'
  and status = 'starting';

select is(
  public.expire_duel_runs()::text,
  '2',
  'maintenance marks both overdue runs as no-result'
);
select is(
  (select status from public.duel_matches
    where requester_id = 'a1111111-1111-4111-8111-111111111111'
    order by created_at limit 1),
  'settled',
  'overdue runs settle the charged room'
);
select is(
  (select coin_balance::text from public.profiles
    where id = 'a1111111-1111-4111-8111-111111111111'),
  '500',
  'overdue no-result settlement refunds requester'
);
select is(
  (select coin_balance::text from public.profiles
    where id = 'a2222222-2222-4222-8222-222222222222'),
  '500',
  'overdue no-result settlement refunds opponent'
);
select is(
  (select count(*)::text from public.duel_payouts
    where duel_id = (select id from public.duel_matches
      where client_request_id = 'a0000000-0000-4000-8000-000000000001')
      and credited_amount = amount),
  '2',
  'maintenance records two credited refund payouts'
);

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select ok(
  public.create_duel(
    'a2222222-2222-4222-8222-222222222222',
    'dung_dodge_v2', 1, 100,
    'a0000000-0000-4000-8000-000000000003'
  )->>'id' is not null,
  'a second room can be created after settlement'
);

select set_config(
  'request.jwt.claim.sub',
  'a2222222-2222-4222-8222-222222222222',
  true
);
select ok(
  (public.join_duel((select id from public.duel_matches
    where client_request_id = 'a0000000-0000-4000-8000-000000000003'))
    ->>'viewer_joined')::boolean,
  'opponent enters the second room'
);
select ok(
  (public.set_duel_ready(
    (select id from public.duel_matches
      where client_request_id = 'a0000000-0000-4000-8000-000000000003'), true, true,
    (public.get_duel((select id from public.duel_matches
      where client_request_id = 'a0000000-0000-4000-8000-000000000003'))
      ->>'viewer_session_token')::uuid
  )->>'viewer_ready')::boolean,
  'opponent READY is recorded in the second room'
);
select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select ok(
  (public.set_duel_ready(
    (select id from public.duel_matches
      where client_request_id = 'a0000000-0000-4000-8000-000000000003'), true, true,
    (public.get_duel((select id from public.duel_matches
      where client_request_id = 'a0000000-0000-4000-8000-000000000003'))
      ->>'viewer_session_token')::uuid
  )->>'started')::boolean,
  'second READY starts the second room'
);

update public.duel_matches
set start_at = now() - interval '1 second'
where client_request_id = 'a0000000-0000-4000-8000-000000000003'
  and status = 'starting';
select public.submit_duel_result(
  (select id from public.duel_matches
    where client_request_id = 'a0000000-0000-4000-8000-000000000003'),
  (public.get_duel((select id from public.duel_matches
    where client_request_id = 'a0000000-0000-4000-8000-000000000003'))
    ->>'viewer_run_id')::uuid,
  (public.get_duel((select id from public.duel_matches
    where client_request_id = 'a0000000-0000-4000-8000-000000000003'))
    ->>'viewer_run_token')::uuid,
  1000, 1000, 'valid'
);

select is(
  public.void_duels_for_account(
    'a1111111-1111-4111-8111-111111111111'
  )::text,
  '1',
  'account cleanup voids an active charged room'
);
select is(
  (select status from public.duel_matches
    where client_request_id = 'a0000000-0000-4000-8000-000000000003'),
  'voided',
  'account cleanup leaves an auditable voided room'
);
select is(
  (select result_kind from public.duel_runs
    where duel_id = (select id from public.duel_matches
      where client_request_id = 'a0000000-0000-4000-8000-000000000003')
      and user_id = 'a1111111-1111-4111-8111-111111111111'),
  'no_result',
  'account cleanup overrides a prior submitted result with a refund'
);
select is(
  (select coin_balance::text from public.profiles
    where id = 'a1111111-1111-4111-8111-111111111111'),
  '500',
  'account cleanup refunds requester before deletion'
);
select is(
  (select coin_balance::text from public.profiles
    where id = 'a2222222-2222-4222-8222-222222222222'),
  '500',
  'account cleanup protects opponent funds'
);

select * from finish();
rollback;

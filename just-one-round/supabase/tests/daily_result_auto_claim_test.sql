begin;

select plan(7);

insert into auth.users (id, is_anonymous)
values ('25252525-2525-4252-8252-252525252525', true);

-- Build a completed score two play days ago. The normal score trigger rejects
-- historical inserts, so this test temporarily bypasses only that deadline
-- trigger while constructing its fixture.
alter table public.scores disable trigger scores_enforce_daily_deadline;

insert into public.attempts (
  id,
  user_id,
  play_date,
  game_id,
  game_version,
  ordinal,
  grant_type,
  status,
  game_duration_seconds
) values (
  '25252525-0000-4252-8252-252525252525',
  '25252525-2525-4252-8252-252525252525',
  public.current_play_date() - 2,
  'apple_game_v2',
  1,
  1,
  'daily',
  'submitted',
  120
);

insert into public.scores (
  attempt_id,
  user_id,
  play_date,
  game_id,
  game_version,
  raw_score,
  duration_ms
) values (
  '25252525-0000-4252-8252-252525252525',
  '25252525-2525-4252-8252-252525252525',
  public.current_play_date() - 2,
  'apple_game_v2',
  1,
  100,
  120000
);

alter table public.scores enable trigger scores_enforce_daily_deadline;

select set_config(
  'request.jwt.claim.sub',
  '25252525-2525-4252-8252-252525252525',
  true
);
set local role authenticated;

select ok(
  (public.get_today_state()->'economy'->>'coins')::integer > 0,
  'the next home-state fetch automatically grants an expired result reward'
);

reset role;

select is(
  (
    select count(*)::integer
    from public.daily_result_acknowledgements
    where user_id = '25252525-2525-4252-8252-252525252525'
  ),
  1,
  'automatic settlement records one acknowledgement'
);

select is(
  (
    select count(*)::integer
    from public.coin_transactions
    where user_id = '25252525-2525-4252-8252-252525252525'
      and transaction_type = 'daily_result_reward'
  ),
  1,
  'automatic settlement records one ledger transaction'
);

select is(
  (public.get_today_state()->'economy'->>'coins')::integer,
  (
    select coin_delta::integer
    from public.coin_transactions
    where user_id = '25252525-2525-4252-8252-252525252525'
      and transaction_type = 'daily_result_reward'
  ),
  'the first automatic payout is reflected in the wallet'
);

select is(
  (public.get_today_state()->'economy'->>'experience_points')::integer,
  (
    select experience_delta::integer
    from public.coin_transactions
    where user_id = '25252525-2525-4252-8252-252525252525'
      and transaction_type = 'daily_result_reward'
  ),
  'the automatic payout grants the matching experience'
);

select is(
  (
    select count(*)::integer
    from public.coin_transactions
    where user_id = '25252525-2525-4252-8252-252525252525'
      and transaction_type = 'daily_result_reward'
  ),
  1,
  'reloading home does not duplicate the payout'
);

select is(
  public.get_unseen_previous_daily_result() is null,
  true,
  'an expired result is no longer offered as a claimable popup'
);

select * from finish();
rollback;

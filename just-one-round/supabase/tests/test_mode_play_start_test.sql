begin;

select plan(8);

insert into auth.users (id, is_anonymous)
values
  ('16161616-1616-4616-8616-161616161616', true),
  ('17171717-1717-4717-8717-171717171717', true);

select set_config(
  'request.jwt.claim.sub',
  '16161616-1616-4616-8616-161616161616',
  true
);

select public.register_device_installation(
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
);
insert into public.device_daily_claims (device_hash, play_date)
values (
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  public.current_play_date()
);
update public.profiles
set is_test_account = true
where id = '16161616-1616-4616-8616-161616161616';

select is(
  (public.claim_daily_attempt(public.current_play_date())).ordinal,
  1::smallint,
  'test mode bypasses the normal device limit'
);

select lives_ok(
  $$ select public.deactivate_test_mode() $$,
  'test mode can be deactivated after a test play'
);

select is(
  (
    select count(*)::integer
    from public.attempts
    where user_id = '16161616-1616-4616-8616-161616161616'
      and play_date = public.current_play_date()
  ),
  0,
  'unlinked test attempts are removed on deactivation'
);

select is(
  (
    select count(*)::integer
    from public.device_daily_claims
    where device_hash =
      'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
      and play_date = public.current_play_date()
  ),
  1,
  'test deactivation preserves the real device daily limit'
);

select set_config(
  'request.jwt.claim.sub',
  '17171717-1717-4717-8717-171717171717',
  true
);

select is(
  (public.claim_daily_attempt(public.current_play_date())).ordinal,
  1::smallint,
  'a normal challenge starts before test mode'
);

update public.profiles
set is_test_account = true
where id = '17171717-1717-4717-8717-171717171717';

select is(
  (public.claim_daily_attempt(public.current_play_date())).ordinal,
  2::smallint,
  'test mode allocates a separate later ordinal'
);

select public.deactivate_test_mode();

select is(
  (
    select count(*)::integer
    from public.attempts attempt
    join public.daily_play_sessions session on session.attempt_id = attempt.id
    where attempt.user_id = '17171717-1717-4717-8717-171717171717'
      and attempt.play_date = public.current_play_date()
  ),
  1,
  'deactivation preserves the linked normal challenge'
);

select is(
  (
    select count(*)::integer
    from public.attempts attempt
    where attempt.user_id = '17171717-1717-4717-8717-171717171717'
      and attempt.play_date = public.current_play_date()
  ),
  1,
  'deactivation removes only the unlinked test challenge'
);

select * from finish();
rollback;

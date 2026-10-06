begin;

select plan(18);

insert into auth.users (id, is_anonymous)
values
  ('47474747-4747-4474-8474-474747474747', true),
  ('48484848-4848-4484-8484-484848484848', true);

insert into public.referral_codes (user_id, code)
values ('47474747-4747-4474-8474-474747474747', '4747474747474747');

insert into public.referral_acceptances (
  inviter_user_id,
  invitee_user_id,
  invitee_identity_hash,
  referral_code
)
values (
  '47474747-4747-4474-8474-474747474747',
  '48484848-4848-4484-8484-484848484848',
  repeat('4', 64),
  '4747474747474747'
);

select set_config(
  'request.jwt.claim.sub',
  '47474747-4747-4474-8474-474747474747',
  true
);

select is(
  (public.get_or_create_referral_code()->>'code'),
  '4747474747474747',
  'an inviter keeps one stable referral code'
);
select is(
  (public.get_referral_status()->>'invited_count'),
  '1',
  'the inviter sees one accepted invite'
);
select is(
  (public.get_referral_status()->>'completed_count'),
  '0',
  'an invite is pending before the friend plays'
);
select is(
  (public.get_referral_status()->>'pending_count'),
  '1',
  'pending count includes an invitee who has not played'
);

-- Build 21 clients explicitly confirm the start.  Keep the legacy insert
-- trigger from marking this test session as started before the update below.
select set_config('request.headers', '{"x-app-build":"21"}', true);

insert into public.daily_play_sessions (
  user_id,
  play_date,
  ordinal,
  play_mode,
  game_id,
  game_version,
  game_duration_seconds
)
values (
  '48484848-4848-4484-8484-484848484848',
  public.current_play_date(),
  1,
  'practice',
  'dung_dodge_v2',
  1,
  300
);

select set_config(
  'request.jwt.claim.sub',
  '48484848-4848-4484-8484-484848484848',
  true
);

update public.daily_play_sessions
set started_at = now()
where user_id = '48484848-4848-4484-8484-484848484848'
  and play_date = public.current_play_date();

select is(
  (select store_challenge_tickets::text from public.profiles
   where id = '47474747-4747-4474-8474-474747474747'),
  '1',
  'starting the invitee practice grants exactly one challenge ticket'
);
select is(
  (select completed_play_mode from public.referral_acceptances
   where invitee_user_id = '48484848-4848-4484-8484-484848484848'),
  'practice',
  'the reward records whether practice or challenge started'
);
select ok(
  (select played_at is not null and reward_granted_at is not null
   from public.referral_acceptances
   where invitee_user_id = '48484848-4848-4484-8484-484848484848'),
  'the referral is marked played and rewarded atomically'
);

update public.daily_play_sessions
set started_at = now()
where user_id = '48484848-4848-4484-8484-484848484848'
  and play_date = public.current_play_date();

select is(
  (select store_challenge_tickets::text from public.profiles
   where id = '47474747-4747-4474-8474-474747474747'),
  '1',
  'repeating the start callback does not duplicate the ticket'
);

select is(
  (public.get_referral_status()->>'reward_granted'),
  'true',
  'the invitee sees that the referral reward was granted'
);

select set_config(
  'request.jwt.claim.sub',
  '47474747-4747-4474-8474-474747474747',
  true
);
select is(
  (public.get_referral_status()->>'completed_count'),
  '1',
  'the inviter sees the completed referral after the play starts'
);
select is(
  (public.get_referral_status()->>'pending_count'),
  '0',
  'completed referrals leave no pending entry'
);

-- Older supported clients populate started_at in the legacy before-insert
-- trigger.  The referral trigger must reward that real start as well.
insert into auth.users (id, is_anonymous)
values ('4b4b4b4b-4b4b-44b4-84b4-4b4b4b4b4b4b', false);
insert into auth.identities (user_id, provider_id, identity_data, provider)
values (
  '4b4b4b4b-4b4b-44b4-84b4-4b4b4b4b4b4b',
  'referral-legacy-proof',
  '{"sub":"referral-legacy-proof"}',
  'kakao'
);
insert into public.referral_acceptances (
  inviter_user_id,
  invitee_user_id,
  invitee_identity_hash,
  referral_code
)
values (
  '47474747-4747-4474-8474-474747474747',
  '4b4b4b4b-4b4b-44b4-84b4-4b4b4b4b4b4b',
  encode(extensions.digest('kakao:referral-legacy-proof', 'sha256'), 'hex'),
  '4747474747474747'
);
select set_config('request.headers', '{"x-app-build":"11"}', true);
select set_config(
  'request.jwt.claim.sub',
  '4b4b4b4b-4b4b-44b4-84b4-4b4b4b4b4b4b',
  true
);
insert into public.daily_play_sessions (
  user_id,
  play_date,
  ordinal,
  play_mode,
  game_id,
  game_version,
  game_duration_seconds
)
values (
  '4b4b4b4b-4b4b-44b4-84b4-4b4b4b4b4b4b',
  public.current_play_date(),
  1,
  'practice',
  'dung_dodge_v2',
  1,
  300
);
select is(
  (select store_challenge_tickets::text from public.profiles
   where id = '47474747-4747-4474-8474-474747474747'),
  '2',
  'legacy clients also grant one ticket when their started session is inserted'
);
select ok(
  (select played_at is not null and reward_granted_at is not null
   from public.referral_acceptances
   where invitee_user_id = '4b4b4b4b-4b4b-44b4-84b4-4b4b4b4b4b4b'),
  'legacy insert marks the referral played and rewarded'
);

-- A deleted account must not be able to accept a second referral after it is
-- recreated with the same Kakao provider id.  The identity hash is the
-- durable tombstone; the user foreign key is intentionally nullable/set-null.
insert into auth.users (id, is_anonymous)
values ('4c4c4c4c-4c4c-44c4-84c4-4c4c4c4c4c4c', true);
insert into public.referral_codes (user_id, code)
values ('4c4c4c4c-4c4c-44c4-84c4-4c4c4c4c4c4c', '4c4c4c4c4c4c4c4c');
insert into auth.users (id, is_anonymous)
values ('49494949-4949-4494-8494-494949494949', false);
insert into auth.identities (user_id, provider_id, identity_data, provider)
values (
  '49494949-4949-4494-8494-494949494949',
  'referral-delete-proof',
  '{"sub":"referral-delete-proof"}',
  'kakao'
);
select set_config(
  'request.jwt.claim.sub',
  '49494949-4949-4494-8494-494949494949',
  true
);
select is(
  (public.accept_referral('4747474747474747')->>'accepted'),
  'true',
  'a Kakao account can accept one referral'
);
select is(
  (public.accept_referral('4747474747474747')->>'accepted'),
  'true',
  'replaying the same acceptance is idempotent'
);
select throws_ok(
  $$ select public.accept_referral('4c4c4c4c4c4c4c4c') $$,
  'P0001',
  'referral already accepted',
  'one Supabase account cannot accept a second inviter'
);
delete from auth.users
where id = '49494949-4949-4494-8494-494949494949';
select ok(
  exists (
    select 1 from public.referral_acceptances
    where invitee_identity_hash = encode(
      extensions.digest('kakao:referral-delete-proof', 'sha256'),
      'hex'
    )
      and invitee_user_id is null
  ),
  'deleting the account preserves the identity tombstone'
);
insert into auth.users (id, is_anonymous)
values ('4a4a4a4a-4a4a-44a4-84a4-4a4a4a4a4a4a', false);
insert into auth.identities (user_id, provider_id, identity_data, provider)
values (
  '4a4a4a4a-4a4a-44a4-84a4-4a4a4a4a4a4a',
  'referral-delete-proof',
  '{"sub":"referral-delete-proof"}',
  'kakao'
);
select set_config(
  'request.jwt.claim.sub',
  '4a4a4a4a-4a4a-44a4-84a4-4a4a4a4a4a4a',
  true
);
select throws_ok(
  $$ select public.accept_referral('4c4c4c4c4c4c4c4c') $$,
  'P0001',
  'referral identity already accepted',
  'the same Kakao account cannot accept a different referral after deletion'
);

select * from finish();
rollback;

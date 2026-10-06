begin;

select plan(5);

insert into auth.users(id, is_anonymous)
values ('31313131-3131-4131-8131-313131313131', true);

select set_config(
  'request.jwt.claim.sub',
  '31313131-3131-4131-8131-313131313131',
  true
);
set local role authenticated;

select is(
  public.claim_first_challenge_nickname_prompt(),
  false,
  'the prompt is not claimed before the first ranked score'
);
select is(
  (
    select first_challenge_nickname_prompted_at is null
    from public.profiles
    where id = '31313131-3131-4131-8131-313131313131'
  ),
  true,
  'an early check does not consume the one-time prompt'
);

reset role;

insert into public.attempts(
  id, user_id, play_date, game_id, game_version, ordinal, grant_type,
  status, game_duration_seconds
) values (
  '31313131-0000-4131-8131-313131313131',
  '31313131-3131-4131-8131-313131313131',
  public.current_play_date(), 'apple_game_v2', 1, 1, 'daily',
  'submitted', 140
);
insert into public.scores(
  attempt_id, user_id, play_date, game_id, game_version, raw_score,
  duration_ms
) values (
  '31313131-0000-4131-8131-313131313131',
  '31313131-3131-4131-8131-313131313131',
  public.current_play_date(), 'apple_game_v2', 1, 100, 140000
);

set local role authenticated;

select is(
  public.claim_first_challenge_nickname_prompt(),
  true,
  'the generated nickname prompts after the first ranked challenge'
);
select is(
  (
    select first_challenge_nickname_prompted_at is not null
    from public.profiles
    where id = '31313131-3131-4131-8131-313131313131'
  ),
  true,
  'claiming the prompt records the one-time server state'
);
select is(
  public.claim_first_challenge_nickname_prompt(),
  false,
  'the nickname prompt cannot be claimed twice'
);

select * from finish();
rollback;

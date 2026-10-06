begin;

select plan(9);

insert into auth.users (id, is_anonymous)
values ('19191919-1919-4919-8919-191919191919', true);

select set_config(
  'request.jwt.claim.sub',
  '19191919-1919-4919-8919-191919191919',
  true
);

select is(
  public.get_today_state()->'tomorrow'->>'play_date',
  (public.current_play_date() + 1)::text,
  'today state exposes the next play date'
);

select is(
  public.get_today_state()->'tomorrow'->'game'->>'id',
  (
    select game_id
    from public.daily_games
    where play_date = public.current_play_date() + 1
  ),
  'tomorrow preview uses the scheduled game'
);

select is(
  public.claim_preview_practice(
    public.current_play_date(),
    public.current_play_date() + 1,
    '19191919-0000-4000-8000-000000000001'
  )->>'play_date',
  (public.current_play_date() + 1)::text,
  'preview practice seeds gameplay with tomorrow date'
);

select is(
  (
    select play_date::text
    from public.daily_play_sessions
    where user_id = '19191919-1919-4919-8919-191919191919'
  ),
  public.current_play_date()::text,
  'preview practice is charged to today inventory'
);

select is(
  (
    select target_game_date::text
    from public.daily_play_sessions
    where user_id = '19191919-1919-4919-8919-191919191919'
  ),
  (public.current_play_date() + 1)::text,
  'preview practice remembers which game date it targets'
);

select is(
  public.get_today_state()->>'practice_tickets_remaining',
  '0',
  'tomorrow practice consumes the shared ticket'
);

select is(
  public.claim_preview_practice(
    public.current_play_date(),
    public.current_play_date() + 1,
    '19191919-0000-4000-8000-000000000001'
  )->>'id',
  (
    select id::text
    from public.daily_play_sessions
    where user_id = '19191919-1919-4919-8919-191919191919'
  ),
  'preview practice retries are idempotent'
);

select throws_ok(
  $$
    select public.claim_preview_practice(
      public.current_play_date(),
      public.current_play_date() + 2,
      '19191919-0000-4000-8000-000000000002'
    )
  $$,
  'P0001',
  'preview game changed',
  'only tomorrow can be previewed'
);

select throws_ok(
  $$
    select public.claim_daily_attempt(public.current_play_date() + 1)
  $$,
  'P0001',
  'daily game changed',
  'tomorrow ranked challenge remains unavailable'
);

select * from finish();
rollback;

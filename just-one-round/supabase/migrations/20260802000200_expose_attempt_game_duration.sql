-- The attempt already snapshots the issued game duration. Include that
-- snapshot in the state response so the client cannot silently fall back to
-- the game implementation's default after a server-side rollout.
create or replace function public.get_today_state()
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  play_day date := public.current_play_date();
  scheduled_game public.daily_games;
  selected_game public.games;
  device_key text := public.current_device_hash();
  is_test boolean := false;
  selected_test_game_id text;
  ads_enabled boolean := public.rewarded_ads_enabled();
  device_claimed boolean := false;
begin
  scheduled_game := public.ensure_daily_game(play_day);

  select p.is_test_account, p.test_game_id
  into is_test, selected_test_game_id
  from public.profiles p
  where p.id = (select auth.uid());

  if not coalesce(is_test, false) then
    device_claimed := exists (
      select 1
      from public.device_daily_claims claim
      where claim.device_hash = device_key
        and claim.play_date = play_day
    );
  end if;

  if coalesce(is_test, false) and selected_test_game_id is not null then
    select * into selected_game
    from public.games
    where id = selected_test_game_id and is_active;
  end if;

  if selected_game is null then
    select * into selected_game
    from public.games
    where id = scheduled_game.game_id
      and version = scheduled_game.game_version;
  end if;

  return (
    with my_attempts as (
      select *
      from public.attempts
      where user_id = (select auth.uid()) and play_date = play_day
    )
    select jsonb_build_object(
      'play_date', play_day,
      'game', jsonb_build_object(
        'id', selected_game.id,
        'version', selected_game.version,
        'display_name', selected_game.display_name,
        'description', selected_game.description,
        'duration_seconds', selected_game.duration_seconds
      ),
      'nickname', (
        select nickname
        from public.profiles
        where id = (select auth.uid())
      ),
      'attempts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id,
        'ordinal', ordinal,
        'status', status,
        'grant_type', grant_type,
        'game_id', game_id,
        'game_version', game_version,
        'game_duration_seconds', game_duration_seconds,
        'play_date', play_date
      ) order by ordinal) from my_attempts), '[]'::jsonb),
      'test_mode', coalesce(is_test, false),
      'daily_claimed', device_claimed or exists (select 1 from my_attempts),
      'ad_attempt_available', case
        when coalesce(is_test, false) or not ads_enabled then false
        else exists (
          select 1 from my_attempts where ordinal = 1 and status <> 'issued'
        ) and not exists (
          select 1 from my_attempts where ordinal = 2
        )
      end,
      'result', public.get_my_daily_result(play_day)
    )
  );
end;
$$;

revoke all on function public.get_today_state() from public;
grant execute on function public.get_today_state() to authenticated;

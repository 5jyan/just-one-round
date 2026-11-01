-- Return the winner of the most recent scheduled round for one game before a
-- requested date.  The schedule date is resolved first so a later round with
-- no score does not silently fall back to an older winner.
create or replace function public.get_previous_game_winner(
  target_game_id text,
  before_date date
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  cutoff_date date;
  winner_date date;
  winner_user_id uuid;
  winner_nickname text;
  winner_score bigint;
  winner_level integer;
  winner_nickname_color text;
  winner_is_blocked boolean;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if target_game_id is null
    or char_length(btrim(target_game_id)) = 0
    or before_date is null then
    return null;
  end if;

  cutoff_date := least(before_date, public.current_play_date());

  select scheduled.play_date
  into winner_date
  from public.daily_games scheduled
  where scheduled.game_id = target_game_id
    and scheduled.play_date < cutoff_date
  order by scheduled.play_date desc
  limit 1;

  if winner_date is null then
    return null;
  end if;

  select
    score.user_id,
    profile.nickname,
    score.raw_score,
    public.experience_level(coalesce(profile.experience_points, 0)),
    coalesce(to_jsonb(profile)->>'nickname_color', 'default'),
    exists (
      select 1
      from public.blocked_profiles blocked
      where blocked.blocker_id = current_user_id
        and blocked.blocked_id = score.user_id
    )
  into
    winner_user_id,
    winner_nickname,
    winner_score,
    winner_level,
    winner_nickname_color,
    winner_is_blocked
  from public.scores score
  join public.profiles profile on profile.id = score.user_id
  where score.play_date = winner_date
    and score.game_id = target_game_id
    and not coalesce(profile.is_test_account, false)
  order by score.raw_score desc, score.submitted_at asc, score.user_id asc
  limit 1;

  if winner_user_id is null then
    return null;
  end if;

  return jsonb_build_object(
    'score', null,
    'rank', null,
    'nickname', null,
    'participants', 1,
    'top_percent', null,
    'best_score', winner_score,
    'nearby', '[]'::jsonb,
    'leaders', jsonb_build_array(
      jsonb_build_object(
        'rank', 1,
        'user_id', case
          when winner_is_blocked then null
          else winner_user_id
        end,
        'nickname', case
          when winner_is_blocked then '차단한 사용자'
          else coalesce(winner_nickname, '이름 미설정')
        end,
        'score', winner_score,
        'is_me', winner_user_id = current_user_id,
        'is_npc', false,
        'level', coalesce(winner_level, 1),
        'nickname_color', case
          when winner_is_blocked then 'default'
          else coalesce(winner_nickname_color, 'default')
        end
      )
    )
  );
end;
$$;

revoke all on function public.get_previous_game_winner(text, date)
  from public, anon;
grant execute on function public.get_previous_game_winner(text, date)
  to authenticated;

comment on function public.get_previous_game_winner(text, date) is
  'Returns the winner of the latest scheduled round for a game before a date.';

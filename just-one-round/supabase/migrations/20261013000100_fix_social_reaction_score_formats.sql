-- Keep reaction-game boast and inbox labels aligned with the client ranking
-- formatters. These games encode lower-is-better milliseconds as a
-- higher-is-better score (1,000,000 - milliseconds).

create or replace function public.format_social_score(
  target_game_id text,
  target_score integer
)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  safe_score integer;
  elapsed_milliseconds integer;
  centiseconds integer;
begin
  if target_score is null then
    return '-';
  end if;

  safe_score := greatest(target_score, 0);

  case target_game_id
    when 'dung_dodge_v2', 'dung_dodge', 'star_dodge', 'gravity_switch' then
      return to_char(
        safe_score::numeric / 1000,
        'FM9999999990.00'
      ) || '초';

    when 'western_duel' then
      if target_score between 998500 and 999999 then
        return to_char(
          (1000000 - target_score)::numeric / 1000,
          'FM9999999990.000'
        ) || '초';
      end if;
      return '기록 없음';

    when 'mole_reaction' then
      if target_score = 0 then
        return '시간 초과';
      end if;
      if target_score between 1 and 999998 then
        return to_char(
          1000000 - target_score,
          'FM999,999,999,990'
        ) || 'ms';
      end if;
      return to_char(safe_score, 'FM999,999,999,990') || '점';

    when 'number_rush' then
      if target_score = 0 then
        return '0점';
      end if;
      elapsed_milliseconds := greatest(
        least(3600000 - target_score, 3599999),
        1
      );
      centiseconds := round(elapsed_milliseconds::numeric / 10)::integer;
      return to_char(
        centiseconds::numeric / 100,
        'FM9999999990.00'
      ) || '초';

    when 'ramen_timer' then
      if target_score = 0 then
        return '시간 초과';
      end if;
      -- Ramen Timer accepts scores from 3,525,750 through 3,600,000.
      -- Keep malformed historical rows readable instead of breaking a push.
      if target_score < 3525750 or target_score > 3600000 then
        return to_char(safe_score, 'FM999,999,999,990') || '점';
      end if;
      elapsed_milliseconds := 3600000 - target_score;
      centiseconds := round(elapsed_milliseconds::numeric / 10)::integer;
      return '총 오차 ' || to_char(
        centiseconds::numeric / 100,
        'FM9999999990.00'
      ) || '초';

    when 'ten_pitch_slugger' then
      return to_char(
        safe_score::numeric / 100,
        'FM999,999,999,990.00'
      ) || 'm';

    when 'apple_game_v2', 'apple_game' then
      return safe_score::text || '개';

    when 'sausage_dachshund', 'midnight_snake' then
      return safe_score::text || '개';

    when 'beat_the_dealer' then
      return least(safe_score, 925)::text || '코인';

    when 'failed_bakery' then
      return safe_score::text || '층';

    when 'mama_duck_trail', 'bathhouse_sort', 'lily_frog', 'net_boat' then
      return to_char(safe_score, 'FM999,999,999,990') || '점';

    else
      -- Unknown historical games still get a readable, grouped score.
      return to_char(safe_score, 'FM999,999,999,990') || '점';
  end case;
end;
$$;

revoke all on function public.format_social_score(text, integer)
  from public, anon, authenticated, service_role;

comment on function public.format_social_score(text, integer) is
  'Formats stored game scores for social inbox and push messages, including reaction-game time labels.';

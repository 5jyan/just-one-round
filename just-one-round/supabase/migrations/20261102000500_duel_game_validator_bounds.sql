-- Tighten duel result contracts to the current game-rule constants.
--
-- This migration intentionally does not enable any game. `duel_enabled` stays
-- an explicit operator gate until each game's full replay/anti-cheat policy is
-- approved. These bounds prevent impossible scores and, where the runtime
-- defines a deterministic score/time relation, enforce that relation too.

create or replace function public.duel_score_upper_bound(
  target_game_id text,
  target_game_version integer,
  target_duration_seconds integer
)
returns bigint
language sql
immutable
security definer set search_path = ''
as $function$
  select case target_game_id
    -- Survival score is the exact elapsed runtime in milliseconds.
    when 'dung_dodge_v2' then greatest(target_duration_seconds, 1)::bigint * 1000
    when 'gravity_switch' then greatest(target_duration_seconds, 1)::bigint * 1000
    -- Apple board is 13 x 8 cells; one removed cell is one point.
    when 'apple_game_v2' then 104
    when 'number_rush' then 3599999
    when 'mole_reaction' then 1000000
    when 'mama_duck_trail' then 100000
    when 'midnight_snake' then 149
    when 'beat_the_dealer' then 925
    when 'ten_pitch_slugger' then 16875
    when 'ramen_timer' then 3600000
    when 'bathhouse_sort' then 1000000
    when 'lily_frog' then 200000
    when 'net_boat' then 1000000
    when 'temple_run' then 100000
    else null
  end;
$function$;

create or replace function public.validate_duel_score(
  target_game_id text,
  target_game_version integer,
  target_duration_seconds integer,
  submitted_score bigint,
  submitted_duration_ms integer,
  target_result_kind text
)
returns void
language plpgsql
security definer set search_path = ''
as $function$
declare
  upper_bound bigint;
  expected_score bigint;
begin
  if target_result_kind = 'no_result' then
    if submitted_score <> 0 then
      raise exception 'no-result score must be zero';
    end if;
    return;
  end if;

  upper_bound := public.duel_score_upper_bound(
    target_game_id, target_game_version, target_duration_seconds
  );
  if upper_bound is null then
    raise exception 'game has no duel validator';
  end if;
  if submitted_score is null or submitted_score < 0
    or submitted_score > upper_bound then
    raise exception 'duel score is outside the game contract';
  end if;
  if submitted_duration_ms is null or submitted_duration_ms < 0
    or submitted_duration_ms > (target_duration_seconds + 120) * 1000 then
    raise exception 'duel duration is outside the game contract';
  end if;
  if submitted_duration_ms > target_duration_seconds * 1000 then
    raise exception 'duel duration exceeds game runtime';
  end if;

  -- These two games publish the exact elapsed survival time as both score and
  -- duration. A cap alone would let a client submit an invented survival
  -- score while still looking like a plausible duration.
  if target_game_id in ('dung_dodge_v2', 'gravity_switch')
    and submitted_score <> submitted_duration_ms then
    raise exception 'survival score must equal submitted duration';
  end if;

  -- Tap50 ranks a non-timeout run as ceiling - elapsed milliseconds. Zero is
  -- the valid timeout sentinel and is only legal after the scheduled runtime.
  if target_game_id = 'number_rush' then
    if submitted_score = 0 then
      if submitted_duration_ms < target_duration_seconds * 1000 then
        raise exception 'timeout score requires the full game duration';
      end if;
    else
      expected_score := greatest(
        1,
        least(3599999, 3600000 - submitted_duration_ms::bigint)
      );
      if submitted_score <> expected_score then
        raise exception 'tap50 score must match submitted duration';
      end if;
    end if;
  end if;

  -- Ramen scores are quantized to 10 ms and must remain in the normal score
  -- band declared by RamenTimerRules. Zero is reserved for a full timeout.
  if target_game_id = 'ramen_timer' then
    if submitted_score = 0 then
      if submitted_duration_ms < target_duration_seconds * 1000 then
        raise exception 'timeout score requires the full game duration';
      end if;
    elsif submitted_duration_ms < 3200
      or submitted_score < 3525750
      or submitted_score % 10 <> 0 then
      raise exception 'ramen score is outside the quantized game contract';
    end if;
  end if;
end;
$function$;

revoke all on function public.duel_score_upper_bound(text, integer, integer),
  public.validate_duel_score(text, integer, integer, bigint, integer, text)
  from public, anon, authenticated;

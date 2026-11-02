-- Keep the runtime-duration guard as a separate migration so environments
-- that already applied 20261102000500 receive the same contract. A result
-- cannot claim more play time than the server-declared game runtime.

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

  if target_game_id in ('dung_dodge_v2', 'gravity_switch')
    and submitted_score <> submitted_duration_ms then
    raise exception 'survival score must equal submitted duration';
  end if;

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

revoke all on function public.validate_duel_score(
  text, integer, integer, bigint, integer, text
) from public, anon, authenticated;

-- Keep the 30 C daily participation reward and update the ranking bonuses.
-- First place remains a special +250 C bonus.

create or replace function public.daily_result_reward_coins(
  result_rank integer,
  result_participants integer
)
returns integer
language plpgsql
immutable
security definer set search_path = ''
as $$
declare
  top_percent integer;
  ranking_bonus integer;
begin
  if result_rank <= 0
    or result_participants <= 0
    or result_rank > result_participants then
    return 0;
  end if;

  if result_rank = 1 then
    ranking_bonus := 250;
  else
    top_percent := greatest(
      1,
      ceil(result_rank::numeric * 100 / result_participants)::integer
    );

    if top_percent <= 10 then
      ranking_bonus := 120;
    elsif top_percent <= 30 then
      ranking_bonus := 80;
    elsif top_percent <= 50 then
      ranking_bonus := 50;
    elsif top_percent <= 70 then
      ranking_bonus := 20;
    else
      ranking_bonus := 0;
    end if;
  end if;

  return 30 + ranking_bonus;
end;
$$;

revoke all on function public.daily_result_reward_coins(integer, integer)
  from public, anon, authenticated;

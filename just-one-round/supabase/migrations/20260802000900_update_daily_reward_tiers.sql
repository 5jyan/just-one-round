-- Update the previous-day ranking reward table without changing the
-- idempotent acknowledgement and economy ledger flow.

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
begin
  if result_rank <= 0
    or result_participants <= 0
    or result_rank > result_participants then
    return 0;
  end if;

  if result_rank = 1 then return 100; end if;
  if result_rank = 2 then return 80; end if;
  if result_rank = 3 then return 70; end if;

  top_percent := greatest(
    1,
    ceil(result_rank::numeric * 100 / result_participants)::integer
  );

  if top_percent <= 10 then return 50; end if;
  if top_percent <= 30 then return 40; end if;
  if top_percent <= 50 then return 30; end if;
  if top_percent <= 70 then return 10; end if;
  return 5;
end;
$$;

revoke all on function public.daily_result_reward_coins(integer, integer)
  from public, anon, authenticated;

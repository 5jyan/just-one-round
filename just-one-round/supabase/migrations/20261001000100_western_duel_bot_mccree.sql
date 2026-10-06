-- Rename only future fallback BOT assignments. Existing opponent snapshots
-- deliberately keep the name shown when their attempt began.
do $migration$
declare
  definition text;
begin
  definition := pg_catalog.pg_get_functiondef(
    'public.confirm_western_duel_started(uuid)'::pg_catalog.regprocedure
  );
  if pg_catalog.strpos(definition, '떠돌이 총잡이') = 0 then
    if pg_catalog.strpos(definition, '맥크리') > 0 then
      return;
    end if;
    raise exception 'western duel BOT name source not found';
  end if;
  execute pg_catalog.replace(definition, '떠돌이 총잡이', '맥크리');
end;
$migration$;

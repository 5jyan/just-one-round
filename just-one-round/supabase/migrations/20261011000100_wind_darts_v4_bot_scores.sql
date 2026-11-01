-- Keep existing opponent snapshots unchanged while using the approved v4 bot
-- score for future sessions.
do $migration$
declare
  definition text;
  old_marker constant text :=
    'array[60,60,60,60,60,60,120]::smallint[], 480, true';
  new_marker constant text :=
    'array[7,19,10,20,6,9,22]::smallint[], 93, true';
  old_count integer;
  new_count integer;
begin
  if pg_catalog.to_regprocedure(
    'public.confirm_wind_darts_started(uuid)'
  ) is null then
    raise exception 'wind darts v4 opponent function not found';
  end if;

  definition := pg_catalog.pg_get_functiondef(
    'public.confirm_wind_darts_started(uuid)'::pg_catalog.regprocedure
  );
  old_count := (
    pg_catalog.length(definition)
    - pg_catalog.length(pg_catalog.replace(definition, old_marker, ''))
  ) / pg_catalog.length(old_marker);
  new_count := (
    pg_catalog.length(definition)
    - pg_catalog.length(pg_catalog.replace(definition, new_marker, ''))
  ) / pg_catalog.length(new_marker);

  if old_count = 0 and new_count = 1 then
    return;
  end if;
  if old_count <> 1 or new_count <> 0 then
    raise exception
      'wind darts v4 BOT score marker mismatch (old %, new %)',
      old_count, new_count;
  end if;

  execute pg_catalog.replace(definition, old_marker, new_marker);
end;
$migration$;

-- A started duel must have an active background settlement job even when both
-- participants go offline. Viewer-side recovery handles delayed executions.
create or replace function public.guard_duel_account_deletion()
returns trigger language plpgsql security definer set search_path = '' as $function$
declare maintenance_active boolean := false;
begin
  if exists (select 1 from public.duel_account_deletions d
      where d.user_id in (new.requester_id, new.opponent_id)) then
    raise exception 'duel participant account is being deleted';
  end if;
  if tg_op = 'UPDATE' and new.status = 'starting' and old.status = 'waiting' then
    if to_regnamespace('cron') is not null then
      begin
        execute 'select exists(select 1 from cron.job where jobname = $1 and active)'
          into maintenance_active using 'just-one-round-maintain-duels';
      exception when others then
        maintenance_active := false;
      end;
    end if;
    if not maintenance_active then
      raise exception 'duel maintenance is unavailable';
    end if;
  end if;
  return new;
end;
$function$;

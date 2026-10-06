-- The one-warmup/one-golden rules were published as immutable v2 by the
-- preceding migration. Keep this migration as a forward-only verification
-- marker for the previously planned, but never shipped, v1 edit.
do $$
begin
  if not exists (
    select 1
    from public.games
    where id = 'mole_reaction'
      and version = 2
      and minimum_app_build = 25
  ) then
    raise exception 'mole reaction v2 rollout is missing';
  end if;
end;
$$;

-- Update only the player-facing metadata for the staged Temple Run entry.
-- The rules version, activation state, schedules, attempts, and scores stay
-- unchanged. The version snapshot is updated first so the existing metadata
-- immutability trigger accepts the matching catalog update.
--
-- Rollback: use a separate forward migration to restore the previous title
-- and description if product copy needs to be reverted.
update public.game_rule_versions
set display_name = '집에 좀 가자',
    description =
      '상자와 셔터를 피해 골목을 달리고 공사 도랑을 뛰어넘어 집에 도착하세요.'
where game_id = 'temple_run';

update public.games
set display_name = '집에 좀 가자',
    description =
      '상자와 셔터를 피해 골목을 달리고 공사 도랑을 뛰어넘어 집에 도착하세요.'
where id = 'temple_run';

do $$
declare
  versioned_count integer;
begin
  select count(*)
  into versioned_count
  from public.game_rule_versions
  where game_id = 'temple_run';

  if versioned_count = 0 then
    raise exception 'Temple Run rule snapshot is missing';
  end if;

  if exists (
    select 1
    from public.games
    where id = 'temple_run'
      and (
        version <> 1
        or duration_seconds <> 300
        or minimum_app_build <> 31
      )
  ) then
    raise exception 'Temple Run rules metadata changed unexpectedly';
  end if;

  if exists (
    select 1
    from public.game_rule_versions
    where game_id = 'temple_run'
      and (
        display_name <> '집에 좀 가자'
        or description <>
          '상자와 셔터를 피해 골목을 달리고 공사 도랑을 뛰어넘어 집에 도착하세요.'
      )
  ) then
    raise exception 'Temple Run metadata snapshot did not update';
  end if;
end;
$$;

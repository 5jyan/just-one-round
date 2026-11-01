-- Run after 20261012000400_sort_daily_nonplayers_by_level.sql inside a transaction.
begin;

select plan(4);

do $$
declare
  play_day date := public.current_play_date();
  game_id text := 'dung_dodge_v2';
  viewer uuid := '74000000-0000-4000-8000-000000000001';
  level_30 uuid := 'ffffffff-ffff-4fff-8fff-ffffffffffff';
  level_25 uuid := '74000000-0000-4000-8000-000000000025';
  level_20 uuid := '74000000-0000-4000-8000-000000000020';
  level_15 uuid := '74000000-0000-4000-8000-000000000015';
  level_10 uuid := '74000000-0000-4000-8000-000000000010';
  level_5_more_xp uuid := '74000000-0000-4000-8000-000000000005';
  level_5_equal_a uuid := '74000000-0000-4000-8000-000000000006';
  level_5_equal_b uuid := '74000000-0000-4000-8000-000000000007';
  response jsonb;
  page_one jsonb;
  page_two jsonb;
  page_three jsonb;
  page_four jsonb;
  all_ids uuid[];
  page_ids uuid[];
  expected_ids uuid[] := array[
    level_30, level_25, level_20, level_15, level_10,
    level_5_more_xp, level_5_equal_a, level_5_equal_b
  ];
  cursor text;
begin
  insert into auth.users(id, is_anonymous) values
    (viewer, true),
    (level_30, true),
    (level_25, true),
    (level_20, true),
    (level_15, true),
    (level_10, true),
    (level_5_more_xp, true),
    (level_5_equal_a, true),
    (level_5_equal_b, true);

  update public.profiles
  set is_test_account = true
  where is_test_account is not true
    and id not in (
      viewer, level_30, level_25, level_20, level_15,
      level_10, level_5_more_xp, level_5_equal_a, level_5_equal_b
    );

  update public.profiles
  set
    nickname = case id
      when viewer then '정렬 조회자'
      when level_30 then '레벨30'
      when level_25 then '레벨25'
      when level_20 then '레벨20'
      when level_15 then '레벨15'
      when level_10 then '레벨10'
      when level_5_more_xp then '레벨5 진행'
      when level_5_equal_a then '레벨5 동률A'
      when level_5_equal_b then '레벨5 동률B'
    end,
    experience_points = case id
      when level_30 then public.experience_threshold(30)
      when level_25 then public.experience_threshold(25)
      when level_20 then public.experience_threshold(20)
      when level_15 then public.experience_threshold(15)
      when level_10 then public.experience_threshold(10)
      when level_5_more_xp then public.experience_threshold(5) + 100
      when level_5_equal_a then public.experience_threshold(5)
      when level_5_equal_b then public.experience_threshold(5)
      else experience_points
    end
  where id in (
    viewer, level_30, level_25, level_20, level_15,
    level_10, level_5_more_xp, level_5_equal_a, level_5_equal_b
  );

  perform set_config('request.jwt.claim.sub', viewer::text, true);

  response := public.get_daily_nonplayers(play_day, game_id, null, 100);
  select array_agg((item.value->>'user_id')::uuid order by item.ordinality)
  into all_ids
  from jsonb_array_elements(response->'players')
    with ordinality as item(value, ordinality);
  if all_ids is distinct from expected_ids then
    raise exception 'global experience ordering changed: expected %, got %',
      expected_ids, all_ids;
  end if;
  if response->'players'->0->>'level' <> '30'
    or response->'players'->5->>'level' <> '5'
    or response->'players'->6->>'user_id' <> level_5_equal_a::text
    or response->'players'->7->>'user_id' <> level_5_equal_b::text then
    raise exception 'level or UUID tie ordering is incorrect: %', response;
  end if;

  page_one := public.get_daily_nonplayers(play_day, game_id, null, 2);
  if page_one->>'next_cursor' <> page_one->'players'->1->>'user_id' then
    raise exception 'page one cursor is not its last returned UUID: %', page_one;
  end if;
  cursor := page_one->>'next_cursor';
  page_two := public.get_daily_nonplayers(play_day, game_id, cursor::uuid, 2);
  if page_two->>'next_cursor' <> page_two->'players'->1->>'user_id' then
    raise exception 'page two cursor is not its last returned UUID: %', page_two;
  end if;
  cursor := page_two->>'next_cursor';
  page_three := public.get_daily_nonplayers(play_day, game_id, cursor::uuid, 2);
  if page_three->>'next_cursor' <> page_three->'players'->1->>'user_id' then
    raise exception 'page three cursor is not its last returned UUID: %', page_three;
  end if;
  cursor := page_three->>'next_cursor';
  page_four := public.get_daily_nonplayers(play_day, game_id, cursor::uuid, 2);
  if page_four->>'next_cursor' is not null
    or jsonb_array_length(page_four->'players') <> 2 then
    raise exception 'page four should be the final complete page: %', page_four;
  end if;

  select array_agg((pages.value->>'user_id')::uuid
    order by pages.page_order, pages.item_order)
  into page_ids
  from (
    select item.value, 1 as page_order, item.ordinality as item_order
    from jsonb_array_elements(page_one->'players')
      with ordinality as item(value, ordinality)
    union all
    select item.value, 2, item.ordinality
    from jsonb_array_elements(page_two->'players')
      with ordinality as item(value, ordinality)
    union all
    select item.value, 3, item.ordinality
    from jsonb_array_elements(page_three->'players')
      with ordinality as item(value, ordinality)
    union all
    select item.value, 4, item.ordinality
    from jsonb_array_elements(page_four->'players')
      with ordinality as item(value, ordinality)
  ) pages;
  if page_ids is distinct from expected_ids then
    raise exception 'pagination skipped or repeated profiles: expected %, got %',
      expected_ids, page_ids;
  end if;

  begin
    perform public.get_daily_nonplayers(
      play_day,
      game_id,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
      2
    );
    raise exception 'expected invalid cursor error';
  exception when others then
    if sqlerrm <> 'invalid cursor' then
      raise;
    end if;
  end;
end;
$$;

select pass('daily nonplayers sort by level and cursor pagination are deterministic');
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_daily_nonplayers(date,text,uuid,integer)',
    'execute'
  ),
  'authenticated role can execute sorted daily nonplayers RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_daily_nonplayers(date,text,uuid,integer)',
    'execute'
  ),
  'anon role cannot execute sorted daily nonplayers RPC'
);
select ok(
  not has_function_privilege(
    'public',
    'public.get_daily_nonplayers(date,text,uuid,integer)',
    'execute'
  ),
  'public role cannot execute sorted daily nonplayers RPC'
);

select * from finish();

rollback;

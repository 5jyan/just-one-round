begin;

select plan(50);

-- The local validation gate currently stages every active, non-linked game.
update public.games
set duel_enabled = true
where is_active and id not in ('wind_darts', 'western_duel');

select is(
  (select count(*)::text from public.games
   where is_active and duel_enabled
     and id not in ('wind_darts', 'western_duel')),
  '13',
  'local duel gate covers the 13 active supported games'
);

-- The database snapshot and the runtime rule constants agree on the current
-- duration for every staged game. This is intentionally explicit rather than
-- deriving the expected value from the same table under test.
select is(
  (select count(*)::text
   from (values
     ('apple_game_v2', 140),
     ('bathhouse_sort', 60),
     ('beat_the_dealer', 180),
     ('dung_dodge_v2', 300),
     ('gravity_switch', 300),
     ('lily_frog', 150),
     ('mama_duck_trail', 120),
     ('midnight_snake', 300),
     ('net_boat', 300),
     ('number_rush', 180),
     ('ramen_timer', 45),
     ('temple_run', 300),
     ('ten_pitch_slugger', 300)
   ) expected(game_id, duration_seconds)
   join public.games game on game.id = expected.game_id
     and game.duration_seconds = expected.duration_seconds
     and game.is_active),
  '13',
  'staged game durations match their runtime contracts'
);

select is(public.duel_score_upper_bound('apple_game_v2', 1, 140), 104::bigint,
  'apple validator uses the 13x8 board cell ceiling');
select is(public.duel_score_upper_bound('bathhouse_sort', 11, 60), 1000000::bigint,
  'bathhouse validator uses its runtime score cap');
select is(public.duel_score_upper_bound('beat_the_dealer', 4, 180), 925::bigint,
  'blackjack validator uses its maximum settlement score');
select is(public.duel_score_upper_bound('dung_dodge_v2', 1, 300), 300000::bigint,
  'dung dodge validator uses the duration in milliseconds');
select is(public.duel_score_upper_bound('gravity_switch', 1, 300), 300000::bigint,
  'gravity switch validator uses the duration in milliseconds');
select is(public.duel_score_upper_bound('lily_frog', 5, 150), 200000::bigint,
  'lily frog validator uses the submitted score ceiling');
select is(public.duel_score_upper_bound('mama_duck_trail', 1, 120), 100000::bigint,
  'mama duck validator uses the submitted score ceiling');
select is(public.duel_score_upper_bound('midnight_snake', 3, 300), 149::bigint,
  'midnight snake validator uses the finite board ceiling');
select is(public.duel_score_upper_bound('net_boat', 3, 300), 1000000::bigint,
  'net boat validator uses the submitted score ceiling');
select is(public.duel_score_upper_bound('number_rush', 1, 180), 3599999::bigint,
  'tap50 validator excludes the unreachable ranking ceiling sentinel');
select is(public.duel_score_upper_bound('ramen_timer', 3, 45), 3600000::bigint,
  'ramen validator keeps the perfect score ceiling');
select is(public.duel_score_upper_bound('temple_run', 1, 300), 100000::bigint,
  'temple run validator uses its submitted score ceiling');
select is(public.duel_score_upper_bound('ten_pitch_slugger', 8, 300), 16875::bigint,
  'slugger validator uses its theoretical maximum distance');

-- One valid boundary value per active game.
select lives_ok($$ select public.validate_duel_score(
  'apple_game_v2', 1, 140, 104, 0, 'valid') $$,
  'apple accepts its maximum valid score');
select lives_ok($$ select public.validate_duel_score(
  'bathhouse_sort', 11, 60, 1000000, 0, 'valid') $$,
  'bathhouse accepts its maximum valid score');
select lives_ok($$ select public.validate_duel_score(
  'beat_the_dealer', 4, 180, 925, 0, 'valid') $$,
  'blackjack accepts its maximum valid score');
select lives_ok($$ select public.validate_duel_score(
  'dung_dodge_v2', 1, 300, 300000, 300000, 'valid') $$,
  'dung dodge accepts a duration-matched maximum score');
select lives_ok($$ select public.validate_duel_score(
  'gravity_switch', 1, 300, 300000, 300000, 'valid') $$,
  'gravity switch accepts a duration-matched maximum score');
select lives_ok($$ select public.validate_duel_score(
  'lily_frog', 5, 150, 200000, 0, 'valid') $$,
  'lily frog accepts its maximum valid score');
select lives_ok($$ select public.validate_duel_score(
  'mama_duck_trail', 1, 120, 100000, 0, 'valid') $$,
  'mama duck accepts its maximum valid score');
select lives_ok($$ select public.validate_duel_score(
  'midnight_snake', 3, 300, 149, 0, 'valid') $$,
  'midnight snake accepts its maximum valid score');
select lives_ok($$ select public.validate_duel_score(
  'net_boat', 3, 300, 1000000, 0, 'valid') $$,
  'net boat accepts its maximum valid score');
select lives_ok($$ select public.validate_duel_score(
  'number_rush', 1, 180, 3599999, 1, 'valid') $$,
  'tap50 accepts a score derived from one millisecond');
select lives_ok($$ select public.validate_duel_score(
  'ramen_timer', 3, 45, 3600000, 3200, 'valid') $$,
  'ramen accepts the quantized perfect score after input unlock');
select lives_ok($$ select public.validate_duel_score(
  'temple_run', 1, 300, 100000, 0, 'valid') $$,
  'temple run accepts its maximum valid score');
select lives_ok($$ select public.validate_duel_score(
  'ten_pitch_slugger', 8, 300, 16875, 0, 'valid') $$,
  'slugger accepts its theoretical maximum score');

-- One impossible value above each game's runtime ceiling.
select throws_ok($$ select public.validate_duel_score(
  'apple_game_v2', 1, 140, 105, 0, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'apple rejects a score above the board ceiling');
select throws_ok($$ select public.validate_duel_score(
  'bathhouse_sort', 11, 60, 1000001, 0, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'bathhouse rejects a score above the runtime cap');
select throws_ok($$ select public.validate_duel_score(
  'beat_the_dealer', 4, 180, 926, 0, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'blackjack rejects a score above the settlement cap');
select throws_ok($$ select public.validate_duel_score(
  'dung_dodge_v2', 1, 300, 300001, 300001, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'dung dodge rejects a score above the duration ceiling');
select throws_ok($$ select public.validate_duel_score(
  'gravity_switch', 1, 300, 300001, 300001, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'gravity switch rejects a score above the duration ceiling');
select throws_ok($$ select public.validate_duel_score(
  'lily_frog', 5, 150, 200001, 0, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'lily frog rejects a score above the runtime cap');
select throws_ok($$ select public.validate_duel_score(
  'mama_duck_trail', 1, 120, 100001, 0, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'mama duck rejects a score above the runtime cap');
select throws_ok($$ select public.validate_duel_score(
  'midnight_snake', 3, 300, 150, 0, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'midnight snake rejects a score above the finite board ceiling');
select throws_ok($$ select public.validate_duel_score(
  'net_boat', 3, 300, 1000001, 0, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'net boat rejects a score above the runtime cap');
select throws_ok($$ select public.validate_duel_score(
  'number_rush', 1, 180, 3600000, 1, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'tap50 rejects the unreachable ranking ceiling sentinel');
select throws_ok($$ select public.validate_duel_score(
  'ramen_timer', 3, 45, 3600001, 3200, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'ramen rejects a score above the perfect ceiling');
select throws_ok($$ select public.validate_duel_score(
  'temple_run', 1, 300, 100001, 0, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'temple run rejects a score above the runtime cap');
select throws_ok($$ select public.validate_duel_score(
  'ten_pitch_slugger', 8, 300, 16876, 0, 'valid') $$,
  'P0001', 'duel score is outside the game contract',
  'slugger rejects a score above its theoretical maximum');

-- Deterministic score/time contracts catch plausible-looking forged results.
select throws_ok($$ select public.validate_duel_score(
  'dung_dodge_v2', 1, 300, 299999, 300000, 'valid') $$,
  'P0001', 'survival score must equal submitted duration',
  'dung dodge rejects a score that does not equal elapsed time');
select throws_ok($$ select public.validate_duel_score(
  'gravity_switch', 1, 300, 299999, 300000, 'valid') $$,
  'P0001', 'survival score must equal submitted duration',
  'gravity switch rejects a score that does not equal elapsed time');
select throws_ok($$ select public.validate_duel_score(
  'number_rush', 1, 180, 3599999, 2, 'valid') $$,
  'P0001', 'tap50 score must match submitted duration',
  'tap50 rejects a score that does not match elapsed time');
select throws_ok($$ select public.validate_duel_score(
  'number_rush', 1, 180, 0, 1, 'valid') $$,
  'P0001', 'timeout score requires the full game duration',
  'tap50 rejects an early timeout sentinel');
select throws_ok($$ select public.validate_duel_score(
  'ramen_timer', 3, 45, 3599999, 3200, 'valid') $$,
  'P0001', 'ramen score is outside the quantized game contract',
  'ramen rejects a non-quantized score');
select throws_ok($$ select public.validate_duel_score(
  'ramen_timer', 3, 45, 3525740, 3200, 'valid') $$,
  'P0001', 'ramen score is outside the quantized game contract',
  'ramen rejects a score below its declared normal band');
select throws_ok($$ select public.validate_duel_score(
  'ramen_timer', 3, 45, 3600000, 1000, 'valid') $$,
  'P0001', 'ramen score is outside the quantized game contract',
  'ramen rejects a result before input unlock');
select throws_ok($$ select public.validate_duel_score(
  'ramen_timer', 3, 45, 0, 1000, 'valid') $$,
  'P0001', 'timeout score requires the full game duration',
  'ramen rejects an early timeout sentinel');
select throws_ok($$ select public.validate_duel_score(
  'apple_game_v2', 1, 140, 104, 140001, 'valid') $$,
  'P0001', 'duel duration exceeds game runtime',
  'all games reject a result duration past the runtime ceiling');

select * from finish();
rollback;

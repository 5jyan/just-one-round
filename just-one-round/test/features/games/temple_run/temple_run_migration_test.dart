import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Temple Run is staged without changing the daily schedule', () {
    final migration = File('supabase/migrations/20261015000100_temple_run.sql');
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("'temple_run', 1"));
    expect(sql, contains("'유적 질주'"));
    expect(sql, contains('duration_seconds,'));
    expect(sql, contains('  300, false, 31'));
    expect(sql, contains('drop constraint if exists scores_stars_range'));
    expect(sql, contains('stars_collected between 0 and 1000'));
    expect(sql, contains('is_active = false'));
    expect(sql, contains("id in ('wind_darts', 'temple_run')"));
    expect(sql, contains('claim_test_temple_run_attempt_v1'));
    expect(sql, contains('daily_play_sessions'));
    expect(sql, contains('get_today_state_before_temple_run'));
    expect(sql, contains('submit_daily_score_before_temple_run'));
    expect(sql, contains('active_attempt.game_duration_seconds <> 300'));
    expect(sql, contains('stars_collected not between 0 and 1000'));
    expect(sql, contains('raw_score not between 0 and 100000'));
    expect(sql, contains('distance_component < 0'));
    expect(sql, contains('collisions not between 0 and 200'));
    expect(
      sql,
      contains('maximum_distance := ceil(duration_ms / 1000.0 * 24.0)'),
    );
    expect(sql, contains('distance_component > maximum_distance'));
    expect(sql, contains('duration_ms, stars_collected, collisions'));
  });

  test(
    'SQL smoke test exercises selection, claim, score, retry, and rejection',
    () {
      final smokeTest = File('supabase/tests/temple_run_scores_test.sql');
      expect(smokeTest.existsSync(), isTrue);
      final sql = smokeTest.readAsStringSync();

      expect(sql, startsWith('-- Run after 20261015000100_temple_run.sql'));
      expect(sql, contains("test_game_id = 'temple_run'"));
      expect(sql, contains('public.get_developer_games()'));
      expect(sql, contains('public.get_today_state()'));
      expect(sql, contains('public.claim_daily_attempt(play_day)'));
      expect(
        sql,
        contains(
          'public.submit_daily_score(claim_attempt, 6000, 3, 0, 300000)',
        ),
      );
      expect(sql, contains('score retry inserted a duplicate'));
      expect(sql, contains('100001'));
      expect(sql, contains('physically impossible distance was accepted'));
      expect(sql, contains('collisions=2'));
      expect(sql, contains('collisions=1'));
      expect(sql.trimRight(), endsWith('rollback;'));
    },
  );
}

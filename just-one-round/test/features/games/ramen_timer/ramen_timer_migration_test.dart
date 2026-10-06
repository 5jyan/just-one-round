import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server migration validates the ramen timer score contract', () {
    final migration = File(
      'supabase/migrations/20260808000500_ramen_timer.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("'ramen_timer'"));
    expect(sql, contains("'10·20·30! 컵라면'"));
    expect(sql, contains('scheduled_duration <> 45'));
    expect(sql, contains('submitted_score = 0'));
    expect(sql, contains('duration_ms = 45000'));
    expect(sql, contains('submitted_score between 3525750 and 3600000'));
    expect(sql, contains('submitted_score % 10 = 0'));
    expect(sql, contains('duration_ms between 3700 and 45000'));
    expect(sql, contains('duration_ms % 10 = 0'));
    expect(
      sql,
      contains('3600000 - submitted_score >= abs(duration_ms - 30000)'),
    );
    expect(sql, contains("raise exception 'invalid ramen timer result'"));
  });

  test('server copy describes the two smoke hint windows', () {
    final migration = File(
      'supabase/migrations/20260808000800_ramen_timer_smoke_hints.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("'ramen_timer',\n  2,"));
    expect(sql, contains('12~13초'));
    expect(sql, contains('22~23초'));
  });

  test('server copy renames the game to 30초 컵라면', () {
    final migration = File(
      'supabase/migrations/20260808000900_rename_ramen_timer.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("'ramen_timer',\n  3,"));
    expect(sql, contains("'30초 컵라면'"));
    expect(sql, contains('active_attempt.game_version not in (1, 2, 3)'));
  });

  test('v4 replaces automatic clock peeks with immediate error feedback', () {
    final migration = File(
      'supabase/migrations/20260920000100_ramen_timer_immediate_error_feedback_v4.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains('set version = 4'));
    expect(sql, contains("game_version is distinct from 4"));
    expect(sql, contains('submitted_score between 3525750 and 3600000'));
    expect(sql, contains('duration_ms between 3700 and 45000'));
    expect(sql, contains('첫 두 입력의 목표 오차'));
    expect(sql, isNot(contains('12~13초')));
    expect(sql, isNot(contains('22~23초')));
  });

  test('Android Alpha rollback restores v3 without rewriting attempts', () {
    final migration = File(
      'supabase/migrations/20260928000100_rollback_ramen_timer_to_v3.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains('version = 3'));
    expect(sql, contains('set game_version = 3'));
    expect(sql, contains("where game_id = 'ramen_timer'"));
    expect(sql, isNot(contains('update public.attempts')));
    expect(sql, isNot(contains('update public.scores')));
  });
}

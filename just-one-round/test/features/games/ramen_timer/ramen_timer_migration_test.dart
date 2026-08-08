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

    expect(sql, contains("where id = 'ramen_timer' and version = 1"));
    expect(sql, contains('12~13초'));
    expect(sql, contains('22~23초'));
  });

  test('server copy renames the game to 30초 컵라면', () {
    final migration = File(
      'supabase/migrations/20260808000900_rename_ramen_timer.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("display_name = '30초 컵라면'"));
    expect(sql, contains("where id = 'ramen_timer' and version = 1"));
  });
}

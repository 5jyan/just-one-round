import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server migration validates the ten-pitch maximum distance contract', () {
    final migration = File(
      'supabase/migrations/20260808000700_ten_pitch_slugger_stronger_late_bonus_v7.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("'ten_pitch_slugger'"));
    expect(
      sql,
      contains("active_attempt.game_version not in (1, 2, 3, 4, 5, 6, 7)"),
    );
    expect(sql, contains('active_attempt.game_version in (2, 3, 4, 5, 6, 7)'));
    expect(sql, contains('submitted_score not between 0 and 15000'));
    expect(sql, contains('stars_collected + collisions <> 10'));
    expect(sql, contains('submitted_score < 3500'));
    expect(sql, contains('duration_ms not between 25000'));
    expect(sql, contains('active_attempt.game_duration_seconds'));
  });

  test('server copy renames the game to 홈런왕', () {
    final migration = File(
      'supabase/migrations/20260808001000_rename_ten_pitch_slugger.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("display_name = '홈런왕'"));
    expect(sql, contains("where game_id = 'ten_pitch_slugger'"));
    expect(sql, contains("where id = 'ten_pitch_slugger'"));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server rejects scores that claim more play time than elapsed', () {
    final migration = File(
      'supabase/migrations/20260801000450_validate_score_elapsed_time.sql',
    );
    final sql = migration.readAsStringSync();

    expect(sql, contains('assert_score_submission_elapsed'));
    expect(sql, contains("raise exception 'game finished too quickly'"));
    expect(sql, contains('duration_ms >= 3000'));
    expect(sql, contains('scheduled_duration * 1000 - 2000'));
  });
}

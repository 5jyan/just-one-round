import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('completed scores remain submitable after reconnecting', () {
    final migration = File(
      'supabase/migrations/20260801000250_reliable_score_submission.sql',
    );
    expect(migration.existsSync(), isTrue);

    final sql = migration.readAsStringSync();
    expect(sql, isNot(contains("interval '10 minutes'")));
    expect(sql, isNot(contains('and is_active')));
    expect(sql, contains("when 'sausage_dachshund'"));
    expect(sql, contains("active_attempt.status = 'submitted'"));
    expect(sql, contains("set status = 'submitted'"));
  });
}

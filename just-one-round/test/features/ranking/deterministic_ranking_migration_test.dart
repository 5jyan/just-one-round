import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily and history rankings have a deterministic final tie breaker', () {
    final migration = File(
      'supabase/migrations/20260801000300_deterministic_ranking_ties.sql',
    );
    expect(migration.existsSync(), isTrue);

    final sql = migration.readAsStringSync();
    expect(sql, contains('order by raw_score desc, submitted_at asc, user_id'));
    expect(
      sql,
      contains('order by r.raw_score desc, r.submitted_at asc, r.user_id'),
    );
  });
}

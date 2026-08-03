import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('점수 제출이 게임 종료 경로와 모순되는 결과를 거부한다', () {
    final sql = File(
      'supabase/migrations/20260802000400_tighten_score_submission_invariants.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains('collisions = 0 and duration_ms <> scheduled_duration * 1000'),
    );
    expect(sql, contains('minimum_mama_duck_score(stars_collected)'));
    expect(sql, contains('duration_ms >= 3000'));
    expect(sql, contains('Full anti-cheat replay would require'));
  });
}

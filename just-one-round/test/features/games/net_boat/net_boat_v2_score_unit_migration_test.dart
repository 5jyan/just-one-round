import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('net boat v2 accepts the runtime ten-point score unit', () {
    final sql = File(
      'supabase/migrations/20260819000400_fix_net_boat_v2_score_unit.sql',
    ).readAsStringSync();

    expect(sql, contains("active_attempt.game_id <> 'net_boat'"));
    expect(sql, contains('active_attempt.game_version <> 2'));
    expect(sql, contains('submitted_score % 10 <> 0'));
    expect(sql, isNot(contains('submitted_score % 100 <> 0')));
  });
}

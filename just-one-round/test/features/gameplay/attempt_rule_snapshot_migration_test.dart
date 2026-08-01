import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attempt snapshots rules so a later rollout cannot reject its score', () {
    final sql = File(
      'supabase/migrations/20260801000500_snapshot_attempt_game_rules.sql',
    ).readAsStringSync();

    expect(sql, contains('game_duration_seconds integer'));
    expect(sql, contains('snapshot_attempt_game_rules_before_insert'));
    expect(sql, contains('active_attempt.game_duration_seconds'));
    expect(sql, isNot(contains('where id = active_attempt.game_id')));
    expect(sql, contains('active_attempt.game_version = 1'));
    expect(sql, contains('active_attempt.game_version = 2'));
    expect(sql, contains('active_attempt.game_version = 3'));
  });
}

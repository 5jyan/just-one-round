import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('게임 버전 메타데이터를 불변 스냅샷으로 보존한다', () {
    final sql = File(
      'supabase/migrations/20260802000300_immutable_game_rule_versions.sql',
    ).readAsStringSync();

    expect(sql, contains('create table public.game_rule_versions'));
    expect(sql, contains('primary key (game_id, version)'));
    expect(sql, contains('daily_games_game_version_fk'));
    expect(sql, contains('attempts_game_version_fk'));
    expect(sql, contains('scores_game_version_fk'));
    expect(sql, contains('game_rule_versions_after_games_write'));
    expect(sql, contains('game version metadata is immutable'));
    expect(sql, contains('versioned.duration_seconds'));
  });
}

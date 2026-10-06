import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('생물 사냥 v2 카탈로그와 점수 검증을 추가하고 v1 제출을 보존한다', () {
    final sql = File(
      'supabase/migrations/20260817000100_net_boat_creature_hunt_v2.sql',
    ).readAsStringSync();

    expect(sql, contains("where id = 'net_boat'"));
    expect(sql, contains('version = 2'));
    expect(sql, contains('active_attempt.game_version <> 2'));
    expect(sql, contains('game_duration_seconds <> 180'));
    expect(sql, contains('submitted_score not between 0 and 1000000'));
    expect(sql, contains('submitted_score % 100 <> 0'));
    expect(sql, contains('submit_daily_score_before_net_boat_v2'));
  });
}

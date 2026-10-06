import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('만선호 카탈로그와 180초 점수 계약을 함께 추가한다', () {
    final sql = File(
      'supabase/migrations/20260816000300_add_net_boat.sql',
    ).readAsStringSync();

    expect(sql, contains("'net_boat'"));
    expect(sql, contains("'만선호'"));
    expect(sql, contains('game_version <> 1'));
    expect(sql, contains('game_duration_seconds <> 180'));
    expect(sql, contains('stars_collected <> 0'));
    expect(sql, contains('duration_ms not between 3000 and 180000'));
    expect(sql, contains('collisions = 0 and duration_ms <> 180000'));
    expect(sql, contains('submitted_score not between 0 and 1000000'));
    expect(sql, contains('submitted_score % 100 <> 0'));
    expect(sql, contains('submit_daily_score_before_net_boat'));
  });
}

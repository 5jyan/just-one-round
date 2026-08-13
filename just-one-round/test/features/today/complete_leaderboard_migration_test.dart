import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/'
    '20260813000800_show_complete_daily_leaderboard.sql',
  ).readAsStringSync();

  test('일일 랭킹은 1위부터 마지막 순위까지 모두 반환한다', () {
    expect(sql, contains("'leaders', coalesce"));
    expect(sql, contains('from ranked leaderboard'));
    expect(sql, isNot(contains('leaderboard.rank <=')));
    expect(sql, isNot(contains('leaders.rank <= 50')));
  });
}

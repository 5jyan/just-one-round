import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('랭킹 응답에 프로필 레벨을 포함한다', () {
    final sql = File(
      'supabase/migrations/20260821000200_show_levels_in_leaderboard.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains('public.experience_level(profile.experience_points) as level'),
    );
    expect(sql, contains("'level', neighbors.level"));
    expect(sql, contains("'level', leaderboard.level"));
  });
}

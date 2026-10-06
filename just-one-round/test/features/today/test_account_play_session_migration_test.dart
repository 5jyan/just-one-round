import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('테스트 계정 도전권도 시작 확인용 플레이 세션을 만든다', () {
    final sql = File(
      'supabase/migrations/20260815000900_fix_test_challenge_play_sessions.sql',
    ).readAsStringSync();

    expect(sql, contains('claim_daily_attempt_before_test_play_sessions'));
    expect(sql, contains("session.play_mode = 'challenge'"));
    expect(sql, contains('session.started_at is null'));
    expect(sql, contains('insert into public.daily_play_sessions'));
    expect(sql, contains('on conflict (attempt_id) do nothing'));
    expect(sql, contains('profile.is_test_account'));
  });
}

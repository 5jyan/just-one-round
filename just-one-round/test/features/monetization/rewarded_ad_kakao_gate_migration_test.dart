import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('최종 추가 플레이 RPC는 Kakao 없이 동작하고 일일 첫 판만 Kakao를 검사한다', () {
    final sql = File(
      'supabase/migrations/20260802001300_restore_anonymous_rewarded_implementation.sql',
    ).readAsStringSync();

    expect(sql, contains('public.prepare_rewarded_ad_without_kakao'));
    expect(sql, contains('public.claim_rewarded_attempt_without_kakao'));
    expect(sql, isNot(contains('auth.identities')));
    expect(sql, isNot(contains('kakao account required for rewarded attempt')));

    final dailyGateSql = File(
      'supabase/migrations/20260802001200_require_kakao_after_previous_day_play.sql',
    ).readAsStringSync();
    expect(dailyGateSql, contains('kakao account required for daily play'));
    expect(dailyGateSql, contains('prepare_rewarded_ad_without_kakao'));
  });
}

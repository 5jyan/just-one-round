import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('레거시 추가 플레이 RPC는 Kakao 없이 동작한다', () {
    final sql = File(
      'supabase/migrations/20260802001300_restore_anonymous_rewarded_implementation.sql',
    ).readAsStringSync();

    expect(sql, contains('public.prepare_rewarded_ad_without_kakao'));
    expect(sql, contains('public.claim_rewarded_attempt_without_kakao'));
    expect(sql, isNot(contains('auth.identities')));
    expect(sql, isNot(contains('kakao account required for rewarded attempt')));

    final optionalKakaoSql = File(
      'supabase/migrations/20260814000400_remove_kakao_login_requirement.sql',
    ).readAsStringSync();
    expect(optionalKakaoSql, contains('select false'));
    expect(optionalKakaoSql, isNot(contains('auth.identities')));
  });

  test('레거시 즉시 시작 추가 판은 광고 준비 시각부터 시간을 계산한다', () {
    final sql = File(
      'supabase/migrations/20260803000400_start_rewarded_attempt_clock_at_ad_prepare.sql',
    ).readAsStringSync();

    expect(sql, contains('issued_at'));
    expect(sql, contains('target_grant.prepared_at'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20260811000100_choose_practice_or_challenge.sql',
  ).readAsStringSync();

  test('하루 플레이 순서와 연습·도전 모드를 서버에 기록한다', () {
    expect(sql, contains('create table public.daily_play_sessions'));
    expect(sql, contains("play_mode in ('challenge', 'practice')"));
    expect(sql, contains('unique (user_id, play_date, ordinal)'));
  });

  test('세 번째 도전 강제와 도전 후 연습 전용 규칙을 계산한다', () {
    expect(sql, contains('summary.play_count < 3'));
    expect(sql, contains('summary.play_count < 2'));
    expect(sql, contains('not summary.challenge_played'));
  });

  test('첫 연습은 무료 RPC이고 이후 연습과 도전은 검증 광고를 사용한다', () {
    expect(sql, contains('public.claim_daily_practice'));
    expect(sql, contains('public.prepare_rewarded_ad_without_kakao'));
    expect(sql, contains('public.prepare_practice_ad'));
    expect(sql, contains("target_grant.status <> 'verified'"));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20260811000100_choose_practice_or_challenge.sql',
  ).readAsStringSync();
  final singleAdSql = File(
    'supabase/migrations/20260812000100_limit_daily_rewarded_ad_to_one.sql',
  ).readAsStringSync();
  final hardenedStartSql = File(
    'supabase/migrations/'
    '20260813000700_harden_play_start_state_machine.sql',
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

  test('연습·도전 순서에 따라 하루 광고를 한 번만 사용한다', () {
    expect(sql, contains('public.claim_daily_practice'));
    expect(sql, contains('public.prepare_rewarded_ad_without_kakao'));
    expect(sql, contains('public.prepare_practice_ad'));
    expect(sql, contains("target_grant.status <> 'verified'"));
    expect(singleAdSql, contains("'challenge_requires_ad'"));
    expect(singleAdSql, contains("'practice_requires_ad'"));
    expect(singleAdSql, contains('public.enforce_one_daily_rewarded_ad'));
    expect(singleAdSql, contains('daily rewarded ad already used'));
  });

  test('이미 소비한 연습 광고는 오래된 클라이언트 상태에서 재사용한다', () {
    final sql = File(
      'supabase/migrations/'
      '20260813000600_recover_stale_practice_ad_state.sql',
    ).readAsStringSync();

    expect(sql, contains("grant_row.status = 'consumed'"));
    expect(sql, contains('session.reward_grant_id = grant_row.id'));
    expect(sql, contains("session.play_mode = 'practice'"));
    expect(sql, contains('if active_grant is not null then'));
  });

  test('무료 연습 시작은 요청 ID로 멱등이고 검증된 광고를 복구한다', () {
    expect(hardenedStartSql, contains('client_request_id uuid'));
    expect(hardenedStartSql, contains('claim_daily_practice_v2'));
    expect(
      hardenedStartSql,
      contains('session.client_request_id = play_request_id'),
    );
    expect(hardenedStartSql, contains("grant_row.status = 'verified'"));
    expect(hardenedStartSql, contains("set status = 'consumed'"));
  });

  test('기기 일일 제한이 있으면 시작 버튼을 열지 않는다', () {
    expect(hardenedStartSql, contains("'device_daily_limit_reached', true"));
    expect(hardenedStartSql, contains("'challenge_available', false"));
    expect(hardenedStartSql, contains("'practice_available', false"));
  });
}

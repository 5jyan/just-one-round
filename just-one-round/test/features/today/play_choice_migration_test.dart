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
  final confirmedStartSql = File(
    'supabase/migrations/'
    '20260814000300_confirm_actual_play_start.sql',
  ).readAsStringSync();
  final practiceTicketSql = File(
    'supabase/migrations/'
    '20260815000800_practice_ticket_rewards.sql',
  ).readAsStringSync();
  final repeatRefillSql = File(
    'supabase/migrations/'
    '20260816000150_repeat_practice_ticket_refills.sql',
  ).readAsStringSync();
  final extraChoiceSql = File(
    'supabase/migrations/20260822000400_choose_extra_challenge_entitlement.sql',
  ).readAsStringSync();
  final testStartFixSql = File(
    'supabase/migrations/20260822000500_fix_test_extra_challenge_start.sql',
  ).readAsStringSync();
  final scorePreservationSql = File(
    'supabase/migrations/'
    '20260825000200_preserve_best_score_on_extra_challenge.sql',
  ).readAsStringSync();
  final rankingBestScoreSql = File(
    'supabase/migrations/20260821000200_show_levels_in_leaderboard.sql',
  ).readAsStringSync();
  final sequentialExtraChallengeSql = File(
    'supabase/migrations/20260824000300_sequential_extra_challenge_ticket.sql',
  ).readAsStringSync();
  final unlimitedChallengeTicketSql = File(
    'supabase/migrations/'
    '20260825000300_allow_unlimited_challenge_ticket_attempts.sql',
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

  test('실제 런타임 시작 전 이탈과 재설치 중복을 복구한다', () {
    expect(confirmedStartSql, contains('started_at timestamptz'));
    expect(confirmedStartSql, contains('confirm_daily_play_started'));
    expect(confirmedStartSql, contains('session.started_at is null'));
    expect(confirmedStartSql, contains('challenge_pending'));
    expect(confirmedStartSql, contains('practice_pending'));
    expect(
      confirmedStartSql,
      contains('coalesce(public.request_app_build(), 0) < 12'),
    );
  });

  test('공식 도전은 무료이고 연습권은 기본 한 장과 광고 두 장으로 계산한다', () {
    expect(practiceTicketSql, contains("'practice_ticket_capacity'"));
    expect(practiceTicketSql, contains("'practice_tickets_remaining'"));
    expect(practiceTicketSql, contains('1 + case'));
    expect(practiceTicketSql, contains('then 2 else 0'));
    expect(practiceTicketSql, contains("'challenge_requires_ad', false"));
    expect(practiceTicketSql, contains('claim_practice_ticket_reward'));
    expect(practiceTicketSql, contains("'tickets_granted', 2"));
    expect(practiceTicketSql, contains('game_id = scheduled_game.game_id'));
    expect(
      practiceTicketSql,
      contains('game_duration_seconds = selected_version.duration_seconds'),
    );
  });

  test('연습권이 0장이 될 때마다 광고로 2장을 반복 충전한다', () {
    expect(
      repeatRefillSql,
      contains('drop trigger if exists rewarded_ad_grants_one_per_day'),
    );
    expect(repeatRefillSql, contains('practice_reward_count * 2'));
    expect(
      repeatRefillSql,
      contains("availability.practice_tickets_remaining = 0"),
    );
    expect(
      repeatRefillSql,
      contains("raise exception 'practice tickets remain'"),
    );
    expect(
      repeatRefillSql,
      contains("grant_row.status in ('prepared', 'verified')"),
    );
  });

  test('기존 추가 도전 선택 RPC는 광고와 도전권 경로를 분리한다', () {
    expect(extraChoiceSql, contains('extra_challenge_available'));
    expect(extraChoiceSql, contains('challenge_ticket_available'));
    expect(extraChoiceSql, contains('claim_challenge_ticket_attempt'));
    expect(
      extraChoiceSql,
      contains("raise exception 'extra challenge choice required'"),
    );
    expect(extraChoiceSql, contains("entitlement.challenge_session_count = 1"));
    expect(extraChoiceSql, contains("entitlement_source\n  ) values"));
  });

  test('추가 도전은 광고 후 보유 도전권만큼 반복해서 연다', () {
    expect(sequentialExtraChallengeSql, contains("'ad_challenge_available'"));
    expect(
      sequentialExtraChallengeSql,
      contains('challenge_session_count = 2'),
    );
    expect(
      sequentialExtraChallengeSql,
      contains('rewarded_challenge_session_count = 1'),
    );
    expect(sequentialExtraChallengeSql, contains('ranked_reward_consumed'));
    expect(sequentialExtraChallengeSql, contains('challenge_ticket_available'));
    expect(sequentialExtraChallengeSql, contains('extra_challenge_available'));
    expect(
      unlimitedChallengeTicketSql,
      contains('entitlement.challenge_session_count >= 2'),
    );
    expect(
      unlimitedChallengeTicketSql,
      contains('entitlement.rewarded_challenge_session_count >= 1'),
    );
    expect(
      unlimitedChallengeTicketSql,
      contains('entitlement.store_challenge_tickets > 0'),
    );
    expect(
      unlimitedChallengeTicketSql,
      isNot(contains('store_challenge_session_count = 0')),
    );
  });

  test('테스트 계정 도전도 시작 확인용 세션을 만든다', () {
    expect(extraChoiceSql, contains('claim_test_daily_attempt_with_session'));
    expect(testStartFixSql, contains('claim_test_daily_attempt_with_session'));
    expect(testStartFixSql, contains('daily_play_sessions'));
  });

  test('재도전은 기존 점수를 보존하고 사용자 최고 기록으로 랭킹한다', () {
    expect(
      scorePreservationSql,
      contains(
        'drop trigger if exists daily_play_sessions_replace_score_before_extra_insert',
      ),
    );
    expect(
      scorePreservationSql,
      contains(
        'drop function if exists public.discard_previous_daily_challenge_score()',
      ),
    );
    expect(scorePreservationSql, isNot(contains('delete from public.scores')));
    expect(rankingBestScoreSql, contains('select distinct on (score.user_id)'));
    expect(
      rankingBestScoreSql,
      contains('order by score.user_id, score.raw_score desc'),
    );
  });
}

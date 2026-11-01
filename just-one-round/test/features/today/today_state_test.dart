import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/lily_frog/domain/lily_frog_rules.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  test('닉네임과 주변 랭킹 응답을 파싱한다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-07-22',
      'game': null,
      'nickname': '별하나',
      'nickname_color': 'violet',
      'store_nickname_color_tickets': 2,
      'store_nickname_change_tickets': 1,
      'attempts': <dynamic>[],
      'ad_attempt_available': false,
      'requires_kakao_for_daily_play': true,
      'economy': {
        'coins': 125,
        'experience_points': 225,
        'level': 2,
        'experience_to_next_level': 175,
      },
      'result': {
        'score': 800,
        'rank': 2,
        'nickname': '별하나',
        'participants': 3,
        'top_percent': 67,
        'nearby': [
          {'rank': 1, 'nickname': '별셋', 'score': 900, 'is_me': false},
          {
            'rank': 2,
            'nickname': '별하나',
            'score': 800,
            'is_me': true,
            'level': 7,
            'nickname_color': 'violet',
          },
          {'rank': 3, 'nickname': '별둘', 'score': 700, 'is_me': false},
        ],
      },
    });

    expect(state.nickname, '별하나');
    expect(state.economy.coins, 125);
    expect(state.economy.experiencePoints, 225);
    expect(state.economy.level, 2);
    expect(state.result?.nearby, hasLength(3));
    expect(state.result?.nearby[1].isMe, isTrue);
    expect(state.result?.nearby[1].level, 7);
    expect(state.result?.nearby[1].nicknameColor, 'violet');
    expect(state.nicknameColor, 'violet');
    expect(state.storeNicknameColorTickets, 2);
    expect(state.storeNicknameChangeTickets, 1);
    expect(state.result?.nearby.first.level, 1);
    expect(state.requiresKakaoForDailyPlay, isTrue);
  });

  test('내일 게임 편성을 파싱하고 오늘 연습권을 공유하는 미리보기 상태를 만든다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-08-19',
      'game': {
        'id': 'number_rush',
        'version': 1,
        'display_name': '탭50',
        'description': '순서대로 탭하세요.',
        'duration_seconds': 60,
      },
      'tomorrow': {
        'play_date': '2026-08-20',
        'game': {
          'id': 'net_boat',
          'version': 2,
          'display_name': '만선호',
          'description': '물고기를 잡으세요.',
          'duration_seconds': 60,
        },
      },
      'attempts': <dynamic>[],
      'ad_attempt_available': false,
      'test_mode': false,
      'result': null,
      'practice_available': true,
      'challenge_available': true,
      'practice_tickets_remaining': 2,
    });

    final tomorrow = state.tomorrowPreview;
    expect(tomorrow?.playDate, DateTime(2026, 8, 20));
    expect(tomorrow?.game?.id, 'net_boat');
    expect(tomorrow?.practiceTicketsRemaining, 2);
    expect(tomorrow?.canChoosePractice, isTrue);
    expect(tomorrow?.canChooseChallenge, isFalse);
    expect(tomorrow?.isTomorrowPreview, isTrue);
  });

  test('호환되지 않는 내일 미리보기는 오늘 로비를 강제 업데이트로 막지 않는다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-09-10',
      'game': {
        'id': 'gravity_switch',
        'version': 1,
        'display_name': '중력 뒤집기',
        'description': '중력을 뒤집으세요.',
        'duration_seconds': 240,
      },
      'tomorrow': {
        'play_date': '2026-09-11',
        'game': {
          'id': 'lily_frog',
          'version': 2,
          'display_name': '빙글개굴',
          'description': '연잎을 밟으세요.',
          'duration_seconds': 300,
        },
      },
      'attempts': <dynamic>[],
      'ad_attempt_available': false,
      'test_mode': false,
      'result': null,
    });

    expect(
      unsupportedGameCompatibilityFor(
        state,
        const ClientCompatibility.supported(),
      ),
      isNull,
    );
  });

  test('플레이 시도에서 게임 ID를 파싱한다', () {
    final attempt = PlayAttempt.fromJson({
      'id': 'attempt-1',
      'ordinal': 1,
      'status': 'issued',
      'grant_type': 'daily',
      'game_id': 'gravity_switch',
      'game_version': 2,
      'game_duration_seconds': 240,
      'play_date': '2026-08-01',
      'issued_at': '2026-08-01T12:34:56.000Z',
      'practice_ordinal': 2,
    });

    expect(attempt.gameId, 'gravity_switch');
    expect(attempt.gameVersion, 2);
    expect(attempt.gameDurationSeconds, 240);
    expect(attempt.playDate, DateTime(2026, 8, 1));
    expect(attempt.issuedAt, DateTime.utc(2026, 8, 1, 12, 34, 56));
    expect(attempt.practiceOrdinal, 2);
  });

  test('클라이언트 최소 빌드 응답을 파싱한다', () {
    final compatibility = ClientCompatibility.fromJson({
      'current_build': 1,
      'minimum_supported_build': 2,
      'update_required': true,
      'store_url': 'https://example.com/store',
      'reason': 'production_release_required',
    });

    expect(compatibility.updateRequired, isTrue);
    expect(compatibility.currentBuild, 1);
    expect(compatibility.minimumSupportedBuild, 2);
    expect(compatibility.storeUrl, 'https://example.com/store');
    expect(compatibility.reason, 'production_release_required');

    final genericUpdate = compatibility.requiringUpdate(
      reason: 'unsupported_game',
    );
    expect(genericUpdate.updateRequired, isTrue);
    expect(genericUpdate.storeUrl, 'https://example.com/store');
    expect(genericUpdate.reason, 'unsupported_game');
  });

  test('시뮬레이터 미리보기는 실제 똥피하기와 빙글개굴 버전을 사용한다', () async {
    final dung = PreviewDailyGameRepository(initialGameId: 'dung_dodge_v2');
    final lily = PreviewDailyGameRepository(initialGameId: 'lily_frog');

    expect((await dung.fetchToday()).game?.version, 1);
    expect((await lily.fetchToday()).game?.version, LilyFrogRules.rulesVersion);
  });

  test('연습과 도전 선택 상태를 파싱한다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-08-11',
      'game': null,
      'attempts': <dynamic>[],
      'ad_attempt_available': false,
      'test_mode': false,
      'result': null,
      'play_count': 2,
      'practice_play_count': 1,
      'challenge_available': true,
      'practice_available': false,
      'next_play_requires_ad': true,
      'challenge_requires_ad': true,
      'practice_requires_ad': false,
      'practice_ticket_capacity': 3,
      'practice_tickets_remaining': 2,
      'practice_reward_available': false,
      'practice_reward_earned': true,
      'store_practice_tickets': 4,
      'store_challenge_tickets': 2,
      'ranked_ad_attempt_used': true,
      'coin_ad_available': true,
    });

    expect(state.completedPlayCount, 2);
    expect(state.practicePlayCount, 1);
    expect(state.canChooseChallenge, isTrue);
    expect(state.canChoosePractice, isFalse);
    expect(state.requiresAdForNextPlay, isTrue);
    expect(state.requiresAdForChallenge, isTrue);
    expect(state.requiresAdForPractice, isFalse);
    expect(state.practiceTicketCapacity, 3);
    expect(state.practiceTicketsRemaining, 2);
    expect(state.practiceRewardEarned, isTrue);
    expect(state.storePracticeTickets, 4);
    expect(state.storeChallengeTickets, 2);
    expect(state.rankedAdAttemptUsed, isTrue);
    expect(state.coinAdAvailable, isTrue);
  });

  test('광고 추가 도전과 도전권 추가 도전을 분리해 파싱한다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-08-24',
      'game': null,
      'attempts': <dynamic>[],
      'ad_attempt_available': false,
      'test_mode': false,
      'result': null,
      'play_count': 2,
      'challenge_available': true,
      'ad_challenge_available': false,
      'extra_challenge_available': true,
      'challenge_ticket_available': true,
      'ranked_ad_attempt_used': true,
      'store_challenge_tickets': 1,
    });

    expect(state.canChooseAdChallenge, isFalse);
    expect(state.canChooseChallengeTicket, isTrue);
    expect(state.canChooseExtraChallenge, isTrue);
    expect(state.canChooseChallenge, isTrue);
  });

  test('통합 추가 도전 플래그가 남아 있어도 사용한 광고를 다시 선택하지 않는다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-09-14',
      'game': null,
      'attempts': <dynamic>[],
      'ad_attempt_available': false,
      'test_mode': false,
      'result': null,
      'challenge_available': true,
      // This is the production response shape from before the dedicated
      // ad_challenge_available field was restored.
      'extra_challenge_available': true,
      'ranked_ad_attempt_used': true,
      'challenge_requires_ad': false,
      'challenge_ticket_available': true,
      'store_challenge_tickets': 1,
    });

    expect(state.adChallengeAvailable, isFalse);
    expect(state.canChooseAdChallenge, isFalse);
    expect(state.canChooseChallengeTicket, isTrue);
    expect(state.canChooseExtraChallenge, isTrue);
  });

  test('명시된 challenge_requires_ad를 레거시 통합 플래그보다 우선한다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-09-14',
      'game': null,
      'attempts': <dynamic>[],
      'ad_attempt_available': false,
      'test_mode': false,
      'result': null,
      'extra_challenge_available': true,
      'challenge_requires_ad': false,
      'ranked_ad_attempt_used': false,
    });

    expect(state.adChallengeAvailable, isFalse);
    expect(state.canChooseAdChallenge, isFalse);
  });

  test('광고 전용 필드가 없는 레거시 응답은 미사용 광고를 유지한다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-09-14',
      'game': null,
      'attempts': <dynamic>[],
      'ad_attempt_available': false,
      'test_mode': false,
      'result': null,
      'extra_challenge_available': true,
      'ranked_ad_attempt_used': false,
    });

    expect(state.adChallengeAvailable, isTrue);
    expect(state.canChooseAdChallenge, isTrue);
  });

  test('테스트 모드에서는 서버 제한과 관계없이 도전을 시작할 수 있다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-08-11',
      'attempts': <dynamic>[],
      'ad_attempt_available': false,
      'test_mode': true,
      'challenge_available': false,
      'practice_available': false,
    });

    expect(state.canChooseChallenge, isTrue);
  });

  test('이전 광고 보상을 받았어도 0장이면 다시 충전할 수 있다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-08-16',
      'game': null,
      'attempts': <dynamic>[],
      'test_mode': false,
      'practice_available': false,
      'practice_tickets_remaining': 0,
      'practice_reward_available': true,
      'practice_reward_earned': true,
    });

    expect(state.canClaimPracticeReward, isTrue);
  });

  test('무료 연습 시도는 랭킹에 반영하지 않는다', () {
    const attempt = PlayAttempt(
      id: 'practice-session',
      ordinal: 1,
      status: 'practice',
      grantType: 'practice_daily',
    );

    expect(attempt.isPractice, isTrue);
  });

  test('플레이 요청 ID는 UUID v4 형식으로 생성한다', () {
    final requestId = createPlayRequestId(random: Random(42));

    expect(
      requestId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  test('닉네임과 주변 랭킹 응답을 파싱한다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-07-22',
      'game': null,
      'nickname': '별하나',
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
          {'rank': 2, 'nickname': '별하나', 'score': 800, 'is_me': true},
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
    expect(state.requiresKakaoForDailyPlay, isTrue);
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
    });

    expect(attempt.gameId, 'gravity_switch');
    expect(attempt.gameVersion, 2);
    expect(attempt.gameDurationSeconds, 240);
    expect(attempt.playDate, DateTime(2026, 8, 1));
    expect(attempt.issuedAt, DateTime.utc(2026, 8, 1, 12, 34, 56));
  });

  test('클라이언트 최소 빌드 응답을 파싱한다', () {
    final compatibility = ClientCompatibility.fromJson({
      'current_build': 1,
      'minimum_supported_build': 2,
      'update_required': true,
      'store_url': 'https://example.com/store',
    });

    expect(compatibility.updateRequired, isTrue);
    expect(compatibility.currentBuild, 1);
    expect(compatibility.minimumSupportedBuild, 2);
    expect(compatibility.storeUrl, 'https://example.com/store');
  });
}

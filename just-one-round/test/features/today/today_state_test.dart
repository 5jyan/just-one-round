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
    expect(state.result?.nearby, hasLength(3));
    expect(state.result?.nearby[1].isMe, isTrue);
  });

  test('플레이 시도에서 게임 ID를 파싱한다', () {
    final attempt = PlayAttempt.fromJson({
      'id': 'attempt-1',
      'ordinal': 1,
      'status': 'issued',
      'grant_type': 'daily',
      'game_id': 'gravity_switch',
    });

    expect(attempt.gameId, 'gravity_switch');
  });
}

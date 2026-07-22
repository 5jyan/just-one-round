import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  test('프로필과 주변 랭킹 응답을 파싱한다', () {
    final state = TodayState.fromJson({
      'play_date': '2026-07-22',
      'game': null,
      'profile': {'nickname': '별하나', 'birth_decade': 2000, 'gender': 'female'},
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

    expect(state.profile.nickname, '별하나');
    expect(state.profile.birthDecade, 2000);
    expect(state.profile.gender, ProfileGender.female);
    expect(state.result?.nearby, hasLength(3));
    expect(state.result?.nearby[1].isMe, isTrue);
  });
}

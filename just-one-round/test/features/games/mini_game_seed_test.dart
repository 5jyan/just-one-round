import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/domain/mini_game_seed.dart';

void main() {
  final playDate = DateTime(2026, 8, 1);

  test('같은 날짜·게임·버전은 같은 시드를 만든다', () {
    expect(
      MiniGameSeed.forAttempt(
        gameId: 'apple_game_v2',
        gameVersion: 1,
        playDate: playDate,
      ),
      MiniGameSeed.forAttempt(
        gameId: 'apple_game_v2',
        gameVersion: 1,
        playDate: playDate,
      ),
    );
  });

  test('날짜·버전·게임이 바뀌면 시드가 분리된다', () {
    final base = MiniGameSeed.forAttempt(
      gameId: 'apple_game_v2',
      gameVersion: 1,
      playDate: playDate,
    );
    expect(
      MiniGameSeed.forAttempt(
        gameId: 'apple_game_v2',
        gameVersion: 1,
        playDate: playDate.add(const Duration(days: 1)),
      ),
      isNot(base),
    );
    expect(
      MiniGameSeed.forAttempt(
        gameId: 'apple_game_v2',
        gameVersion: 2,
        playDate: playDate,
      ),
      isNot(base),
    );
    expect(
      MiniGameSeed.forAttempt(
        gameId: 'number_rush',
        gameVersion: 1,
        playDate: playDate,
      ),
      isNot(base),
    );
  });

  test('결정론적 helper는 공식 도전과 연습 회차별 시드를 분리한다', () {
    final challenge = MiniGameSeed.forAttempt(
      gameId: 'beat_the_dealer',
      gameVersion: 3,
      playDate: playDate,
    );
    final firstPractice = MiniGameSeed.forAttempt(
      gameId: 'beat_the_dealer',
      gameVersion: 3,
      playDate: playDate,
      practiceOrdinal: 1,
    );
    final sameFirstPractice = MiniGameSeed.forAttempt(
      gameId: 'beat_the_dealer',
      gameVersion: 3,
      playDate: playDate,
      practiceOrdinal: 1,
    );
    final secondPractice = MiniGameSeed.forAttempt(
      gameId: 'beat_the_dealer',
      gameVersion: 3,
      playDate: playDate,
      practiceOrdinal: 2,
    );

    expect(firstPractice, isNot(challenge));
    expect(sameFirstPractice, firstPractice);
    expect(secondPractice, isNot(firstPractice));
  });

  test('랜덤 시드는 기본적으로 난수를 사용하고 테스트에서는 source를 주입할 수 있다', () {
    final first = MiniGameSeed.randomSeed(random: Random(41));
    final same = MiniGameSeed.randomSeed(random: Random(41));
    final different = MiniGameSeed.randomSeed(random: Random(42));

    expect(first, same);
    expect(different, isNot(first));
    expect(first, inInclusiveRange(0, 0x7ffffffe));
  });
}

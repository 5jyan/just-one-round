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

  test('일반 게임은 두 번째 시도에서도 같은 챌린지를 사용하고 블랙잭만 분리한다', () {
    final regularFirst = MiniGameSeed.forAttempt(
      gameId: 'number_rush',
      gameVersion: 1,
      playDate: playDate,
    );
    final regularSecond = MiniGameSeed.forAttempt(
      gameId: 'number_rush',
      gameVersion: 1,
      playDate: playDate,
    );
    final blackjackFirst = MiniGameSeed.forAttempt(
      gameId: 'beat_the_dealer',
      gameVersion: 3,
      playDate: playDate,
      attemptOrdinal: 1,
    );
    final blackjackSecond = MiniGameSeed.forAttempt(
      gameId: 'beat_the_dealer',
      gameVersion: 3,
      playDate: playDate,
      attemptOrdinal: 2,
    );

    expect(regularSecond, regularFirst);
    expect(blackjackSecond, isNot(blackjackFirst));
  });
}

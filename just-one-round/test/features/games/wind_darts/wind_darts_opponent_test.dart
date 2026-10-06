import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_opponent.dart';

void main() {
  const v1Json = <String, dynamic>{
    'nickname': 'v1 opponent',
    'shot_scores': [25, 60, 39, 57, 20],
    'is_bot': false,
  };
  const v2Json = <String, dynamic>{
    'nickname': 'v2 opponent',
    'shot_scores': [50, 60, 39, 57, 20, 60],
    'is_bot': true,
  };
  const v3Json = <String, dynamic>{
    'nickname': 'v3 opponent',
    'shot_scores': [50, 60, 39, 57, 20, 60],
    'is_bot': false,
  };

  test('parses five-shot historical opponents for v1', () {
    final opponent = WindDartsOpponent.fromJson(v1Json, attemptVersion: 1);

    expect(opponent.shotScores, [25, 60, 39, 57, 20]);
    expect(opponent.score, 201);
  });

  test('parses six-shot opponents for v2', () {
    final opponent = WindDartsOpponent.fromJson(v2Json, attemptVersion: 2);

    expect(opponent.shotScores, [50, 60, 39, 57, 20, 60]);
    expect(opponent.score, 286);
  });

  test('parses six-shot opponents for the unlimited v3 runtime', () {
    final opponent = WindDartsOpponent.fromJson(v3Json, attemptVersion: 3);

    expect(opponent.shotScores, [50, 60, 39, 57, 20, 60]);
    expect(opponent.score, 286);
  });

  test('rejects a payload whose length does not match the attempt version', () {
    expect(
      () => WindDartsOpponent.fromJson(v2Json, attemptVersion: 1),
      throwsFormatException,
    );
    expect(
      () => WindDartsOpponent.fromJson(v1Json, attemptVersion: 2),
      throwsFormatException,
    );
    expect(
      () => WindDartsOpponent.fromJson(v1Json, attemptVersion: 3),
      throwsFormatException,
    );
  });
}

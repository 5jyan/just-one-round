import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/domain/ten_pitch_slugger_rules.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/ten_pitch_slugger_game.dart';

void main() {
  test('interruption never reports a score', () {
    var finishCount = 0;
    final game = TenPitchSluggerGame(
      challengeSeed: 1,
      onFinished: (_) => finishCount++,
    );

    game.interrupt();
    game.interrupt();

    expect(finishCount, 0);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    game.disposeController();
  });

  testWidgets('safe opening ignores taps and exposes no visible timer', (
    tester,
  ) async {
    final game = TenPitchSluggerGame(
      challengeSeed: 2,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);

    expect(game.gamePhase, TenPitchSluggerPhase.safeOpening);
    expect(TenPitchSluggerRules.safeOpeningSeconds, 2);
    expect(game.hud.value.remainingSeconds, isNull);
    game.tapSwing();
    expect(game.hasTappedThisPitch, isFalse);

    await tester.pump(
      Duration(
        milliseconds: (TenPitchSluggerRules.safeOpeningSeconds * 1000).ceil(),
      ),
    );
    expect(game.gamePhase, TenPitchSluggerPhase.windup);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ten pitches finish once with maximum distance and hit counts', (
    tester,
  ) async {
    GameResult? result;
    var finishCount = 0;
    final game = TenPitchSluggerGame(
      challengeSeed: 3,
      countdownDuration: Duration.zero,
      onFinished: (value) {
        result = value;
        finishCount++;
      },
    );
    addTearDown(game.disposeController);
    final hitDistances = <int>[];

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);

    for (var index = 0; index < TenPitchSluggerRules.pitchCount; index++) {
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
      expect(game.gamePhase, TenPitchSluggerPhase.pitchFlight);

      if (index < 2) {
        final timingOffset = index == 0
            ? -0.02
            : -game.currentPitch.hitWindowSeconds * 0.75;
        while (game.phaseElapsed <
            game.currentPitch.idealTapSeconds + timingOffset) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        game.tapSwing();
        game.tapSwing();
        await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
        expect(game.lastDistanceCm, greaterThan(0));
        hitDistances.add(game.lastDistanceCm);
        expect(game.lastHitType, isNotNull);
        expect(
          game.hud.value.message,
          contains(TenPitchSluggerRules.hitTypeLabel(game.lastHitType!)),
        );
      } else {
        await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
      }
      expect(game.gamePhase, TenPitchSluggerPhase.feedback);
      if (index < TenPitchSluggerRules.pitchCount - 1) {
        await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);
      } else {
        await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.finished);
      }
    }

    expect(finishCount, 1);
    expect(result, isNotNull);
    expect(result!.score, game.bestDistanceCm);
    expect(result!.score, hitDistances.reduce(max));
    expect(result!.score, isNot(hitDistances.reduce((a, b) => a + b)));
    expect(result!.score, greaterThan(0));
    expect(result!.starsCollected, 2);
    expect(result!.collisions, 8);
    expect(result!.starsCollected + result!.collisions, 10);
    expect(result!.endType, GameEndType.clear);
    await tester.pump(const Duration(seconds: 1));
    expect(finishCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the slugger appears only for pitch seven and announces once', (
    tester,
  ) async {
    final game = TenPitchSluggerGame(
      challengeSeed: 31,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    final messages = <String?>[];
    String? previousMessage;
    void recordMessage() {
      final message = game.hud.value.message;
      if (message != previousMessage) {
        messages.add(message);
        previousMessage = message;
      }
    }

    game.hud.addListener(recordMessage);
    addTearDown(() => game.hud.removeListener(recordMessage));
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);

    for (var pitch = 1; pitch <= 6; pitch++) {
      expect(game.usesSluggerBatter, isFalse);
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
      await _pumpUntilPhase(
        tester,
        game,
        pitch == 6
            ? TenPitchSluggerPhase.sluggerEntrance
            : TenPitchSluggerPhase.windup,
      );
    }

    expect(game.pitchNumber, 7);
    expect(game.usesSluggerBatter, isTrue);
    expect(game.currentPitch.movement, TenPitchMovement.slider);
    expect(game.gamePhase, TenPitchSluggerPhase.sluggerEntrance);
    expect(game.hud.value.message, '강타자 등장!');
    game.tapSwing();
    expect(game.swingCount, 0);
    await tester.pump(const Duration(milliseconds: 800));
    expect(game.gamePhase, TenPitchSluggerPhase.sluggerEntrance);
    expect(game.swingCount, 0);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);
    expect(game.hud.value.message, '7번 타자는 강타자 등장!');
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    expect(game.usesSluggerBatter, isTrue);
    expect(game.hud.value.message, '7번 타자는 강타자 등장!');
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
    expect(game.usesSluggerBatter, isTrue);

    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);
    expect(game.pitchNumber, 8);
    expect(game.usesSluggerBatter, isFalse);
    expect(game.hud.value.message, contains('8구'));
    expect(messages.where((message) => message == '7번 타자는 강타자 등장!').length, 1);
    expect(messages.where((message) => message == '강타자 등장!').length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('windup accepts repeated swings before the ball is released', (
    tester,
  ) async {
    final game = TenPitchSluggerGame(
      challengeSeed: 21,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);

    game.tapSwing();
    expect(game.swingCount, 1);
    expect(game.hasTappedThisPitch, isFalse);
    await tester.pump(const Duration(milliseconds: 299));
    game.tapSwing();
    expect(game.swingCount, 1);
    await tester.pump(const Duration(milliseconds: 2));
    game.tapSwing();
    expect(game.swingCount, 2);

    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    game.tapSwing();
    expect(game.swingCount, 3);
    expect(game.hasTappedThisPitch, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('watchdog interrupts without manufacturing a result', (
    tester,
  ) async {
    var finishCount = 0;
    final game = TenPitchSluggerGame(
      challengeSeed: 4,
      countdownDuration: Duration.zero,
      watchdogDuration: const Duration(seconds: 1),
      onFinished: (_) => finishCount++,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    for (var tick = 0; tick < 20; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(game.hud.value.phase, MiniGamePhase.finished);
    expect(finishCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'early misses allow another swing after the 0.3 second cooldown',
    (tester) async {
      final game = TenPitchSluggerGame(
        challengeSeed: 5,
        countdownDuration: Duration.zero,
        onFinished: (_) {},
      );
      addTearDown(game.disposeController);

      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      await _waitUntilLoaded(tester, game);
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);

      game.tapSwing();
      expect(game.swingCount, 1);
      await tester.pump(const Duration(milliseconds: 130));
      expect(game.gamePhase, TenPitchSluggerPhase.pitchFlight);
      game.tapSwing();
      expect(game.swingCount, 1);

      await tester.pump(const Duration(milliseconds: 180));
      game.tapSwing();
      expect(game.swingCount, 2);
      await tester.pump(const Duration(milliseconds: 130));
      expect(game.gamePhase, TenPitchSluggerPhase.pitchFlight);

      while (game.phaseElapsed < game.currentPitch.idealTapSeconds - 0.01) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      game.tapSwing();
      expect(game.swingCount, 3);
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);

      expect(game.lastDistanceCm, greaterThan(0));
      expect(game.lastJudgement, TenPitchJudgement.perfect);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('watching a pitch never triggers an automatic swing', (
    tester,
  ) async {
    final game = TenPitchSluggerGame(
      challengeSeed: 6,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);

    expect(game.lastDistanceCm, 0);
    expect(game.hasTappedThisPitch, isFalse);
    expect(game.swingCount, 0);
    expect(game.lastJudgement, TenPitchJudgement.watched);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _waitUntilLoaded(
  WidgetTester tester,
  TenPitchSluggerGame game,
) async {
  for (var attempt = 0; attempt < 30 && !game.assetsReady; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(game.assetsReady, isTrue);
}

Future<void> _pumpUntilPhase(
  WidgetTester tester,
  TenPitchSluggerGame game,
  TenPitchSluggerPhase phase,
) async {
  for (var tick = 0; tick < 400 && game.gamePhase != phase; tick++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(game.gamePhase, phase);
}

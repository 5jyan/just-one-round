import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/domain/ten_pitch_slugger_rules.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/ten_pitch_slugger_game.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await loader.load();
  });

  testWidgets('first pitch fits the real 360x640 runtime', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('ten-pitch-runtime-capture');
    final game = TenPitchSluggerGame(
      challengeSeed: 20260807,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    for (var attempt = 0; attempt < 30 && !game.assetsReady; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(game.assetsReady, isTrue);
    for (
      var tick = 0;
      tick < 400 && game.gamePhase != TenPitchSluggerPhase.pitchFlight;
      tick++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(game.gamePhase, TenPitchSluggerPhase.pitchFlight);
    for (var tick = 0; tick < 35; tick++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    game.pauseEngine();
    await tester.pump();

    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'qc/runtime-first-pitch-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'seventh-pitch slugger windup renders the announcement and batter',
    (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const captureKey = Key('ten-pitch-slugger-windup-capture');
      final game = TenPitchSluggerGame(
        challengeSeed: 20260807,
        countdownDuration: Duration.zero,
        onFinished: (_) {},
      );
      addTearDown(game.disposeController);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: captureKey,
            child: SizedBox.expand(child: GameWidget(game: game)),
          ),
        ),
      );
      await _waitUntilLoaded(tester, game);
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);
      for (var index = 0; index < 6; index++) {
        await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
        await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
        await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);
      }
      await tester.pump(const Duration(milliseconds: 100));
      game.pauseEngine();
      await tester.pump();

      expect(game.pitchNumber, 7);
      expect(game.usesSluggerBatter, isTrue);
      expect(game.gamePhase, TenPitchSluggerPhase.windup);
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
        await expectLater(
          find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'slugger_v1/qc/runtime-slugger-pitch7-windup-360x640.png',
        ),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('perfect swing visibly meets the ball at the authored frame', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('ten-pitch-contact-capture');
    final game = TenPitchSluggerGame(
      challengeSeed: 20260807,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    while (game.phaseElapsed < game.currentPitch.idealTapSeconds - 0.005) {
      await tester.pump(const Duration(milliseconds: 5));
    }
    game.tapSwing();
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
    game.pauseEngine();
    await tester.pump();

    expect(game.lastDistanceCm, greaterThan(0));
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'qc/runtime-perfect-contact-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('home-run contact remains visible deep into the field', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('ten-pitch-long-hit-capture');
    final game = TenPitchSluggerGame(
      challengeSeed: 20260807,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    while (game.phaseElapsed < game.currentPitch.idealTapSeconds - 0.005) {
      await tester.pump(const Duration(milliseconds: 5));
    }
    game.tapSwing();
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
    await tester.pump(const Duration(milliseconds: 2450));
    game.pauseEngine();
    await tester.pump();

    expect(game.lastDistanceCm, greaterThan(0));
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'qc/runtime-v4-long-hit-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('100m hit shows the dedicated home-run celebration', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('ten-pitch-home-run-celebration-capture');
    final game = TenPitchSluggerGame(
      challengeSeed: 20260807,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    while (game.phaseElapsed < game.currentPitch.idealTapSeconds - 0.005) {
      await tester.pump(const Duration(milliseconds: 5));
    }
    game.tapSwing();
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
    await tester.pump(const Duration(milliseconds: 220));
    game.pauseEngine();
    await tester.pump();

    expect(game.lastDistanceCm, greaterThanOrEqualTo(10000));
    expect(game.lastHitType, TenPitchHitType.homeRun);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'qc/runtime-home-run-celebration-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sub-100m long hit stays visually below the outfield wall', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('ten-pitch-below-wall-capture');
    final game = TenPitchSluggerGame(
      challengeSeed: 20260807,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    final targetTap =
        game.currentPitch.idealTapSeconds -
        game.currentPitch.hitWindowSeconds * 0.3;
    while (game.phaseElapsed < targetTap) {
      await tester.pump(const Duration(milliseconds: 2));
    }
    game.tapSwing();
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
    await tester.pump(const Duration(milliseconds: 1500));
    game.pauseEngine();
    await tester.pump();

    expect(game.lastDistanceCm, lessThan(10000));
    expect(game.lastHitType, TenPitchHitType.longHit);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'qc/runtime-long-hit-below-wall-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ground ball rolls low and avoids the pitcher lane', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('ten-pitch-ground-ball-capture');
    final game = TenPitchSluggerGame(
      challengeSeed: 20260807,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    final targetTap =
        game.currentPitch.idealTapSeconds -
        game.currentPitch.hitWindowSeconds * 0.9;
    while (game.phaseElapsed < targetTap) {
      await tester.pump(const Duration(milliseconds: 2));
    }
    game.tapSwing();
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
    await tester.pump(const Duration(milliseconds: 900));
    game.pauseEngine();
    await tester.pump();

    expect(game.lastHitType, TenPitchHitType.groundBall);
    expect(game.lastLaunchDirection, isNot(0));
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'qc/runtime-ground-ball-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missed pitch remains visible while passing the plate', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('ten-pitch-missed-ball-capture');
    final game = TenPitchSluggerGame(
      challengeSeed: 20260807,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    final earlyMissTap =
        game.currentPitch.idealTapSeconds -
        game.currentPitch.hitWindowSeconds -
        0.08;
    while (game.phaseElapsed < earlyMissTap) {
      await tester.pump(const Duration(milliseconds: 2));
    }
    game.tapSwing();
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
    await tester.pump(const Duration(milliseconds: 450));
    game.pauseEngine();
    await tester.pump();

    expect(game.lastDistanceCm, 0);
    expect(game.gamePhase, TenPitchSluggerPhase.feedback);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'qc/runtime-missed-ball-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('watched pitch leaves the batter idle without an auto swing', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('ten-pitch-watched-ball-capture');
    final game = TenPitchSluggerGame(
      challengeSeed: 20260807,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
    await tester.pump(const Duration(milliseconds: 100));
    game.pauseEngine();
    await tester.pump();

    expect(game.swingCount, 0);
    expect(game.hasTappedThisPitch, isFalse);
    expect(game.lastJudgement, TenPitchJudgement.watched);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'qc/runtime-watched-no-auto-swing-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tenth-pitch magic flight renders without freezing or overflow', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('ten-pitch-magic-capture');
    final game = TenPitchSluggerGame(
      challengeSeed: 20260807,
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);

    for (var index = 0; index < 9; index++) {
      expect(game.gamePhase, TenPitchSluggerPhase.windup);
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.feedback);
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.windup);
    }

    expect(game.pitchNumber, 10);
    expect(game.currentPitch.movement, TenPitchMovement.magic);
    expect(game.gamePhase, TenPitchSluggerPhase.windup);
    await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
    await tester.pump(const Duration(milliseconds: 550));
    game.pauseEngine();
    await tester.pump();

    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_TEN_PITCH_SLUGGER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ten_pitch_slugger/'
          'qc/runtime-magic-flight-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('runtime remains stable on short, canonical, and tall phones', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    for (final viewport in const [
      Size(320, 568),
      Size(360, 640),
      Size(430, 932),
    ]) {
      tester.view
        ..physicalSize = viewport
        ..devicePixelRatio = 1;
      final game = TenPitchSluggerGame(
        challengeSeed: 20260807,
        countdownDuration: Duration.zero,
        onFinished: (_) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(child: GameWidget(game: game)),
        ),
      );
      await _waitUntilLoaded(tester, game);
      await _pumpUntilPhase(tester, game, TenPitchSluggerPhase.pitchFlight);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: '$viewport');
      await tester.pumpWidget(const SizedBox.shrink());
      game.disposeController();
    }
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
  for (var tick = 0; tick < 500 && game.gamePhase != phase; tick++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(game.gamePhase, phase);
}

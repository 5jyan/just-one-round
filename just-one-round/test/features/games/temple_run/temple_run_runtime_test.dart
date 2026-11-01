import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';
import 'package:just_one_round/features/games/temple_run/temple_run_game.dart';

void main() {
  test(
    'projection widens toward the runner and stays centered on the road',
    () {
      final art = TempleRunArt();
      final far = art.project(TempleRunRules.farClipDistanceMeters);
      final near = art.project(0);

      expect(near.roadWidth, greaterThan(far.roadWidth));
      expect(near.scale, greaterThan(far.scale));
      expect(near.center.dy, greaterThan(far.center.dy));
    },
  );

  test(
    'portrait viewport keeps lane width and adds tall-device world space',
    () {
      final canonical = TempleRunGame.viewportResolutionForCanvas(
        Vector2(360, 640),
      );
      final tall = TempleRunGame.viewportResolutionForCanvas(Vector2(390, 844));
      final wide = TempleRunGame.viewportResolutionForCanvas(Vector2(430, 640));

      expect(canonical, Vector2(360, 640));
      expect(tall.x, 360);
      expect(tall.y, greaterThan(640));
      expect(tall.y, lessThanOrEqualTo(820));
      expect(wide.x, greaterThan(360));
      expect(wide.x, lessThanOrEqualTo(430));
      expect(wide.y, 640);
    },
  );

  test('outer lane runner bounds stay visible during either corner bend', () {
    final art = TempleRunArt(viewportWidth: 360, viewportHeight: 640);
    final course = TempleRunCourse(
      obstacles: const [],
      coins: const [],
      powerUps: const [],
      turns: const [],
      totalDistanceMeters: 100,
    );
    for (final direction in TempleRunTurnDirection.values) {
      art.updateScene(
        course: course,
        distanceMeters: 0,
        lane: TempleRunRules.centerLane,
        visualLane: TempleRunRules.centerLane.toDouble(),
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: 0,
        activeTurn: TempleRunTurn(
          distanceMeters: 20,
          direction: direction,
          windowStartMeters: 10,
          windowEndMeters: 24,
        ),
        bendProgress: 1,
        bendDirection: direction,
        cameraYaw: direction == TempleRunTurnDirection.left ? -0.14 : 0.14,
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
      );
      final projection = art.project(0);
      expect(projection.center.dx, closeTo(180, 0.001));
      for (final lane in [TempleRunRules.firstLane, TempleRunRules.lastLane]) {
        final laneCenter =
            projection.center.dx +
            (lane - TempleRunRules.centerLane) * projection.roadWidth / 3;
        expect(laneCenter - 48, greaterThanOrEqualTo(0));
        expect(laneCenter + 48, lessThanOrEqualTo(360));
      }
    }
  });

  testWidgets('runtime loads with the shared 360x640 camera contract', (
    tester,
  ) async {
    final game = TempleRunGame(
      countdownDuration: Duration.zero,
      enableTiltInput: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      await game.toBeLoaded();
      await game.ready();
    });
    await tester.pump();

    expect(game.isLoaded, isTrue);
    expect(game.courseForTesting.isReachable, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('production image mode preloads before the game is ready', (
    tester,
  ) async {
    final game = TempleRunGame(
      countdownDuration: Duration.zero,
      useImageAssets: true,
      enableTiltInput: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      await game.toBeLoaded();
      await game.ready();
    });
    await tester.pump();

    expect(game.isLoaded, isTrue);
    expect(game.courseForTesting.isReachable, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_preview.dart';

void main() {
  test('home and guide poses follow course distance at real contact times', () {
    final start = TempleRunPreviewSnapshot.forFrame(0);
    final beforeWrap = TempleRunPreviewSnapshot.forFrame(95);
    final afterWrap = TempleRunPreviewSnapshot.forFrame(96);
    final firstHurdle = TempleRunPreviewSnapshot.forFrame(36);
    final secondHurdle = TempleRunPreviewSnapshot.forFrame(64);
    final shutter = TempleRunPreviewSnapshot.forFrame(88);

    expect(start.scene, TempleRunPreviewScene.home);
    expect(start.distanceMeters, 52);
    expect(start.runnerFrame, 0);
    expect(start.lane, TempleRunRules.centerLane);
    expect(start.score, start.distanceMeters.floor() + start.coins * 10);
    expect(beforeWrap.distanceMeters, 99.5);
    expect(afterWrap.frame, 0);
    expect(afterWrap.distanceMeters, start.distanceMeters);
    expect(afterWrap.coins, start.coins);
    expect(afterWrap.score, start.score);

    for (final contact in [firstHurdle, secondHurdle]) {
      expect(contact.jumpActive, isTrue);
      expect(contact.jumpProgress, closeTo(.5, .0001));
      expect(contact.slideActive, isFalse);
    }
    expect(firstHurdle.distanceMeters, 70);
    expect(secondHurdle.distanceMeters, 84);
    expect(shutter.distanceMeters, 96);
    expect(shutter.slideActive, isTrue);
    expect(shutter.slideProgress, closeTo(.5, .0001));
    expect(shutter.jumpActive, isFalse);
    expect(TempleRunPreviewSnapshot.forFrame(72).jumpActive, isFalse);
  });

  test('all preview courses exclude removed gap hazards', () {
    for (final scene in TempleRunPreviewScene.values) {
      expect(
        TempleRunPreviewSnapshot.obstaclesForScene(
          scene,
        ).any((obstacle) => obstacle.kind == TempleRunObstacleKind.gap),
        isFalse,
        reason: scene.name,
      );
    }
  });

  test(
    'maneuver page crosses each full-width hazard during its six-second loop',
    () {
      final firstHurdle = TempleRunPreviewSnapshot.forFrame(
        16,
        scene: TempleRunPreviewScene.maneuvers,
      );
      final secondHurdle = TempleRunPreviewSnapshot.forFrame(
        44,
        scene: TempleRunPreviewScene.maneuvers,
      );
      final shutter = TempleRunPreviewSnapshot.forFrame(
        72,
        scene: TempleRunPreviewScene.maneuvers,
      );

      expect(firstHurdle.distanceMeters, 50);
      expect(secondHurdle.distanceMeters, 64);
      expect(shutter.distanceMeters, 78);
      for (final contact in [firstHurdle, secondHurdle]) {
        expect(contact.jumpActive, isTrue);
        expect(contact.jumpProgress, closeTo(.5, .0001));
      }
      expect(shutter.slideActive, isTrue);
      expect(shutter.slideProgress, closeTo(.5, .0001));
      expect(
        TempleRunPreviewSnapshot.forFrame(
          52,
          scene: TempleRunPreviewScene.maneuvers,
        ).jumpActive,
        isFalse,
      );
    },
  );

  test(
    'narrow path holds the runner inside its safe lane for the short interval',
    () {
      final narrowStart = TempleRunPreviewSnapshot.forFrame(12);
      final narrowMiddle = TempleRunPreviewSnapshot.forFrame(15);
      final narrowEnd = TempleRunPreviewSnapshot.forFrame(18);
      final clear = TempleRunPreviewSnapshot.forFrame(19);

      for (final narrow in [narrowStart, narrowMiddle, narrowEnd]) {
        expect(narrow.narrowPathActive, isTrue);
        expect(narrow.phoneTilt, closeTo(.92, .0001));
        expect(
          narrow.visualLane,
          inInclusiveRange(
            TempleRunRules.lastLane -
                TempleRunRules.narrowPathSafeHalfWidthInLanes -
                TempleRunRules.narrowPathLateralEpsilon,
            TempleRunRules.lastLane +
                TempleRunRules.narrowPathSafeHalfWidthInLanes +
                TempleRunRules.narrowPathLateralEpsilon,
          ),
        );
      }
      expect(clear.narrowPathActive, isFalse);
      expect(clear.jumpActive, isFalse);
    },
  );

  test('corner demo reserves three seconds before and crosses at 74m', () {
    final reserved = TempleRunPreviewSnapshot.forFrame(
      7,
      scene: TempleRunPreviewScene.controls,
    );
    final crossed = TempleRunPreviewSnapshot.forFrame(
      55,
      scene: TempleRunPreviewScene.corner,
    );

    expect(reserved.distanceMeters, 50);
    expect(reserved.turnReserved, isTrue);
    expect(reserved.turnCrossed, isFalse);
    expect(crossed.distanceMeters, 74);
    expect(crossed.turnReserved, isFalse);
    expect(crossed.turnCrossed, isTrue);
    expect(crossed.cornerVisible, isTrue);
    expect(crossed.completedTurnCount, 1);
    expect(crossed.bendProgress, 1);
    expect(crossed.caption, contains('새 길'));
  });

  testWidgets('home and guide scenes fit short and tall portrait slots', (
    tester,
  ) async {
    await tester.runAsync(TempleRunPreview.preloadAssets);
    for (final size in const [Size(393, 268), Size(393, 360), Size(393, 480)]) {
      for (final scene in TempleRunPreviewScene.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: TempleRunPreview(scene: scene, animate: false),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('temple-run-preview')), findsOneWidget);
        expect(find.byKey(const Key('temple-run-art')), findsOneWidget);
        expect(
          find.byKey(const Key('temple-run-preview-ready')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: '${scene.name} $size');
      }
    }
  });

  testWidgets(
    'animated home preview completes and restarts its six-second loop',
    (tester) async {
      await tester.runAsync(TempleRunPreview.preloadAssets);
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(width: 360, height: 460, child: TempleRunPreview()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('temple-run-preview-caption')), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const Key('temple-run-preview-ready')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

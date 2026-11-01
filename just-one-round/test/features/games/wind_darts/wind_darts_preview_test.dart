import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_preview.dart';

void main() {
  testWidgets(
    'home and all guide scenes render without overflow or asset errors',
    (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final scene in WindDartsPreviewScene.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: WindDartsPreview(scene: scene, animate: false),
              ),
            ),
          ),
        );
        for (
          var frame = 0;
          frame < 30 &&
              find
                  .byKey(const ValueKey('wind-darts-preview-ready'))
                  .evaluate()
                  .isEmpty;
          frame++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(
          find.byKey(const ValueKey('wind-darts-preview-ready')),
          findsOneWidget,
          reason: '$scene should finish loading its art bundle',
        );
        expect(tester.takeException(), isNull, reason: '$scene');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'guide slots keep every wind darts scene visible at phone sizes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      for (final size in const [
        Size(390, 360),
        Size(280, 260),
        Size(430, 462),
      ]) {
        tester.view.physicalSize = size;
        for (final scene in WindDartsPreviewScene.values) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox.expand(
                  child: WindDartsPreview(scene: scene, animate: false),
                ),
              ),
            ),
          );
          for (var frame = 0; frame < 24; frame++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump(const Duration(milliseconds: 25));
            if (find
                .byKey(const ValueKey('wind-darts-preview-ready'))
                .evaluate()
                .isNotEmpty) {
              break;
            }
          }
          expect(
            find.byKey(const ValueKey('wind-darts-preview-ready')),
            findsOneWidget,
            reason: '$scene should load at $size',
          );
          expect(tester.takeException(), isNull, reason: '$scene at $size');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('scoring preview target is the standard triple 20 ring', () {
    const boardRadius = 170.0;
    final target = Offset(
      0,
      -boardRadius *
          (WindDartsRules.tripleInnerRadiusRatio +
              WindDartsRules.tripleOuterRadiusRatio) /
          2,
    );
    final impact = WindDartsRules.resolveImpact(
      point: target,
      boardRadius: boardRadius,
      boardAngle: WindDartsRules.boardAngle,
    );

    expect(impact.sector, 20);
    expect(impact.multiplier, 3);
    expect(impact.score, 60);
  });

  test(
    'home preview follows production timing and resets its full seven-shot loop',
    () {
      final firstCycle = windDartsPreviewCycleSecondsForShot(0);
      final secondCycle = windDartsPreviewCycleSecondsForShot(1);
      final duration = windDartsPreviewDurationSeconds();

      expect(firstCycle, closeTo(2.4 + .72 + 2 + .7, 0.0001));
      expect(secondCycle, closeTo(firstCycle + .05, 0.0001));
      expect(
        duration,
        closeTo(
          firstCycle * WindDartsRules.shotCount +
              .05 *
                  (WindDartsRules.shotCount - 1) *
                  WindDartsRules.shotCount /
                  2,
          0.0001,
        ),
      );

      final firstShotFlight = windDartsPreviewTimingForElapsed(2.4);
      expect(firstShotFlight.shotIndex, 0);
      expect(firstShotFlight.phase, WindDartsPreviewPhase.flight);
      expect(firstShotFlight.flightProgress, closeTo(0, 0.0001));
      final firstShotImpact = windDartsPreviewTimingForElapsed(2.4 + .72);
      expect(firstShotImpact.phase, WindDartsPreviewPhase.impact);
      expect(firstShotImpact.impactProgress, closeTo(0, 0.0001));

      final firstBoundary = windDartsPreviewTimingForElapsed(firstCycle);
      expect(firstBoundary.shotIndex, 1);
      expect(firstBoundary.phase, WindDartsPreviewPhase.aim);
      final secondLoopStart = windDartsPreviewTimingForElapsed(duration);
      expect(secondLoopStart.shotIndex, 0);
      expect(secondLoopStart.phase, WindDartsPreviewPhase.aim);
      final secondLoopFirstBoundary = windDartsPreviewTimingForElapsed(
        duration + firstCycle,
      );
      expect(secondLoopFirstBoundary.shotIndex, 1);
      expect(secondLoopFirstBoundary.phase, WindDartsPreviewPhase.aim);
    },
  );

  test(
    'home preview scores are legal and the golden seventh shot is doubled',
    () {
      expect(windDartsPreviewScoreForShot(6), 120);
      expect(windDartsPreviewTotalForCompletedShots(7), 333);
      for (var shot = 0; shot < WindDartsRules.shotCount; shot++) {
        expect(
          windDartsPreviewManualAimOffsetForShot(shot).distance,
          lessThanOrEqualTo(WindDartsRules.baseBoardRadius * .75),
          reason: 'staged launch $shot must fit the production drag limit',
        );
      }
    },
  );
}

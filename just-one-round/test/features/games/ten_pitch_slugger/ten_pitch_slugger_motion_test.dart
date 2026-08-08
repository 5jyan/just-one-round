import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/domain/ten_pitch_slugger_rules.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_motion.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_scene.dart';

void main() {
  test(
    'authored swing reaches the contact frame at the unchanged lead time',
    () {
      expect(TenPitchSluggerRules.swingLeadSeconds, 0.12);
      expect(
        TenPitchSluggerMotion.batterSwingFrame(
          TenPitchSluggerRules.swingLeadSeconds,
        ),
        TenPitchSluggerScene.batterContactFrame,
      );

      const size = Size(360, 640);
      expect(
        (TenPitchSluggerScene.batterContactTipFor(size) -
                TenPitchSluggerScene.contactFor(size))
            .distance,
        lessThanOrEqualTo(4),
      );
    },
  );

  test('V4 swing has readable load, contact hold, and full follow-through', () {
    expect(TenPitchSluggerMotion.batterSwingFrame(0), 0);
    expect(TenPitchSluggerMotion.batterSwingFrame(0.083), 5);
    expect(
      TenPitchSluggerMotion.batterSwingFrame(0.12),
      TenPitchSluggerScene.batterContactFrame,
    );
    expect(TenPitchSluggerMotion.batterSwingFrame(0.30), 13);
    expect(
      TenPitchSluggerMotion.batterSwingFrame(
        TenPitchSluggerMotion.swingDurationSeconds,
      ),
      15,
    );

    expect(
      TenPitchSluggerMotion.batterFeedbackSwingFrame(
        elapsedSeconds:
            TenPitchSluggerMotion.hitStopDurationFor(TenPitchHitType.homeRun) -
            0.001,
        hit: true,
        hitType: TenPitchHitType.homeRun,
      ),
      TenPitchSluggerScene.batterContactFrame,
    );
    expect(
      TenPitchSluggerMotion.batterFeedbackSwingFrame(
        elapsedSeconds: TenPitchSluggerMotion.feedbackSwingDuration(hit: true),
        hit: true,
      ),
      15,
    );
  });

  test('pitcher follows through and then returns to idle during flight', () {
    expect(TenPitchSluggerMotion.regularFollowThroughFrame(0), 5);
    expect(TenPitchSluggerMotion.regularFollowThroughFrame(0.20), isNot(5));
    expect(TenPitchSluggerMotion.regularFollowThroughFrame(0.53), -1);

    expect(TenPitchSluggerMotion.magicFollowThroughFrame(0), 11);
    expect(TenPitchSluggerMotion.magicFollowThroughFrame(0.30), isNot(11));
    expect(TenPitchSluggerMotion.magicFollowThroughFrame(0.67), -1);
  });

  test(
    'ball perspective is monotonic, slower far away, and exact at contact',
    () {
      final samples = <double>[
        for (var index = 0; index <= 10; index++)
          TenPitchSluggerMotion.perspectiveProgress(index / 10),
      ];
      for (var index = 1; index < samples.length; index++) {
        expect(samples[index], greaterThan(samples[index - 1]));
      }
      expect(samples.first, 0);
      expect(samples[5], lessThan(0.5));
      expect(samples.last, 1);
    },
  );

  test('successful visual correction ends exactly at the bat', () {
    expect(
      TenPitchSluggerMotion.contactCorrection(
        elapsedSeconds: 1.2,
        resolutionSeconds: 1.2,
      ),
      1,
    );
    expect(
      TenPitchSluggerMotion.contactCorrection(
        elapsedSeconds: 1.12,
        resolutionSeconds: 1.2,
      ),
      0,
    );
  });

  test('hit stop holds the ball before the long launch begins', () {
    var previousDuration = 0.0;
    for (final hitType in TenPitchHitType.values) {
      final duration = TenPitchSluggerMotion.launchDurationFor(hitType);
      expect(duration, greaterThan(previousDuration));
      previousDuration = duration;
      expect(TenPitchSluggerMotion.launchProgress(0, hitType: hitType), 0);
      expect(
        TenPitchSluggerMotion.launchProgress(
          TenPitchSluggerMotion.hitStopDurationFor(hitType),
          hitType: hitType,
        ),
        0,
      );
      expect(
        TenPitchSluggerMotion.launchProgress(
          TenPitchSluggerMotion.hitStopDurationFor(hitType) +
              TenPitchSluggerMotion.launchDurationFor(hitType),
          hitType: hitType,
        ),
        closeTo(1, 0.000001),
      );
    }
  });

  test('five hit types have progressively deeper and higher trajectories', () {
    final contact = TenPitchSluggerScene.contactFor(const Size(360, 640));
    final midpoints = <Offset>[];
    final endpoints = <Offset>[];
    for (final hitType in TenPitchHitType.values) {
      midpoints.add(
        TenPitchSluggerMotion.launchedBallPoint(
          contact: contact,
          progress: 0.5,
          quality: 0.5,
          direction: 1,
          hitType: hitType,
        ),
      );
      endpoints.add(
        TenPitchSluggerMotion.launchedBallPoint(
          contact: contact,
          progress: 1,
          quality: 0.5,
          direction: 1,
          hitType: hitType,
        ),
      );
    }

    for (var index = 1; index < midpoints.length; index++) {
      expect(midpoints[index].dy, lessThan(midpoints[index - 1].dy));
      expect(endpoints[index].dy, lessThan(endpoints[index - 1].dy));
    }
    expect(endpoints.first.dy, greaterThan(260));
    expect(endpoints.last.dy, inInclusiveRange(100, 160));
  });

  test('hit types use distinct ball scale and trail density', () {
    for (final hitType in TenPitchHitType.values) {
      expect(TenPitchSluggerMotion.launchedBallSize(0, hitType: hitType), 30);
      expect(
        TenPitchSluggerMotion.launchedBallSize(0.5, hitType: hitType),
        lessThan(30),
      );
    }
    expect(
      TenPitchSluggerMotion.launchedBallSize(
        1,
        hitType: TenPitchHitType.groundBall,
      ),
      9,
    );
    expect(
      TenPitchSluggerMotion.launchedBallSize(
        1,
        hitType: TenPitchHitType.homeRun,
      ),
      3,
    );
    expect(
      TenPitchSluggerMotion.afterimageCountFor(TenPitchHitType.groundBall),
      1,
    );
    expect(TenPitchSluggerMotion.afterimageCountFor(TenPitchHitType.single), 2);
    expect(TenPitchSluggerMotion.afterimageCountFor(TenPitchHitType.double), 3);
    expect(
      TenPitchSluggerMotion.afterimageCountFor(TenPitchHitType.longHit),
      4,
    );
    expect(
      TenPitchSluggerMotion.afterimageCountFor(TenPitchHitType.homeRun),
      7,
    );
  });

  test('far-flight coast keeps moving and shrinking after authored launch', () {
    final contact = TenPitchSluggerScene.contactFor(const Size(360, 640));
    final launchEnd = TenPitchSluggerMotion.launchedBallPoint(
      contact: contact,
      progress: 1,
      quality: 1,
      direction: 1,
      hitType: TenPitchHitType.homeRun,
    );
    final coastEnd = TenPitchSluggerMotion.launchedBallPoint(
      contact: contact,
      progress: 1 + TenPitchSluggerMotion.farFlightProgress,
      quality: 1,
      direction: 1,
      hitType: TenPitchHitType.homeRun,
    );
    final launchEndSize = TenPitchSluggerMotion.launchedBallSize(
      1,
      hitType: TenPitchHitType.homeRun,
    );
    final coastEndSize = TenPitchSluggerMotion.launchedBallSize(
      1 + TenPitchSluggerMotion.farFlightProgress,
      hitType: TenPitchHitType.homeRun,
    );

    expect(coastEnd.dx, greaterThan(launchEnd.dx));
    expect(coastEnd.dy, greaterThan(launchEnd.dy));
    expect(coastEndSize, lessThan(launchEndSize));
  });

  test('fly balls descend late while ground balls stay on the dirt', () {
    final contact = TenPitchSluggerScene.contactFor(const Size(360, 640));

    for (final hitType in TenPitchHitType.values.where(
      (value) => value != TenPitchHitType.groundBall,
    )) {
      final apex = TenPitchSluggerMotion.launchedBallPoint(
        contact: contact,
        progress: 0.72,
        quality: 0.5,
        direction: 1,
        hitType: hitType,
      );
      final landing = TenPitchSluggerMotion.launchedBallPoint(
        contact: contact,
        progress: 1 + TenPitchSluggerMotion.farFlightProgress,
        quality: 0.5,
        direction: 1,
        hitType: hitType,
      );
      expect(landing.dy, greaterThan(apex.dy), reason: '$hitType must fall');
    }

    for (final progress in const <double>[0.25, 0.5, 0.75, 1]) {
      final groundBall = TenPitchSluggerMotion.launchedBallPoint(
        contact: contact,
        progress: progress,
        quality: 0.5,
        direction: -1,
        hitType: TenPitchHitType.groundBall,
      );
      expect(groundBall.dy, greaterThan(300));
    }
  });

  test('all four launch lanes remain visible through the far-flight coast', () {
    final contact = TenPitchSluggerScene.contactFor(const Size(360, 640));
    final coastProgress = 1 + TenPitchSluggerMotion.farFlightProgress;

    for (final hitType in TenPitchHitType.values) {
      for (final direction in const <double>[-1, -0.45, 0.45, 1]) {
        final endpoint = TenPitchSluggerMotion.launchedBallPoint(
          contact: contact,
          progress: coastProgress,
          quality: 1,
          direction: direction,
          hitType: hitType,
        );
        expect(endpoint.dx, inInclusiveRange(0, 360));
      }
    }
  });

  test(
    'a missed pitch continues past the plate and fades below the screen',
    () {
      const release = Offset(180, 284);
      const contact = Offset(194, 474);
      final start = TenPitchSluggerMotion.missedBallPoint(
        release: release,
        contact: contact,
        progress: 0,
      );
      final middle = TenPitchSluggerMotion.missedBallPoint(
        release: release,
        contact: contact,
        progress: 0.5,
      );
      final end = TenPitchSluggerMotion.missedBallPoint(
        release: release,
        contact: contact,
        progress: 1,
      );

      expect(start, contact);
      expect(middle.dy, greaterThan(contact.dy));
      expect(end.dy, greaterThan(640));
      expect(TenPitchSluggerMotion.missedBallSize(1), greaterThan(30));
      expect(TenPitchSluggerMotion.missedBallOpacity(0.7), 1);
      expect(TenPitchSluggerMotion.missedBallOpacity(1), 0);
    },
  );

  test('every 100m home run clears the wall even after descending', () {
    final contact = TenPitchSluggerScene.contactFor(const Size(360, 640));
    final coastProgress = 1 + TenPitchSluggerMotion.farFlightProgress;

    for (final hitType in TenPitchHitType.values.where(
      (value) => value != TenPitchHitType.homeRun,
    )) {
      final endpoint = TenPitchSluggerMotion.launchedBallPoint(
        contact: contact,
        progress: coastProgress,
        quality: 1,
        direction: 1,
        hitType: hitType,
      );
      expect(endpoint.dy, greaterThanOrEqualTo(280));
    }

    final thresholdHomeRun = TenPitchSluggerMotion.launchedBallPoint(
      contact: contact,
      progress: coastProgress,
      quality: TenPitchSluggerRules.wallHeightProgress(10000),
      direction: 0,
      hitType: TenPitchHitType.homeRun,
    );
    final farBeyond = TenPitchSluggerMotion.launchedBallPoint(
      contact: contact,
      progress: coastProgress,
      quality: 1,
      direction: 0,
      hitType: TenPitchHitType.homeRun,
    );

    expect(thresholdHomeRun.dy, lessThan(280));
    expect(farBeyond.dy, lessThan(100));
    expect(farBeyond.dy, lessThan(thresholdHomeRun.dy));
  });

  test('home-run launch adds a readable slow-motion opening', () {
    final normal = TenPitchSluggerMotion.launchProgress(
      TenPitchSluggerMotion.hitStopDurationFor(TenPitchHitType.double) +
          TenPitchSluggerMotion.launchDurationFor(TenPitchHitType.double) *
              0.25,
      hitType: TenPitchHitType.double,
    );
    final homeRun = TenPitchSluggerMotion.launchProgress(
      TenPitchSluggerMotion.hitStopDurationFor(TenPitchHitType.homeRun) +
          TenPitchSluggerMotion.launchDurationFor(TenPitchHitType.homeRun) *
              0.25,
      hitType: TenPitchHitType.homeRun,
    );

    expect(normal, closeTo(0.25, 0.000001));
    expect(homeRun, lessThan(normal));
  });

  test('home-run celebration pops, holds, and fades', () {
    expect(TenPitchSluggerMotion.homeRunCelebrationOpacity(0), 0);
    expect(TenPitchSluggerMotion.homeRunCelebrationOpacity(0.10), 1);
    expect(TenPitchSluggerMotion.homeRunCelebrationOpacity(0.92), 1);
    expect(
      TenPitchSluggerMotion.homeRunCelebrationOpacity(
        TenPitchSluggerMotion.homeRunCelebrationDuration,
      ),
      0,
    );
    expect(TenPitchSluggerMotion.homeRunCelebrationScale(0), 0.72);
    expect(TenPitchSluggerMotion.homeRunCelebrationScale(0.14), 1.10);
    expect(TenPitchSluggerMotion.homeRunCelebrationScale(0.28), 1);
  });

  test('impact size, flash, and shake rise across all five hit types', () {
    var previousScale = 0.0;
    var previousFxDuration = 0.0;
    var previousFlash = 0.0;
    var previousStrength = 0.0;
    var previousShakeDuration = 0.0;

    for (final hitType in TenPitchHitType.values) {
      final scale = TenPitchSluggerMotion.hitFxScaleFor(hitType);
      final fxDuration = TenPitchSluggerMotion.hitFxDurationFor(hitType);
      final flash = TenPitchSluggerMotion.hitFlashPeakOpacityFor(hitType);
      final strength = TenPitchSluggerMotion.hitShakeStrengthFor(hitType);
      final shakeDuration = TenPitchSluggerMotion.hitShakeDurationFor(hitType);

      expect(scale, greaterThan(previousScale));
      expect(fxDuration, greaterThan(previousFxDuration));
      expect(flash, greaterThan(previousFlash));
      expect(strength, greaterThan(previousStrength));
      expect(shakeDuration, greaterThan(previousShakeDuration));
      expect(TenPitchSluggerMotion.hitFxFrame(0, hitType: hitType), 0);
      expect(
        TenPitchSluggerMotion.hitFxFrame(fxDuration - 0.001, hitType: hitType),
        7,
      );
      expect(TenPitchSluggerMotion.hitFlashOpacity(0, hitType: hitType), flash);
      expect(
        TenPitchSluggerMotion.hitFlashOpacity(
          TenPitchSluggerMotion.hitFlashDurationFor(hitType),
          hitType: hitType,
        ),
        0,
      );

      for (var step = 0; step * 0.01 < shakeDuration; step++) {
        final offset = TenPitchSluggerMotion.hitShakeOffset(
          elapsedSeconds: step / 100,
          strength: strength,
          duration: shakeDuration,
          seed: 3,
        );
        expect(offset.dx.abs(), lessThanOrEqualTo(strength.ceil()));
        expect(offset.dy.abs(), lessThanOrEqualTo(strength.ceil()));
        expect(offset.dx, offset.dx.roundToDouble());
        expect(offset.dy, offset.dy.roundToDouble());
      }
      expect(
        TenPitchSluggerMotion.hitShakeOffset(
          elapsedSeconds: shakeDuration,
          strength: strength,
          duration: shakeDuration,
          seed: 3,
        ),
        Offset.zero,
      );

      previousScale = scale;
      previousFxDuration = fxDuration;
      previousFlash = flash;
      previousStrength = strength;
      previousShakeDuration = shakeDuration;
    }
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/domain/ten_pitch_slugger_rules.dart';

void main() {
  test('builds ten deterministic pitches with strictly shrinking windows', () {
    final first = TenPitchSluggerRules.buildPitchSequence(Random(20260807));
    final second = TenPitchSluggerRules.buildPitchSequence(Random(20260807));

    expect(first.length, TenPitchSluggerRules.pitchCount);
    expect(
      first.map((pitch) => pitch.flightSeconds),
      second.map((pitch) => pitch.flightSeconds),
    );
    for (var index = 1; index < first.length; index++) {
      expect(
        first[index].flightSeconds,
        lessThan(first[index - 1].flightSeconds),
      );
      expect(
        first[index].hitWindowSeconds,
        lessThan(first[index - 1].hitWindowSeconds),
      );
      expect(
        first[index].maximumDistanceCm,
        greaterThan(first[index - 1].maximumDistanceCm),
      );
    }
    expect(first.first.movement, TenPitchMovement.straight);
    expect(first.last.movement, TenPitchMovement.magic);
    expect(first.last.name, contains('마구'));
    expect(
      first.every(
        (pitch) =>
            pitch.idealTapSeconds >=
            TenPitchSluggerRules.minimumIdealTapSeconds,
      ),
      isTrue,
    );
    expect(
      first.first.flightSeconds / first.last.flightSeconds,
      greaterThan(2.5),
    );
    expect(first.last.flightSeconds, inInclusiveRange(0.594, 0.606));
    expect(first.last.idealTapSeconds, inInclusiveRange(0.474, 0.486));
  });

  test(
    'perfect timing reaches each cap and the best is the theory maximum',
    () {
      final pitches = TenPitchSluggerRules.buildPitchSequence(Random(1));
      final distances = pitches
          .map(
            (pitch) => TenPitchSluggerRules.distanceForTiming(
              pitch: pitch,
              timingErrorSeconds: 0,
            ),
          )
          .toList();

      expect(distances.last, TenPitchSluggerRules.theoreticalMaximumScoreCm);
      expect(
        distances.reduce(max),
        TenPitchSluggerRules.theoreticalMaximumScoreCm,
      );
    },
  );

  test('window edge is a short hit and outside the window is a miss', () {
    final pitch = TenPitchSluggerRules.buildPitchSequence(Random(7)).first;

    expect(
      TenPitchSluggerRules.distanceForTiming(
        pitch: pitch,
        timingErrorSeconds: pitch.hitWindowSeconds,
      ),
      TenPitchSluggerRules.minimumHitDistanceCm,
    );
    expect(
      TenPitchSluggerRules.distanceForTiming(
        pitch: pitch,
        timingErrorSeconds: pitch.hitWindowSeconds + 0.000001,
      ),
      0,
    );
  });

  test('distance thresholds classify five visibly distinct hit types', () {
    expect(TenPitchSluggerRules.hitTypeForDistance(0), isNull);
    expect(
      TenPitchSluggerRules.hitTypeForDistance(3500),
      TenPitchHitType.groundBall,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(4299),
      TenPitchHitType.groundBall,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(4300),
      TenPitchHitType.single,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(5499),
      TenPitchHitType.single,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(5500),
      TenPitchHitType.double,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(6999),
      TenPitchHitType.double,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(7000),
      TenPitchHitType.longHit,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(9999),
      TenPitchHitType.longHit,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(10000),
      TenPitchHitType.homeRun,
    );
  });

  test('rebalanced timing bands award restrained everyday distances', () {
    final pitch = TenPitchSluggerRules.buildPitchSequence(Random(16)).first;
    const timingRatios = <double>[0.9, 0.7, 0.5, 0.3];
    const expectedRanges = <(int, int)>[
      (3500, 4299),
      (4300, 5499),
      (5500, 6999),
      (7000, 9999),
    ];

    for (var index = 0; index < timingRatios.length; index++) {
      final distance = TenPitchSluggerRules.distanceForTiming(
        pitch: pitch,
        timingErrorSeconds: pitch.hitWindowSeconds * timingRatios[index],
      );
      expect(
        distance,
        inInclusiveRange(expectedRanges[index].$1, expectedRanges[index].$2),
      );
    }
  });

  test('home runs require the narrow central 12 percent timing band', () {
    final pitch = TenPitchSluggerRules.buildPitchSequence(Random(26)).last;
    expect(TenPitchSluggerRules.homeRunTimingRatio, 0.12);

    final boundary = TenPitchSluggerRules.distanceForTiming(
      pitch: pitch,
      timingErrorSeconds:
          pitch.hitWindowSeconds * TenPitchSluggerRules.homeRunTimingRatio,
    );
    final justInside = TenPitchSluggerRules.distanceForTiming(
      pitch: pitch,
      timingErrorSeconds:
          pitch.hitWindowSeconds *
          (TenPitchSluggerRules.homeRunTimingRatio - 0.000001),
    );

    expect(boundary, 9999);
    expect(
      TenPitchSluggerRules.hitTypeForDistance(boundary),
      TenPitchHitType.longHit,
    );
    expect(justInside, greaterThanOrEqualTo(10000));
    expect(
      TenPitchSluggerRules.hitTypeForDistance(justInside),
      TenPitchHitType.homeRun,
    );
  });

  test('later pitches give more distance for the same excellent timing', () {
    final pitches = TenPitchSluggerRules.buildPitchSequence(Random(17));
    final first = pitches.first;
    final last = pitches.last;
    final firstDistance = TenPitchSluggerRules.distanceForTiming(
      pitch: first,
      timingErrorSeconds: first.hitWindowSeconds * 0.1,
    );
    final lastDistance = TenPitchSluggerRules.distanceForTiming(
      pitch: last,
      timingErrorSeconds: last.hitWindowSeconds * 0.1,
    );

    expect(first.maximumDistanceCm, 10500);
    expect(last.maximumDistanceCm, 15000);
    expect(lastDistance, greaterThan(firstDistance));
    expect(
      TenPitchSluggerRules.hitTypeForDistance(firstDistance),
      TenPitchHitType.homeRun,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(lastDistance),
      TenPitchHitType.homeRun,
    );
  });

  test('the same ordinary contact travels farther on later pitches', () {
    final pitches = TenPitchSluggerRules.buildPitchSequence(Random(27));
    final first = pitches.first;
    final middle = pitches[4];
    final late = pitches[6];
    final last = pitches.last;

    for (final ratio in const <double>[0.9, 0.7, 0.5, 0.3]) {
      int distance(TenPitchSpec pitch) =>
          TenPitchSluggerRules.distanceForTiming(
            pitch: pitch,
            timingErrorSeconds: pitch.hitWindowSeconds * ratio,
          );

      expect(distance(middle), greaterThan(distance(first)), reason: '$ratio');
      expect(distance(last), greaterThan(distance(middle)), reason: '$ratio');
    }

    final firstMidContact = TenPitchSluggerRules.distanceForTiming(
      pitch: first,
      timingErrorSeconds: first.hitWindowSeconds * 0.5,
    );
    final lastMidContact = TenPitchSluggerRules.distanceForTiming(
      pitch: last,
      timingErrorSeconds: last.hitWindowSeconds * 0.5,
    );
    expect(firstMidContact, inInclusiveRange(5500, 6999));
    expect(lastMidContact, inInclusiveRange(7000, 9999));
    expect(lastMidContact - firstMidContact, greaterThanOrEqualTo(1800));

    final middleMidContact = TenPitchSluggerRules.distanceForTiming(
      pitch: middle,
      timingErrorSeconds: middle.hitWindowSeconds * 0.5,
    );
    final lateMidContact = TenPitchSluggerRules.distanceForTiming(
      pitch: late,
      timingErrorSeconds: late.hitWindowSeconds * 0.5,
    );
    expect(middleMidContact - firstMidContact, lessThan(500));
    expect(lateMidContact - firstMidContact, greaterThan(800));

    final lastLooseContact = TenPitchSluggerRules.distanceForTiming(
      pitch: last,
      timingErrorSeconds: last.hitWindowSeconds * 0.7,
    );
    expect(
      TenPitchSluggerRules.hitTypeForDistance(lastLooseContact),
      TenPitchHitType.double,
    );
  });

  test('the first pitch baseline produces all five contact types', () {
    final pitch = TenPitchSluggerRules.buildPitchSequence(Random(18)).first;
    const expectedTypes = <TenPitchHitType>[
      TenPitchHitType.groundBall,
      TenPitchHitType.single,
      TenPitchHitType.double,
      TenPitchHitType.longHit,
      TenPitchHitType.homeRun,
    ];
    const timingRatios = <double>[0.9, 0.7, 0.5, 0.3, 0.1];

    for (var index = 0; index < timingRatios.length; index++) {
      final distance = TenPitchSluggerRules.distanceForTiming(
        pitch: pitch,
        timingErrorSeconds: pitch.hitWindowSeconds * timingRatios[index],
      );
      expect(
        TenPitchSluggerRules.hitTypeForDistance(distance),
        expectedTypes[index],
        reason: 'timing ratio ${timingRatios[index]}',
      );
    }
  });

  test('seed and timing distribute contact across four non-center lanes', () {
    final pitches = TenPitchSluggerRules.buildPitchSequence(Random(22));
    final pitch = pitches.first;
    final early = TenPitchSluggerRules.launchDirectionForTiming(
      pitch: pitch,
      timingErrorSeconds: -pitch.hitWindowSeconds * 0.5,
    );
    final late = TenPitchSluggerRules.launchDirectionForTiming(
      pitch: pitch,
      timingErrorSeconds: pitch.hitWindowSeconds * 0.5,
    );
    final seededDirections = pitches
        .map(
          (value) => TenPitchSluggerRules.launchDirectionForTiming(
            pitch: value,
            timingErrorSeconds: 0,
          ),
        )
        .toSet();

    expect(early, lessThan(late));
    expect(seededDirections.length, greaterThanOrEqualTo(3));
    expect(
      seededDirections.every(
        (direction) => const <double>[-1, -0.45, 0.45, 1].contains(direction),
      ),
      isTrue,
    );
    expect(seededDirections, isNot(contains(0)));
  });

  test('distance progress resets at the wall and rises within each tier', () {
    final pitch = TenPitchSluggerRules.buildPitchSequence(Random(24)).last;

    expect(
      TenPitchSluggerRules.hitTypeProgress(pitch: pitch, distanceCm: 7000),
      0,
    );
    expect(
      TenPitchSluggerRules.hitTypeProgress(pitch: pitch, distanceCm: 9999),
      1,
    );
    expect(
      TenPitchSluggerRules.hitTypeProgress(pitch: pitch, distanceCm: 10000),
      0,
    );
    expect(
      TenPitchSluggerRules.hitTypeProgress(
        pitch: pitch,
        distanceCm: pitch.maximumDistanceCm,
      ),
      1,
    );
  });

  test('normalized quality uses each pitch own min-to-cap range', () {
    final pitch = TenPitchSluggerRules.buildPitchSequence(Random(23)).last;

    expect(
      TenPitchSluggerRules.normalizedHitQuality(
        pitch: pitch,
        distanceCm: TenPitchSluggerRules.minimumHitDistanceCm,
      ),
      0,
    );
    expect(
      TenPitchSluggerRules.normalizedHitQuality(
        pitch: pitch,
        distanceCm: pitch.maximumDistanceCm,
      ),
      1,
    );
  });

  test('wall clearance starts at the 100m home-run threshold', () {
    expect(TenPitchSluggerRules.wallClearDistanceCm, 10000);
    expect(TenPitchSluggerRules.wallClearTrajectoryProgress, 0);
    expect(TenPitchSluggerRules.wallHeightProgress(10000), 0);
    expect(TenPitchSluggerRules.wallHeightProgress(13000), 0.6);
    expect(TenPitchSluggerRules.wallHeightProgress(15000), 1);
  });

  test('score formatting treats raw score as centimeters', () {
    expect(TenPitchSluggerRules.formatScore(15000), '150.00m');
    expect(TenPitchSluggerRules.formatHudScore(12345), '123.5m');
  });

  test('feedback distinguishes perfect, early, late, and watched pitches', () {
    final pitch = TenPitchSluggerRules.buildPitchSequence(Random(8)).first;

    expect(
      TenPitchSluggerRules.judgementForTiming(
        pitch: pitch,
        timingErrorSeconds: 0,
      ),
      TenPitchJudgement.perfect,
    );
    expect(
      TenPitchSluggerRules.judgementForTiming(
        pitch: pitch,
        timingErrorSeconds: -pitch.hitWindowSeconds - 0.01,
      ),
      TenPitchJudgement.earlyMiss,
    );
    expect(
      TenPitchSluggerRules.judgementForTiming(
        pitch: pitch,
        timingErrorSeconds: pitch.hitWindowSeconds + 0.01,
      ),
      TenPitchJudgement.lateMiss,
    );
    expect(
      TenPitchSluggerRules.judgementForTiming(
        pitch: pitch,
        timingErrorSeconds: null,
      ),
      TenPitchJudgement.watched,
    );
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';

void main() {
  group('WindDartsRules', () {
    test('uses the standard clockwise sector order and multipliers', () {
      const radius = 64.0;
      expect(
        WindDartsRules.resolveImpact(
          point: const Offset(0, -20),
          boardRadius: radius,
          boardAngle: 0,
        ).score,
        20,
      );
      expect(
        WindDartsRules.resolveImpact(
          point: const Offset(0, -40),
          boardRadius: radius,
          boardAngle: 0,
        ).score,
        60,
      );
      expect(
        WindDartsRules.resolveImpact(
          point: const Offset(0, -63.5),
          boardRadius: radius,
          boardAngle: 0,
        ).score,
        40,
      );
      expect(
        WindDartsRules.resolveImpact(
          point: const Offset(0, -2),
          boardRadius: radius,
          boardAngle: 0,
        ).score,
        50,
      );
      expect(
        WindDartsRules.resolveImpact(
          point: const Offset(0, -5.8),
          boardRadius: radius,
          boardAngle: 0,
        ).score,
        50,
      );
      expect(
        WindDartsRules.resolveImpact(
          point: Offset(0, -radius * WindDartsRules.tripleInnerRadiusRatio),
          boardRadius: radius,
          boardAngle: WindDartsRules.boardAngle,
        ).kind,
        WindDartsImpactKind.triple,
      );
      expect(
        WindDartsRules.resolveImpact(
          point: Offset(0, -radius * WindDartsRules.doubleInnerRadiusRatio),
          boardRadius: radius,
          boardAngle: WindDartsRules.boardAngle,
        ).kind,
        WindDartsImpactKind.double,
      );
      final fullBullBoundary = WindDartsRules.resolveImpact(
        point: Offset(0, -radius * 15.9 / 170),
        boardRadius: radius,
        boardAngle: 0,
      );
      expect(fullBullBoundary.score, 50);
      expect(fullBullBoundary.sector, 25);
      expect(fullBullBoundary.multiplier, 2);
      expect(fullBullBoundary.kind, WindDartsImpactKind.doubleBull);
      expect(
        WindDartsRules.resolveImpact(
          point: const Offset(0, -65),
          boardRadius: radius,
          boardAngle: 0,
        ).score,
        0,
      );
    });

    test('keeps the board angle fixed in the runtime rule', () {
      final impact = WindDartsRules.resolveImpact(
        point: const Offset(20, 0),
        boardRadius: 64,
        boardAngle: pi / 2,
      );
      expect(impact.sector, 20);
      expect(impact.score, 20);
      expect(WindDartsRules.boardAngleAt(0), -pi / 20);
      expect(WindDartsRules.boardAngleAt(100), -pi / 20);
      expect(
        WindDartsRules.resolveImpact(
          point: Offset(0, -64),
          boardRadius: 64,
          boardAngle: WindDartsRules.boardAngle,
        ).sector,
        20,
        reason: '20 must sit at the 12 o\'clock axis',
      );
    });

    test('provides reproducible wind, aim timing, and distance scaling', () {
      final first = WindDartsRules.windsForSeed(42);
      final second = WindDartsRules.windsForSeed(42);
      expect(
        first.map((wind) => [wind.clockDirection, wind.metersPerSecond]),
        second.map((wind) => [wind.clockDirection, wind.metersPerSecond]),
      );
      expect(first, hasLength(WindDartsRules.shotCount));
      expect(
        first.every(
          (wind) => wind.clockDirection >= 0 && wind.clockDirection < 12,
        ),
        isTrue,
      );
      expect(
        first.every(
          (wind) => wind.metersPerSecond >= 0.5 && wind.metersPerSecond <= 3.5,
        ),
        isTrue,
      );
      expect(WindDartsRules.rulesVersion, 3);
      expect(WindDartsRules.shotCount, 6);
      expect(WindDartsRules.windOffsetCoefficient, 0.48);
      expect(WindDartsRules.aimJitterHorizontalCoefficient, 0.36);
      expect(WindDartsRules.aimJitterVerticalCoefficient, 0.30);
      expect(WindDartsRules.impactDisplayDuration, const Duration(seconds: 2));
      expect(WindDartsRules.tripleInnerRadiusRatio, 95 / 170);
      expect(WindDartsRules.tripleOuterRadiusRatio, 111 / 170);
      expect(WindDartsRules.doubleInnerRadiusRatio, 154 / 170);
      expect(WindDartsRules.aimAt(0, 64).offset, Offset.zero);
      expect(WindDartsRules.powerAt(0), 0);
      expect(WindDartsRules.powerAt(1.5), 0.25);
      expect(WindDartsRules.powerAt(3), 0.5);
      expect(WindDartsRules.powerAt(4.5), 0.75);
      expect(WindDartsRules.powerAt(6), 1);
      expect(WindDartsRules.powerAt(9), 1);
      expect(
        WindDartsRules.aimAt(9, 64).offset,
        isNot(equals(WindDartsRules.aimAt(6, 64).offset)),
      );
      final jitter = WindDartsRules.aimAt(1, 100).offset;
      expect(jitter.dx, closeTo(sin(2.25) * 36, 0.000001));
      expect(jitter.dy, closeTo(sin(1.73) * 30, 0.000001));
      expect(List.generate(6, WindDartsRules.boardScaleForShot), [
        1,
        0.91,
        0.82,
        0.745,
        0.67,
        0.61,
      ]);
      expect(List.generate(6, WindDartsRules.distanceForShot), [
        1,
        1.5,
        2,
        2.5,
        3,
        3.5,
      ]);
      expect(WindDartsRules.baseBoardRadius, 142);
      expect(WindDartsRules.boardScaleForShot(5), 0.61);
      expect(WindDartsRules.distanceLabelForShot(1), '1.5m');
      expect(WindDartsRules.rankingScore(360), 360);
    });
  });
}

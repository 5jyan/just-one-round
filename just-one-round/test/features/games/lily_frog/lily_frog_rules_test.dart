import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/lily_frog/domain/lily_field_generator.dart';
import 'package:just_one_round/features/games/lily_frog/domain/lily_frog_rules.dart';

void main() {
  group('LilyFrogRules', () {
    test('접선 방향은 회전 방향에 따라 반대가 된다', () {
      final counterClockwise = LilyFrogRules.tangentDirection(
        theta: 0,
        clockwise: false,
      );
      final clockwise = LilyFrogRules.tangentDirection(
        theta: 0,
        clockwise: true,
      );

      expect(counterClockwise.x, closeTo(0, 1e-9));
      expect(counterClockwise.y, closeTo(1, 1e-9));
      expect(clockwise.x, closeTo(0, 1e-9));
      expect(clockwise.y, closeTo(-1, 1e-9));
    });

    test('선분과 원의 첫 충돌을 큰 프레임 이동에서도 찾는다', () {
      final hit = LilyFrogRules.firstSegmentCircleHit(
        start: const Point(0, 0),
        end: const Point(100, 0),
        center: const Point(60, 0),
        radius: 10,
      );

      expect(hit, closeTo(0.5, 1e-9));
    });

    test('연잎 외곽보다 10px 밖에 걸쳐도 착지로 인정한다', () {
      final hit = LilyFrogRules.firstSegmentCircleHit(
        start: const Point(0, 0),
        end: const Point(100, 0),
        center: const Point(50, 89),
        radius: 90,
      );

      const pad = LilyPadSpec(
        id: 1,
        center: Point(0, 0),
        diameter: 160,
        clockwise: false,
        angularSpeed: 1,
        variant: 0,
        risky: false,
        progressIndex: 0,
      );
      expect(hit, isNotNull);
      expect(pad.landingRadius, 90);
      expect(pad.orbitRadius, 80);
      expect(
        LilyFrogRules.firstSegmentCircleHit(
          start: const Point(0, 91),
          end: const Point(100, 91),
          center: pad.center,
          radius: pad.landingRadius,
        ),
        isNull,
      );
    });

    test('일반 새 연잎은 콤보에 따라 300점에 10점씩 더한다', () {
      expect(
        LilyFrogRules.landingScore(risky: false, caughtFly: false, combo: 1),
        310,
      );
      expect(
        LilyFrogRules.landingScore(risky: false, caughtFly: false, combo: 10),
        400,
      );
      expect(LilyFrogRules.formatScore(12345), '12,345점');
      expect(LilyFrogRules.formatHudScore(12345), '12,345');
    });

    test('황금 연잎은 1000점에 콤보를 더하고 파리는 한 마리당 100점이다', () {
      expect(
        LilyFrogRules.landingScore(
          risky: false,
          caughtFly: false,
          golden: true,
          combo: 1,
        ),
        1010,
      );
      expect(
        LilyFrogRules.landingScore(
          risky: false,
          caughtFly: false,
          golden: true,
          combo: 10,
        ),
        1100,
      );
      expect(LilyFrogRules.flyScore, 100);
      expect(
        LilyFrogRules.landingScore(risky: false, caughtFly: true, combo: 1),
        410,
      );
    });

    test('20초 기준 속도를 선형 보간해 140초에 2.80 상한에 도달한다', () {
      const milestones = <(double, double)>[
        (0, 1.35),
        (20, 1.70),
        (40, 2.10),
        (60, 2.30),
        (80, 2.50),
        (100, 2.60),
        (120, 2.70),
        (140, 2.80),
      ];
      for (final entry in milestones) {
        expect(
          LilyFrogRules.difficultyAt(entry.$1).angularSpeed,
          closeTo(entry.$2, 1e-9),
          reason: '${entry.$1}초',
        );
      }
      expect(LilyFrogRules.angularSpeedAt(-10), 1.35);
      expect(LilyFrogRules.angularSpeedAt(10), closeTo(1.525, 1e-9));
      expect(LilyFrogRules.angularSpeedAt(30), closeTo(1.90, 1e-9));
      expect(LilyFrogRules.angularSpeedAt(999), 2.80);
      var previous = LilyFrogRules.angularSpeedAt(0);
      for (var second = 1; second <= 140; second++) {
        final current = LilyFrogRules.angularSpeedAt(second.toDouble());
        expect(current, greaterThan(previous));
        previous = current;
      }
      expect(LilyFrogRules.angularSpeedAt(150), 2.80);
      expect(LilyFrogRules.gameDuration, const Duration(seconds: 150));
      expect(2 * pi / LilyFrogRules.angularSpeedAt(0), closeTo(4.654, 0.001));
      expect(2 * pi / LilyFrogRules.angularSpeedAt(140), closeTo(2.244, 0.001));
    });

    test('속도 가속은 연잎 크기·간격·위험 등장 일정을 바꾸지 않는다', () {
      final atThirty = LilyFrogRules.difficultyAt(30);
      expect(atThirty.minimumDiameter, 176);
      expect(atThirty.maximumDiameter, 208);
      expect(atThirty.minimumGap, 202);
      expect(atThirty.maximumGap, 228);
      expect(atThirty.riskyChance, 0.32);

      final atFifty = LilyFrogRules.difficultyAt(50);
      expect(atFifty.minimumDiameter, 176);
      expect(atFifty.maximumDiameter, 192);
      expect(atFifty.minimumGap, 196);
      expect(atFifty.maximumGap, 224);
      expect(atFifty.riskyChance, 0.48);

      final atNinety = LilyFrogRules.difficultyAt(90);
      expect(atNinety.minimumDiameter, 160);
      expect(atNinety.maximumDiameter, 176);
      expect(atNinety.minimumGap, 194);
      expect(atNinety.maximumGap, 222);
      expect(atNinety.riskyChance, 0.62);

      final atOneTen = LilyFrogRules.difficultyAt(110);
      expect(atOneTen.minimumDiameter, 160);
      expect(atOneTen.maximumDiameter, 176);
      expect(atOneTen.minimumGap, 196);
      expect(atOneTen.maximumGap, 224);
      expect(atOneTen.riskyChance, 0.72);
    });

    test('착지 입력 잠금은 없고 다음 점프까지 빠른 회전 방향을 고른다', () {
      expect(LilyFrogRules.landingLockSeconds, 0);

      const fromCenter = Point<double>(180, 480);
      const landingPoint = Point<double>(180, 376);
      const targetCenter = Point<double>(236, 236);
      final counterClockwiseWait = LilyFrogRules.nextLaunchWaitSeconds(
        fromCenter: fromCenter,
        orbitRadius: 104,
        landingPoint: landingPoint,
        clockwise: false,
        angularSpeed: 1.35,
        targetCenter: targetCenter,
        targetLandingRadius: 106,
      );
      final clockwiseWait = LilyFrogRules.nextLaunchWaitSeconds(
        fromCenter: fromCenter,
        orbitRadius: 104,
        landingPoint: landingPoint,
        clockwise: true,
        angularSpeed: 1.35,
        targetCenter: targetCenter,
        targetLandingRadius: 106,
      );

      expect(counterClockwiseWait, isNotNull);
      expect(clockwiseWait, isNotNull);
      final clockwise = LilyFrogRules.optimalClockwiseForNextJump(
        fromCenter: fromCenter,
        orbitRadius: 104,
        landingPoint: landingPoint,
        angularSpeed: 1.35,
        targetCenter: targetCenter,
        targetLandingRadius: 106,
        fallbackClockwise: false,
      );
      final selectedWait = clockwise ? clockwiseWait : counterClockwiseWait;
      final otherWait = clockwise ? counterClockwiseWait : clockwiseWait;
      expect(selectedWait, lessThanOrEqualTo(otherWait! + 0.01));
    });

    test('생성 시 예상 착지점을 기록하고 출발 연잎의 방향을 미리 결정한다', () {
      const from = LilyPadSpec(
        id: 0,
        center: Point(180, 480),
        diameter: 208,
        clockwise: false,
        angularSpeed: 1.35,
        variant: 0,
        risky: false,
        progressIndex: 0,
      );
      final generation = LilyFieldGenerator(Random(8124)).generate(
        from: from,
        nextPadId: 1,
        nextFlyId: 1,
        elapsedSeconds: 40,
        existing: [from],
      );
      final expectedDirection = LilyFrogRules.optimalClockwiseForNextJump(
        fromCenter: from.center,
        orbitRadius: from.orbitRadius,
        landingPoint: LilyFrogRules.orbitPosition(
          center: from.center,
          radius: from.orbitRadius,
          theta: -pi / 2,
        ),
        angularSpeed: LilyFrogRules.difficultyAt(40).angularSpeed,
        targetCenter: generation.safe.center,
        targetLandingRadius: generation.safe.landingRadius,
        fallbackClockwise: from.clockwise,
      );

      expect(generation.preparedFromClockwise, expectedDirection);
      expect(generation.safe.expectedLandingPoint, isNotNull);
    });
  });

  group('LilyFieldGenerator', () {
    LilyPadSpec startPad() => const LilyPadSpec(
      id: 0,
      center: Point(180, 480),
      diameter: 208,
      clockwise: false,
      angularSpeed: 1.35,
      variant: 0,
      risky: false,
      progressIndex: 0,
    );

    LilyPadSpec padAtProgress(int progressIndex) => LilyPadSpec(
      id: progressIndex,
      center: const Point(180, 480),
      diameter: 208,
      clockwise: false,
      angularSpeed: 1.35,
      variant: 0,
      risky: false,
      progressIndex: progressIndex,
    );

    test('같은 시드는 같은 연잎 묶음을 만든다', () {
      LilyGeneration generate(int seed) =>
          LilyFieldGenerator(Random(seed)).generate(
            from: startPad(),
            nextPadId: 1,
            nextFlyId: 1,
            elapsedSeconds: 70,
            existing: [startPad()],
          );

      final first = generate(8123);
      final second = generate(8123);

      expect(first.safe.center, second.safe.center);
      expect(first.safe.diameter, second.safe.diameter);
      expect(first.safe.clockwise, second.safe.clockwise);
      expect(first.risky?.center, second.risky?.center);
      expect(first.fly?.center, second.fly?.center);
      expect(
        first.flies.map((fly) => fly.center),
        second.flies.map((fly) => fly.center),
      );
    });

    test('안전 연잎은 가능한 경우 옆으로 60px 이상 이동한다', () {
      for (var seed = 0; seed < 12; seed++) {
        final from = startPad();
        final generation = LilyFieldGenerator(Random(seed)).generate(
          from: from,
          nextPadId: 1,
          nextFlyId: 1,
          elapsedSeconds: 30,
          existing: [from],
        );
        expect(
          (generation.safe.center.x - from.center.x).abs(),
          greaterThanOrEqualTo(60),
          reason: 'seed=$seed',
        );
      }
    });

    test('모든 시간 구간과 여러 시드가 최소 하나의 안전 경로를 만든다', () {
      for (final elapsed in [0.0, 30.0, 60.0, 100.0, 140.0, 145.0, 149.9]) {
        for (var seed = 0; seed < 50; seed++) {
          final from = startPad();
          final generator = LilyFieldGenerator(Random(seed));
          final generation = generator.generate(
            from: from,
            nextPadId: 1,
            nextFlyId: 1,
            elapsedSeconds: elapsed,
            existing: [from],
          );

          expect(
            generator.reachableWindowSeconds(
              from: from,
              target: generation.safe,
            ),
            greaterThanOrEqualTo(LilyFrogRules.minimumSafeWindowSeconds - 0.01),
            reason: 'elapsed=$elapsed seed=$seed',
          );
          expect(generation.safe.risky, isFalse);
        }
      }
    });

    test('가속 상한인 140초 이후에도 실제 각속도로 안전 경로를 만든다', () {
      for (final elapsed in [140.0, 145.0, 149.9]) {
        for (var seed = 0; seed < 20; seed++) {
          final from = startPad().copyWith(
            angularSpeed: LilyFrogRules.difficultyAt(elapsed).angularSpeed,
          );
          final generator = LilyFieldGenerator(Random(seed));
          final generation = generator.generate(
            from: from,
            nextPadId: 1,
            nextFlyId: 1,
            elapsedSeconds: elapsed,
            existing: [from],
          );

          expect(
            generator.reachableWindowSeconds(
              from: from,
              target: generation.safe,
            ),
            greaterThanOrEqualTo(LilyFrogRules.minimumSafeWindowSeconds - 0.01),
            reason: 'elapsed=$elapsed seed=$seed',
          );
        }
      }
    });

    test('다섯 번째마다 104px 황금 연잎이 안전 연잎과 함께 생성된다', () {
      final from = padAtProgress(4);
      final generation = LilyFieldGenerator(Random(3)).generate(
        from: from,
        nextPadId: 10,
        nextFlyId: 1,
        elapsedSeconds: 115,
        existing: [from],
      );

      expect(generation.safe.golden, isFalse);
      expect(generation.safe.progressIndex, 5);
      expect(generation.risky, isNotNull);
      expect(generation.risky!.golden, isTrue);
      expect(generation.risky!.diameter, LilyFrogRules.goldenLilyDiameter);
      expect(generation.risky!.progressIndex, 5);
      expect(generation.risky!.id, isNot(generation.safe.id));
      expect(generation.continuation, isNotNull);
      expect(generation.continuation!.progressIndex, 6);
      expect(generation.flies, isEmpty);
    });

    test('황금 선택 구간에는 파리를 놓지 않는다', () {
      for (var seed = 0; seed < 100; seed++) {
        final from = padAtProgress(4);
        final generation = LilyFieldGenerator(Random(seed)).generate(
          from: from,
          nextPadId: 10,
          nextFlyId: 20,
          elapsedSeconds: 115,
          existing: [from],
        );
        expect(generation.risky, isNotNull);
        expect(generation.flies, isEmpty);
      }
    });

    test('일반 구간의 약 50%에 2~3마리를 안전 연잎 경로로 놓음', () {
      var routesWithFlies = 0;
      for (var seed = 0; seed < 200; seed++) {
        final from = padAtProgress(2);
        final generation = LilyFieldGenerator(Random(seed)).generate(
          from: from,
          nextPadId: 10,
          nextFlyId: 20,
          elapsedSeconds: 40,
          existing: [from],
        );
        expect(generation.risky, isNull);
        if (generation.flies.isEmpty) continue;
        routesWithFlies++;
        expect(generation.flies.length, inInclusiveRange(2, 3));
        expect(
          generation.flies.every((fly) => fly.padId == generation.safe.id),
          isTrue,
        );
        expect(
          generation.flies.every((fly) {
            final dx = fly.center.x - generation.safe.center.x;
            final dy = fly.center.y - generation.safe.center.y;
            return sqrt(dx * dx + dy * dy) > generation.safe.landingRadius;
          }),
          isTrue,
          reason: '파리는 실제 첫 착지점보다 앞의 물 위에 있어야 한다: seed=$seed',
        );
      }
      expect(routesWithFlies, inInclusiveRange(75, 125));
    });

    test('파리는 현재 회전 방향의 첫 착지 가능한 점프 창에서 먹힌다', () {
      var checked = 0;
      for (var seed = 0; seed < 200; seed++) {
        final source = padAtProgress(2);
        final generation = LilyFieldGenerator(Random(seed)).generate(
          from: source,
          nextPadId: 10,
          nextFlyId: 20,
          elapsedSeconds: 40,
          existing: [source],
        );
        if (generation.flies.isEmpty) continue;
        checked++;
        final from = source.copyWith(
          clockwise: generation.preparedFromClockwise,
        );
        final landing =
            from.expectedLandingPoint ??
            Point<double>(from.center.x, from.center.y - from.orbitRadius);
        final startTheta = atan2(
          landing.y - from.center.y,
          landing.x - from.center.x,
        );
        var enteredFirstWindow = false;
        var catchesFlies = false;
        for (var index = 0; index <= 720; index++) {
          final theta =
              startTheta + (from.clockwise ? -1 : 1) * 2 * pi * index / 720;
          final hitsTarget = LilyFrogRules.tangentLaunchHits(
            fromCenter: from.center,
            orbitRadius: from.orbitRadius,
            clockwise: from.clockwise,
            theta: theta,
            targetCenter: generation.safe.center,
            targetLandingRadius: generation.safe.landingRadius,
          );
          if (!hitsTarget) {
            if (enteredFirstWindow) break;
            continue;
          }
          enteredFirstWindow = true;
          final start = LilyFrogRules.orbitPosition(
            center: from.center,
            radius: from.orbitRadius,
            theta: theta,
          );
          final direction = LilyFrogRules.tangentDirection(
            theta: theta,
            clockwise: from.clockwise,
          );
          final end = Point<double>(
            start.x +
                direction.x *
                    LilyFrogRules.launchSpeed *
                    LilyFrogRules.maximumFlightSeconds,
            start.y +
                direction.y *
                    LilyFrogRules.launchSpeed *
                    LilyFrogRules.maximumFlightSeconds,
          );
          final landingT = LilyFrogRules.firstSegmentCircleHit(
            start: start,
            end: end,
            center: generation.safe.center,
            radius: generation.safe.landingRadius,
            minimumT: 0.04,
          );
          if (landingT == null) continue;
          final landingEnd = Point<double>(
            start.x + (end.x - start.x) * landingT,
            start.y + (end.y - start.y) * landingT,
          );
          if (generation.flies.every(
            (fly) =>
                LilyFrogRules.firstSegmentCircleHit(
                  start: start,
                  end: landingEnd,
                  center: fly.center,
                  radius: LilyFrogRules.flyPickupRadius,
                ) !=
                null,
          )) {
            catchesFlies = true;
            break;
          }
        }
        expect(
          catchesFlies,
          isTrue,
          reason: 'seed=$seed clockwise=${from.clockwise}',
        );
      }
      expect(checked, greaterThan(50));
    });

    test('황금 분기는 다섯 번째가 아닌 진행도에는 생성되지 않는다', () {
      for (final progress in [0, 1, 2, 3, 5, 6, 7, 8]) {
        final from = padAtProgress(progress);
        final generation = LilyFieldGenerator(Random(progress)).generate(
          from: from,
          nextPadId: 10,
          nextFlyId: 20,
          elapsedSeconds: 115,
          existing: [from],
        );
        expect(generation.risky, isNull, reason: 'progress=$progress');
        expect(
          generation.flies.every((fly) => fly.padId == generation.safe.id),
          isTrue,
          reason: 'progress=$progress',
        );
      }
    });

    test('연속 생성된 모든 연잎은 외곽 사이에 최소 물 간격을 둔다', () {
      for (var seed = 0; seed < 120; seed++) {
        final generator = LilyFieldGenerator(Random(seed));
        final pads = <LilyPadSpec>[startPad()];
        var cursor = pads.single;
        var nextPadId = 1;
        for (var step = 0; step < 10; step++) {
          final generation = generator.generate(
            from: cursor,
            nextPadId: nextPadId,
            nextFlyId: step + 1,
            elapsedSeconds: step * 12,
            existing: pads,
          );
          for (final candidate in generation.pads) {
            for (final existing in pads) {
              final dx = candidate.center.x - existing.center.x;
              final dy = candidate.center.y - existing.center.y;
              final centerDistance = sqrt(dx * dx + dy * dy);
              final required =
                  (candidate.diameter + existing.diameter) / 2 +
                  LilyFrogRules.minimumPadEdgeGap;
              expect(
                centerDistance,
                greaterThanOrEqualTo(required - 1e-9),
                reason:
                    'seed=$seed step=$step candidate=${candidate.id} '
                    'existing=${existing.id}',
              );
            }
            pads.add(candidate);
          }
          cursor = generation.continuation ?? generation.safe;
          nextPadId += generation.continuation != null
              ? 3
              : generation.risky == null
              ? 1
              : 2;
        }
      }
    });
  });
}

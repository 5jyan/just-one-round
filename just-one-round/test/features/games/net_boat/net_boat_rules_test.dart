import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/net_boat/domain/net_boat_rules.dart';

void main() {
  group('NetBoatRules', () {
    test('탭할 때마다 방향이 시계 방향으로 한 칸 돈다', () {
      var direction = NetBoatDirection.north;
      direction = NetBoatRules.turnRight(direction);
      expect(direction, NetBoatDirection.east);
      direction = NetBoatRules.turnRight(direction);
      expect(direction, NetBoatDirection.south);
      direction = NetBoatRules.turnRight(direction);
      expect(direction, NetBoatDirection.west);
      direction = NetBoatRules.turnRight(direction);
      expect(direction, NetBoatDirection.north);
    });

    test('쿨다운 중 입력은 하나만 버퍼링한다', () {
      final buffer = NetBoatTurnBuffer();
      expect(buffer.request(), isTrue);
      expect(buffer.request(), isFalse);
      expect(buffer.request(), isFalse);
      expect(buffer.hasBufferedTurn, isTrue);
      expect(buffer.update(0.11), isFalse);
      expect(buffer.update(0.01), isTrue);
      expect(buffer.hasBufferedTurn, isFalse);
    });

    test('직교 자기 교차에서 최근 단순 폐곡선을 추출한다', () {
      final loop = NetBoatRules.latestLoop(const [
        Point(100, 100),
        Point(200, 100),
        Point(200, 200),
        Point(100, 200),
        Point(100, 50),
      ]);

      expect(loop, isNotNull);
      expect(loop!.intersection, const Point<double>(100, 100));
      expect(loop.polygon, const [
        Point<double>(100, 100),
        Point<double>(200, 100),
        Point<double>(200, 200),
        Point<double>(100, 200),
        Point<double>(100, 100),
      ]);
      expect(NetBoatRules.polygonArea(loop.polygon).abs(), 10000);
    });

    test('보이는 그물 폭과 2px 여유 안쪽의 틈은 맞닿은 폐곡선으로 판정한다', () {
      final loop = NetBoatRules.latestLoop(const [
        Point<double>(100, 100),
        Point<double>(200, 100),
        Point<double>(200, 200),
        Point<double>(108, 200),
        Point<double>(108, 116),
      ]);

      expect(NetBoatRules.netClosureTolerance, 16);
      expect(loop, isNotNull);
      expect(loop!.intersection, const Point<double>(108, 100));
      expect(loop.polygon, const [
        Point<double>(108, 100),
        Point<double>(200, 100),
        Point<double>(200, 200),
        Point<double>(108, 200),
        Point<double>(108, 100),
      ]);
    });

    test('그물 외곽 폭과 여유를 0.01px 넘긴 틈은 열린 경로로 유지한다', () {
      final loop = NetBoatRules.latestLoop(const [
        Point<double>(100, 100),
        Point<double>(200, 100),
        Point<double>(200, 200),
        Point<double>(108, 200),
        Point<double>(108, 116.01),
      ]);

      expect(loop, isNull);
    });

    test('복수 교차 후보에서는 더 최근 선분으로 닫힌 고리를 고른다', () {
      final loop = NetBoatRules.latestLoop(const [
        Point(40, 40),
        Point(160, 40),
        Point(160, 160),
        Point(80, 160),
        Point(80, 80),
        Point(200, 80),
        Point(200, 200),
        Point(40, 200),
        Point(40, 20),
      ]);

      expect(loop, isNotNull);
      expect(loop!.intersection, const Point<double>(40, 40));
    });

    test('경계 위 물고기도 포획하고 바깥 물고기는 제외한다', () {
      const polygon = [
        Point<double>(0, 0),
        Point<double>(100, 0),
        Point<double>(100, 100),
        Point<double>(0, 100),
        Point<double>(0, 0),
      ];
      expect(
        NetBoatRules.pointInPolygonInclusive(const Point(50, 50), polygon),
        isTrue,
      );
      expect(
        NetBoatRules.pointInPolygonInclusive(const Point(100, 50), polygon),
        isTrue,
      );
      expect(
        NetBoatRules.pointInPolygonInclusive(const Point(101, 50), polygon),
        isFalse,
      );
    });

    test('상어 중심과 그물 꼭짓점 사이 거리도 정확히 잰다', () {
      const net = [
        Point<double>(20, 20),
        Point<double>(100, 20),
        Point<double>(100, 100),
      ];
      expect(
        NetBoatRules.distanceToPolyline(const Point(104, 24), net),
        closeTo(4, 1e-9),
      );
    });

    test('피라냐 실루엣과 그물 바깥선이 1픽셀도 없이 맞닿으면 접촉한다', () {
      const net = [Point<double>(100, 0), Point<double>(100, 200)];

      expect(NetBoatRules.netVisualHalfWidth, 7);
      expect(
        NetBoatRules.movingCreatureTouchesNet(
          previousCreature: const Point<double>(80.5, 100),
          creature: const Point<double>(80.5, 100),
          direction: const Point<double>(1, 0),
          kind: NetBoatCreatureKind.piranha,
          net: net,
        ),
        isTrue,
      );
      expect(
        NetBoatRules.movingCreatureTouchesNet(
          previousCreature: const Point<double>(80.49, 100),
          creature: const Point<double>(80.49, 100),
          direction: const Point<double>(1, 0),
          kind: NetBoatCreatureKind.piranha,
          net: net,
        ),
        isFalse,
      );
    });

    test('빠른 물고기의 이동 전후가 그물을 건너면 중간 경로에서 접촉한다', () {
      expect(
        NetBoatRules.movingCreatureTouchesNet(
          previousCreature: const Point<double>(50, 100),
          creature: const Point<double>(150, 100),
          direction: const Point<double>(1, 0),
          kind: NetBoatCreatureKind.marlin,
          net: const [Point<double>(100, 0), Point<double>(100, 200)],
        ),
        isTrue,
      );
    });

    test('그물에 닿은 물고기는 들어온 쪽에 남고 속도가 반사된다', () {
      final bounce = NetBoatRules.bounceCreatureOffNet(
        previousCreature: const Point<double>(80, 100),
        creature: const Point<double>(120, 100),
        velocity: const Point<double>(40, 0),
        kind: NetBoatCreatureKind.piranha,
        net: const [Point<double>(100, 0), Point<double>(100, 200)],
      );

      expect(bounce, isNotNull);
      expect(bounce!.position.x, lessThan(100));
      expect(bounce.velocity.x, -40);
      expect(bounce.velocity.y, 0);
    });

    test('고래는 열린 그물을 통과하고 반사되지 않는다', () {
      const net = [Point<double>(100, 0), Point<double>(100, 200)];

      expect(
        NetBoatRules.movingCreatureTouchesNet(
          previousCreature: const Point<double>(80, 100),
          creature: const Point<double>(120, 100),
          direction: const Point<double>(40, 0),
          kind: NetBoatCreatureKind.whale,
          net: net,
        ),
        isFalse,
      );
      expect(
        NetBoatRules.bounceCreatureOffNet(
          previousCreature: const Point<double>(80, 100),
          creature: const Point<double>(120, 100),
          velocity: const Point<double>(40, 0),
          kind: NetBoatCreatureKind.whale,
          net: net,
        ),
        isNull,
      );
    });

    test('그물 길이는 꺾인 전체 경로를 합산하고 80%부터 경고한다', () {
      const path = [
        Point<double>(0, 0),
        Point<double>(600, 0),
        Point<double>(600, 200),
      ];
      final length = NetBoatRules.netLength(path);

      expect(length, 800);
      expect(NetBoatRules.netUsageRatio(length), 0.8);
      expect(NetBoatRules.netWarningMessage, '그물 길이 800부터 끊길 위험이 있어요!');
      expect(NetBoatRules.isNetWarning(799.9), isFalse);
      expect(NetBoatRules.isNetWarning(length), isTrue);
      expect(NetBoatRules.isNetAtLimit(999.9), isFalse);
      expect(NetBoatRules.isNetAtLimit(1000), isTrue);
      expect(NetBoatRules.netUsageRatio(1200), 1);
    });

    test('정어리를 제외한 생물 수로 동시 포획 보너스를 계산한다', () {
      expect(NetBoatRules.captureScore(const []), 0);
      expect(
        NetBoatRules.captureScore(const [NetBoatCreatureKind.sardine]),
        10,
      );
      expect(
        NetBoatRules.captureScore(const [
          NetBoatCreatureKind.sardine,
          NetBoatCreatureKind.sardine,
          NetBoatCreatureKind.sardine,
        ]),
        30,
      );
      expect(
        NetBoatRules.captureScore(const [NetBoatCreatureKind.piranha]),
        100,
      );
      expect(
        NetBoatRules.captureScore(const [
          NetBoatCreatureKind.sardine,
          NetBoatCreatureKind.sardine,
          NetBoatCreatureKind.piranha,
        ]),
        120,
      );
      expect(
        NetBoatRules.captureScore(const [
          NetBoatCreatureKind.sardine,
          NetBoatCreatureKind.sardine,
          NetBoatCreatureKind.piranha,
          NetBoatCreatureKind.marlin,
        ]),
        620,
      );
      expect(
        NetBoatRules.captureScore(const [
          NetBoatCreatureKind.piranha,
          NetBoatCreatureKind.marlin,
        ]),
        600,
      );
      expect(
        NetBoatRules.captureScore(const [
          NetBoatCreatureKind.piranha,
          NetBoatCreatureKind.marlin,
          NetBoatCreatureKind.shark,
          NetBoatCreatureKind.whale,
        ]),
        4200,
      );
      expect(NetBoatRules.formatScore(12300), '12,300점');
      expect(
        NetBoatRules.capturePopupLabel(NetBoatCreatureKind.sardine),
        '+10',
      );
      expect(
        NetBoatRules.capturePopupLabel(NetBoatCreatureKind.piranha),
        '+100',
      );
      expect(
        NetBoatRules.capturePopupLabel(NetBoatCreatureKind.marlin),
        '+300',
      );
      expect(NetBoatRules.capturePopupLabel(NetBoatCreatureKind.shark), '+700');
      expect(
        NetBoatRules.capturePopupLabel(NetBoatCreatureKind.whale),
        '+2,500',
      );
    });

    test('원본 스프라이트는 피라냐만 좌향, 나머지는 우향이다', () {
      expect(
        NetBoatRules.nativeSpriteFacesRight(NetBoatCreatureKind.piranha),
        isFalse,
      );
      for (final kind in const [
        NetBoatCreatureKind.sardine,
        NetBoatCreatureKind.marlin,
        NetBoatCreatureKind.shark,
        NetBoatCreatureKind.whale,
      ]) {
        expect(NetBoatRules.nativeSpriteFacesRight(kind), isTrue);
      }
    });

    test('실제 이동축 렌더에서는 좌향 원본 피라냐만 수평 반전한다', () {
      expect(
        NetBoatRules.spriteNeedsHorizontalFlipForVelocity(
          NetBoatCreatureKind.piranha,
        ),
        isTrue,
      );
      for (final kind in const [
        NetBoatCreatureKind.sardine,
        NetBoatCreatureKind.marlin,
        NetBoatCreatureKind.shark,
        NetBoatCreatureKind.whale,
      ]) {
        expect(
          NetBoatRules.spriteNeedsHorizontalFlipForVelocity(kind),
          isFalse,
        );
      }
    });

    test('모든 생물은 8방향에서 진행축을 향하며 배가 위로 뒤집히지 않는다', () {
      const velocities = <Point<double>>[
        Point(1, 0),
        Point(1, 1),
        Point(0, 1),
        Point(-1, 1),
        Point(-1, 0),
        Point(-1, -1),
        Point(0, -1),
        Point(1, -1),
      ];
      for (final kind in NetBoatCreatureKind.values) {
        for (final velocity in velocities) {
          final transform = NetBoatRules.spriteTransformForVelocity(
            kind,
            velocity,
          );
          final nativeForwardX = NetBoatRules.nativeSpriteFacesRight(kind)
              ? 1.0
              : -1.0;
          final localForwardX = transform.flipHorizontally
              ? -nativeForwardX
              : nativeForwardX;
          final renderedForward = Point<double>(
            cos(transform.rotation) * localForwardX,
            sin(transform.rotation) * localForwardX,
          );
          final speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y);
          expect(
            renderedForward.x,
            closeTo(velocity.x / speed, 1e-9),
            reason: '$kind $velocity x축',
          );
          expect(
            renderedForward.y,
            closeTo(velocity.y / speed, 1e-9),
            reason: '$kind $velocity y축',
          );
          final renderedBellyY = cos(transform.rotation);
          expect(
            renderedBellyY,
            greaterThanOrEqualTo(-1e-9),
            reason: '$kind $velocity 배가 화면 위로 뒤집히면 안 됨',
          );
        }
      }
    });

    test('30·60·90·150초에 속도와 생물 구성이 바뀌고 5분까지 상한을 유지한다', () {
      void expectRoster(
        double seconds,
        int sardine,
        int piranha,
        int marlin,
        int shark,
        int whale,
      ) {
        final roster = NetBoatRules.difficultyAt(seconds).roster;
        expect(
          (
            roster.sardine,
            roster.piranha,
            roster.marlin,
            roster.shark,
            roster.whale,
          ),
          (sardine, piranha, marlin, shark, whale),
          reason: '$seconds초 로스터',
        );
      }

      expect(NetBoatRules.difficultyAt(0).boatSpeed, 91.2);
      expectRoster(0, 15, 3, 1, 0, 0);
      expectRoster(29.999, 15, 3, 1, 0, 0);
      expect(NetBoatRules.difficultyAt(30).boatSpeed, 100.8);
      expectRoster(30, 20, 4, 2, 0, 0);
      expectRoster(59.999, 20, 4, 2, 0, 0);
      expectRoster(60, 25, 5, 2, 1, 1);
      expectRoster(89.999, 25, 5, 2, 1, 1);
      expect(NetBoatRules.difficultyAt(90).boatSpeed, 110.4);
      expectRoster(90, 30, 6, 3, 2, 1);
      expectRoster(119.999, 30, 6, 3, 2, 1);
      expectRoster(120, 35, 6, 3, 2, 1);
      expectRoster(149.999, 35, 6, 3, 2, 1);
      expect(NetBoatRules.difficultyAt(150).boatSpeed, 120);
      expectRoster(150, 40, 7, 3, 3, 1);
      expectRoster(NetBoatRules.difficultyCapSeconds, 40, 7, 3, 3, 1);
      expectRoster(
        NetBoatRules.gameDuration.inSeconds.toDouble(),
        40,
        7,
        3,
        3,
        1,
      );
      expectRoster(999, 40, 7, 3, 3, 1);
      expect(NetBoatRules.difficultyAt(300).boatSpeed, 120);
      expect(NetBoatRules.rulesVersion, 3);
      expect(NetBoatRules.gameDuration, const Duration(seconds: 300));
    });

    test('고래는 60초 간격으로 240초까지 고정 출현을 예약한다', () {
      expect(NetBoatRules.whaleSpawnSeconds, [60, 120, 180, 240]);
      expect(NetBoatRules.whaleWarningSeconds, 2);
    });

    test('생물별 이동 속도 범위를 유지한다', () {
      final sardine = NetBoatRules.specFor(NetBoatCreatureKind.sardine);
      final piranha = NetBoatRules.specFor(NetBoatCreatureKind.piranha);
      final marlin = NetBoatRules.specFor(NetBoatCreatureKind.marlin);
      final shark = NetBoatRules.specFor(NetBoatCreatureKind.shark);
      final whale = NetBoatRules.specFor(NetBoatCreatureKind.whale);

      expect((sardine.minimumSpeed, sardine.maximumSpeed), (18, 24));
      expect((piranha.minimumSpeed, piranha.maximumSpeed), (24, 30));
      expect((marlin.minimumSpeed, marlin.maximumSpeed), (30, 40));
      expect((shark.minimumSpeed, shark.maximumSpeed), (40, 50));
      expect((whale.minimumSpeed, whale.maximumSpeed), (15, 15));
      expect(sardine.respawnSeconds, 1);
      expect(piranha.respawnSeconds, 5);
      expect(marlin.respawnSeconds, 10);
      expect(shark.respawnSeconds, 20);
    });

    test('고래는 기존 크기에서 10퍼센트를 추가로 줄인다', () {
      final whale = NetBoatRules.specFor(NetBoatCreatureKind.whale);

      expect(whale.renderWidth, closeTo(129.6, 1e-9));
      expect(whale.renderHeight, closeTo(85.86, 1e-9));
      expect(whale.collisionHalfLength, closeTo(46.98, 1e-9));
      expect(whale.collisionHalfWidth, closeTo(19.44, 1e-9));
      expect(whale.netContactHalfLength, closeTo(59.94, 1e-9));
      expect(whale.netContactHalfWidth, closeTo(29.16, 1e-9));
    });

    test('정어리는 피라냐보다 작고 배와 닿아도 치명적이지 않다', () {
      final sardine = NetBoatRules.specFor(NetBoatCreatureKind.sardine);
      final piranha = NetBoatRules.specFor(NetBoatCreatureKind.piranha);

      expect(sardine.points, 10);
      expect(sardine.renderWidth, 28);
      expect(sardine.renderHeight, 28);
      expect(sardine.renderWidth, lessThanOrEqualTo(piranha.renderWidth));
      expect(sardine.renderHeight, lessThanOrEqualTo(piranha.renderHeight));
      expect(
        NetBoatRules.isLethalOnBoatContact(NetBoatCreatureKind.sardine),
        isFalse,
      );
      for (final kind in NetBoatCreatureKind.values.where(
        (kind) => kind != NetBoatCreatureKind.sardine,
      )) {
        expect(NetBoatRules.isLethalOnBoatContact(kind), isTrue);
      }
    });

    test('상어 충돌 범위는 보이는 등지느러미 크기만 사용한다', () {
      final shark = NetBoatRules.specFor(NetBoatCreatureKind.shark);

      expect(shark.collisionHalfLength, 10.5);
      expect(shark.collisionHalfWidth, 7);
      expect(
        NetBoatRules.boatHitsCreature(
          boat: const Point(25.5, 0),
          boatDirection: const Point(1, 0),
          creature: const Point(0, 0),
          direction: const Point(1, 0),
          kind: NetBoatCreatureKind.shark,
        ),
        isTrue,
      );
      expect(
        NetBoatRules.boatHitsCreature(
          boat: const Point(26.5, 0),
          boatDirection: const Point(1, 0),
          creature: const Point(0, 0),
          direction: const Point(1, 0),
          kind: NetBoatCreatureKind.shark,
        ),
        isFalse,
      );
    });

    test('시작점에서 첫 외곽 충돌까지 3초보다 오래 걸린다', () {
      final distanceToTop =
          NetBoatRules.startY -
          NetBoatRules.boatWallCollisionHalfLength -
          NetBoatRules.playTop;
      expect(distanceToTop / 91.2, greaterThan(3));
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(NetBoatRules.startX, NetBoatRules.startY),
          direction: NetBoatDirection.north,
        ),
        isTrue,
      );
    });

    test('벽 전용 선체 코어가 네 방향 돌 벽을 실제로 넘을 때만 실패한다', () {
      expect(NetBoatRules.horizontalWallForgiveness, 8);
      expect(NetBoatRules.verticalWallForgiveness, 11);

      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            NetBoatRules.playLeft -
                NetBoatRules.horizontalWallForgiveness +
                NetBoatRules.boatWallCollisionHalfWidth,
            300,
          ),
          direction: NetBoatDirection.north,
        ),
        isTrue,
      );
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            NetBoatRules.playLeft -
                NetBoatRules.horizontalWallForgiveness +
                NetBoatRules.boatWallCollisionHalfWidth -
                0.1,
            300,
          ),
          direction: NetBoatDirection.north,
        ),
        isFalse,
      );
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            NetBoatRules.playLeft -
                NetBoatRules.horizontalWallForgiveness +
                NetBoatRules.boatWallCollisionHalfLength,
            300,
          ),
          direction: NetBoatDirection.east,
        ),
        isTrue,
      );
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            NetBoatRules.playLeft -
                NetBoatRules.horizontalWallForgiveness +
                NetBoatRules.boatWallCollisionHalfLength -
                0.1,
            300,
          ),
          direction: NetBoatDirection.east,
        ),
        isFalse,
      );
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            NetBoatRules.playRight +
                NetBoatRules.horizontalWallForgiveness -
                NetBoatRules.boatWallCollisionHalfLength,
            300,
          ),
          direction: NetBoatDirection.west,
        ),
        isTrue,
      );
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            NetBoatRules.playRight +
                NetBoatRules.horizontalWallForgiveness -
                NetBoatRules.boatWallCollisionHalfLength +
                0.1,
            300,
          ),
          direction: NetBoatDirection.west,
        ),
        isFalse,
      );
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            180,
            NetBoatRules.playTop -
                NetBoatRules.verticalWallForgiveness +
                NetBoatRules.boatWallCollisionHalfLength,
          ),
          direction: NetBoatDirection.north,
        ),
        isTrue,
      );
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            180,
            NetBoatRules.playTop -
                NetBoatRules.verticalWallForgiveness +
                NetBoatRules.boatWallCollisionHalfLength -
                0.1,
          ),
          direction: NetBoatDirection.north,
        ),
        isFalse,
      );
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            180,
            NetBoatRules.playBottom +
                NetBoatRules.verticalWallForgiveness -
                NetBoatRules.boatWallCollisionHalfLength,
          ),
          direction: NetBoatDirection.south,
        ),
        isTrue,
      );
      expect(
        NetBoatRules.isBoatInsidePlayArea(
          const Point(
            180,
            NetBoatRules.playBottom +
                NetBoatRules.verticalWallForgiveness -
                NetBoatRules.boatWallCollisionHalfLength +
                0.1,
          ),
          direction: NetBoatDirection.south,
        ),
        isFalse,
      );
    });

    test('배와 생물의 캡슐 충돌은 보이는 몸체가 닿을 때만 성립한다', () {
      expect(
        NetBoatRules.boatHitsCreature(
          boat: const Point(36, 0),
          boatDirection: const Point(1, 0),
          creature: const Point(0, 0),
          direction: const Point(1, 0),
          kind: NetBoatCreatureKind.marlin,
        ),
        isFalse,
      );
      expect(
        NetBoatRules.boatHitsCreature(
          boat: const Point(35, 0),
          boatDirection: const Point(1, 0),
          creature: const Point(0, 0),
          direction: const Point(1, 0),
          kind: NetBoatCreatureKind.marlin,
        ),
        isTrue,
      );
      expect(
        NetBoatRules.boatHitsCreature(
          boat: const Point(0, 11.5),
          boatDirection: const Point(1, 0),
          creature: const Point(0, 0),
          direction: const Point(1, 0),
          kind: NetBoatCreatureKind.marlin,
        ),
        isFalse,
      );
      expect(
        NetBoatRules.boatHitsCreature(
          boat: const Point(0, 10.5),
          boatDirection: const Point(1, 0),
          creature: const Point(0, 0),
          direction: const Point(1, 0),
          kind: NetBoatCreatureKind.marlin,
        ),
        isTrue,
      );
    });

    test('모든 생물은 실제 장축 접점과 1픽셀 간격을 구분한다', () {
      for (final kind in NetBoatCreatureKind.values) {
        final spec = NetBoatRules.specFor(kind);
        final touchingDistance =
            NetBoatRules.boatCollisionHalfLength + spec.collisionHalfLength;
        expect(
          NetBoatRules.boatHitsCreature(
            boat: Point(touchingDistance, 0),
            boatDirection: const Point(1, 0),
            creature: const Point(0, 0),
            direction: const Point(1, 0),
            kind: kind,
          ),
          isTrue,
          reason: '$kind 장축 접점',
        );
        expect(
          NetBoatRules.boatHitsCreature(
            boat: Point(touchingDistance + 1, 0),
            boatDirection: const Point(1, 0),
            creature: const Point(0, 0),
            direction: const Point(1, 0),
            kind: kind,
          ),
          isFalse,
          reason: '$kind 장축 1픽셀 간격',
        );
      }
    });
  });
}

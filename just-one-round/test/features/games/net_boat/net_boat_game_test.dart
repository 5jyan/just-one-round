import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/net_boat/domain/net_boat_rules.dart';
import 'package:just_one_round/features/games/net_boat/net_boat_game.dart';

void main() {
  test('긴 화면도 폭 360과 최대 가시 높이 800을 유지한다', () {
    expect(
      NetBoatGame.viewportResolutionForCanvas(Vector2(360, 640)),
      Vector2(360, 640),
    );
    expect(
      NetBoatGame.viewportResolutionForCanvas(Vector2(1080, 2400)),
      Vector2(360, 800),
    );
  });

  test('중단은 결과를 제출하지 않고 반복 호출해도 안전하다', () {
    final results = <GameResult>[];
    final game = NetBoatGame(onFinished: results.add);

    game.interrupt();
    game.interrupt();

    expect(results, isEmpty);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    game.disposeController();
  });

  test('800px부터 끊김 위험 문구를 표시하고 짧은 그물에서는 물고기 수를 표시한다', () {
    final game = NetBoatGame(onFinished: (_) {});
    addTearDown(game.disposeController);

    game.setNetPathForTesting(const [
      Point<double>(-600, 110),
      Point<double>(200, 110),
    ], direction: NetBoatDirection.east);
    expect(game.currentNetLength, 800);
    expect(game.hud.value.message, NetBoatRules.netWarningMessage);

    game.setNetPathForTesting(const [
      Point<double>(180, 400),
    ], direction: NetBoatDirection.north);
    expect(game.currentNetLength, 0);
    expect(game.hud.value.message, '잡은 물고기 0마리');
  });

  test('고래는 60초 간격으로 출현하고 이미 있으면 다음 웨이브를 건너뛴다', () {
    final game = NetBoatGame(
      random: Random(20260818),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    game.setElapsedForTesting(58);
    game.updateWhaleScheduleForTesting();
    expect(game.whaleWarningRemainingForTesting, 2);
    game.updateWhaleWarningForTesting(2);
    expect(game.creatureCountForTesting(NetBoatCreatureKind.whale), 1);

    game.setElapsedForTesting(118);
    game.updateWhaleScheduleForTesting();
    expect(game.whaleWarningRemainingForTesting, isNull);
    expect(game.creatureCountForTesting(NetBoatCreatureKind.whale), 1);

    // The skipped 120-second wave must not stop later 60-second waves.
    game.setCreatureForTesting(
      NetBoatCreatureKind.sardine,
      const Point<double>(180, 200),
    );
    game.setElapsedForTesting(178);
    game.updateWhaleScheduleForTesting();
    expect(game.whaleWarningRemainingForTesting, 2);
    game.updateWhaleWarningForTesting(2);
    expect(game.creatureCountForTesting(NetBoatCreatureKind.whale), 1);

    game.setCreatureForTesting(
      NetBoatCreatureKind.sardine,
      const Point<double>(180, 200),
    );
    game.setElapsedForTesting(238);
    game.updateWhaleScheduleForTesting();
    expect(game.whaleWarningRemainingForTesting, 2);
    game.updateWhaleWarningForTesting(2);
    expect(game.creatureCountForTesting(NetBoatCreatureKind.whale), 1);
  });

  test('고래 경고 중에 이미 고래가 생겨도 출현 순간 중복하지 않는다', () {
    final game = NetBoatGame(
      random: Random(20260819),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    game.setElapsedForTesting(58);
    game.updateWhaleScheduleForTesting();
    expect(game.whaleWarningRemainingForTesting, 2);

    game.setCreatureForTesting(
      NetBoatCreatureKind.whale,
      const Point<double>(180, 200),
    );
    game.updateWhaleWarningForTesting(2);

    expect(game.whaleWarningRemainingForTesting, isNull);
    expect(game.creatureCountForTesting(NetBoatCreatureKind.whale), 1);
  });

  testWidgets('실제 에셋을 로드하고 첫 3초 동안 실패 없이 우회전한다', (tester) async {
    final results = <GameResult>[];
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260816),
      enableHaptics: false,
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();

    expect(game.creatureCountForTesting(NetBoatCreatureKind.sardine), 15);

    expect(game.tapForTesting(), isTrue);
    expect(game.directionForTesting.name, 'east');
    game.update(3);

    expect(results, isEmpty);
    expect(game.boatPositionForTesting.x, greaterThan(180));
    expect(game.hud.value.phase, MiniGamePhase.playing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('정어리가 선체와 실제로 겹쳐도 게임이 끝나지 않는다', (tester) async {
    final results = <GameResult>[];
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260820),
      enableHaptics: false,
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.setElapsedForTesting(4);
    game.setCreatureForTesting(
      NetBoatCreatureKind.sardine,
      const Point<double>(180, 399),
    );

    game.update(0.01);

    expect(results, isEmpty);
    expect(game.hud.value.phase, MiniGamePhase.playing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('물고기 이미지 끝이 열린 그물에 맞닿으면 메시지 없이 튕긴다', (tester) async {
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260822),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.setElapsedForTesting(4);
    game.setNetPathForTesting(const [
      Point<double>(140, 150),
      Point<double>(140, 250),
    ], direction: NetBoatDirection.south);
    game.setCreatureForTesting(
      NetBoatCreatureKind.piranha,
      const Point<double>(120.5, 200),
    );

    game.update(0.01);

    expect(game.hud.value.score, 0);
    expect(game.caughtFishForTesting, 0);
    expect(game.scorePopupLabelsForTesting, isEmpty);
    expect(
      game.creaturePositionForTesting(NetBoatCreatureKind.piranha)!.x,
      lessThan(140),
    );
    expect(
      game.creatureVelocityForTesting(NetBoatCreatureKind.piranha)!.x,
      lessThan(0),
    );
    expect(game.currentNetLength, greaterThan(0));
    expect(game.hud.value.message, '잡은 물고기 0마리');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('고래는 열린 그물을 통과하고 튕김 메시지를 띄우지 않는다', (tester) async {
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260825),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.setElapsedForTesting(4);
    game.setNetPathForTesting(const [
      Point<double>(140, 150),
      Point<double>(140, 250),
    ], direction: NetBoatDirection.south);
    game.setCreatureForTesting(
      NetBoatCreatureKind.whale,
      const Point<double>(130, 200),
    );
    game.setCreatureVelocityForTesting(const Point<double>(40, 0));

    game.update(0.3);

    expect(
      game.creaturePositionForTesting(NetBoatCreatureKind.whale)!.x,
      greaterThan(140),
    );
    expect(
      game.creatureVelocityForTesting(NetBoatCreatureKind.whale)!.x,
      greaterThan(0),
    );
    expect(game.hud.value.message, isNot(contains('그물에 튕겼어요')));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('피라냐는 충돌 전에는 같은 방향으로만 이동한다', (tester) async {
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260824),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.setElapsedForTesting(4);
    game.setCreatureForTesting(
      NetBoatCreatureKind.piranha,
      const Point<double>(100, 200),
      turnRemaining: 0,
    );
    game.setCreatureVelocityForTesting(const Point<double>(24, 0));

    game.update(0.01);

    expect(
      game.creatureVelocityForTesting(NetBoatCreatureKind.piranha),
      const Point<double>(24, 0),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('한 프레임에 그물을 넘는 빠른 물고기도 반대편으로 통과하지 못한다', (tester) async {
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260823),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.setElapsedForTesting(4);
    game.setNetPathForTesting(const [
      Point<double>(140, 150),
      Point<double>(140, 250),
    ], direction: NetBoatDirection.south);
    game.setCreatureForTesting(
      NetBoatCreatureKind.marlin,
      const Point<double>(80, 200),
    );
    game.setCreatureVelocityForTesting(const Point<double>(4000, 0));

    game.update(0.01);

    expect(game.hud.value.score, 0);
    expect(game.caughtFishForTesting, 0);
    expect(game.scorePopupLabelsForTesting, isEmpty);
    expect(
      game.creaturePositionForTesting(NetBoatCreatureKind.marlin)!.x,
      lessThan(140),
    );
    expect(
      game.creatureVelocityForTesting(NetBoatCreatureKind.marlin)!.x,
      lessThan(0),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('종료 순간에는 남은 시간이 항상 0초로 고정된다', (tester) async {
    final results = <GameResult>[];
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260821),
      enableHaptics: false,
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.setElapsedForTesting(299.99);
    game.setNetPathForTesting(const [
      Point<double>(180, 400),
    ], direction: NetBoatDirection.north);

    game.update(0.02);

    expect(results, hasLength(1));
    expect(game.hud.value.phase, MiniGamePhase.finished);
    expect(game.hud.value.remainingSeconds, 0);
    expect(results.single.collisions, 0);
    expect(results.single.duration, const Duration(seconds: 300));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('1000px 그물은 배를 죽이지 않고 끊긴 뒤 1초 후 다시 전개된다', (tester) async {
    final results = <GameResult>[];
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260817),
      enableHaptics: false,
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.setNetPathForTesting(const [
      Point<double>(-866, 110),
      Point<double>(133, 110),
    ], direction: NetBoatDirection.east);
    expect(game.currentNetLength, 999);

    game.update(0.02);

    expect(results, isEmpty);
    expect(game.hud.value.phase, MiniGamePhase.playing);
    expect(game.currentNetLength, 0);
    expect(game.netRecoveryRemainingForTesting, greaterThan(0));
    expect(game.hud.value.message, contains('그물이 끊어졌어요'));

    expect(game.tapForTesting(), isTrue);
    expect(game.currentNetLength, 0);
    expect(game.netRecoveryRemainingForTesting, greaterThan(0));

    game.update(1.01);

    expect(game.netRecoveryRemainingForTesting, 0);
    expect(game.currentNetLength, greaterThan(0));
    expect(results, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('빈 폐곡선은 문구나 점수 팝업 없이 조용히 새 그물을 시작한다', (tester) async {
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260818),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.setNetPathForTesting(const [
      Point<double>(100, 100),
      Point<double>(120, 100),
      Point<double>(120, 120),
      Point<double>(100, 120),
      Point<double>(100, 120),
    ], direction: NetBoatDirection.north);

    game.update(0.25);

    expect(game.closedLoopsForTesting, 1);
    expect(game.hud.value.score, 0);
    expect(game.scorePopupCountForTesting, 0);
    expect(game.hud.value.message, isNot(contains('빈 그물')));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('포획한 정어리 위치에는 +10 팝업이 생성되고 사라진다', (tester) async {
    final game = NetBoatGame(
      countdownDuration: Duration.zero,
      random: Random(20260819),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.setCreatureForTesting(
      NetBoatCreatureKind.sardine,
      const Point<double>(130, 180),
    );
    game.setNetPathForTesting(const [
      Point<double>(100, 100),
      Point<double>(200, 100),
      Point<double>(200, 200),
      Point<double>(115, 200),
      Point<double>(115, 116),
    ], direction: NetBoatDirection.north);

    game.update(0.01);

    expect(game.closedLoopsForTesting, 1);
    expect(game.hud.value.score, 10);
    expect(game.scorePopupLabelsForTesting, ['+10']);

    game.update(0.86);
    expect(game.scorePopupCountForTesting, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

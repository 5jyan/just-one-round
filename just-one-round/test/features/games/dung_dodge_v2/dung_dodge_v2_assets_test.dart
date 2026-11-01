import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/dung_dodge_v2_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('똥피하기 런타임 에셋 크기가 계약과 일치한다', () async {
    const contract = {
      'assets/images/dung_dodge_v2/background_map.png': (360, 960),
      'assets/images/dung_dodge_v2/ground_strip.png': (360, 208),
      'assets/images/dung_dodge_v2/player_idle_sheet.png': (128, 128),
      'assets/images/dung_dodge_v2/player_run_sheet.png': (128, 128),
      'assets/images/dung_dodge_v2/poop_fall_sheet.png': (96, 96),
      'assets/images/dung_dodge_v2/dust_sheet.png': (32, 32),
      'assets/images/dung_dodge_v2/poop_impact_sheet.png': (128, 128),
      'assets/images/dung_dodge_v2/player_game_over.png': (64, 64),
      'assets/images/dung_dodge_v2/home_gameplay_hero.png': (1206, 1546),
    };

    for (final entry in contract.entries) {
      final data = await rootBundle.load(entry.key);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      addTearDown(codec.dispose);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);

      expect(
        (frame.image.width, frame.image.height),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('긴 화면은 플레이 영역을 늘리지 않고 그려진 오버스캔을 노출한다', () {
    expect(
      DungDodgeV2Game.viewportResolutionForCanvas(Vector2(360, 640)),
      Vector2(360, 640),
    );
    expect(
      DungDodgeV2Game.viewportResolutionForCanvas(Vector2(393, 852)).y,
      closeTo(780.46, 0.01),
    );
    expect(
      DungDodgeV2Game.viewportResolutionForCanvas(Vector2(360, 900)),
      Vector2(360, 800),
    );
  });

  test('올라간 지면 스트립은 가장 긴 일반 폰 뷰포트 아래까지 덮는다', () {
    const groundStripHeight = 208.0;
    const tallestViewportBottom = 720.0;

    expect(
      DungDodgeV2Game.groundY + groundStripHeight,
      greaterThanOrEqualTo(tallestViewportBottom),
    );
  });

  test('똥피하기 캐릭터는 가독성을 위해 64픽셀로 표시한다', () {
    expect(DungDodgeV2Game.playerSize, 64);
  });

  test('똥피하기 캐릭터는 잘리지 않는 범위에서 양끝까지 이동한다', () {
    final bounds = DungDodgeV2Game.playerHorizontalBounds(
      displaySize: DungDodgeV2Game.playerSize,
      edgePadding: 0,
    );

    expect(bounds.minimum, 32);
    expect(bounds.maximum, 328);
  });

  testWidgets('똥피하기 에셋으로 실제 Flame 화면을 구성한다', (tester) async {
    final game = DungDodgeV2Game(
      gameDuration: const Duration(seconds: 60),
      countdownDuration: Duration.zero,
      random: Random(3),
      onFinished: (_) {},
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(game.hud.value.remainingSeconds, isNull);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('플레이어 충돌 순간 실제 캐릭터가 KO 포즈로 교체된다', (tester) async {
    GameResult? result;
    final game = DungDodgeV2Game(
      gameDuration: const Duration(minutes: 5),
      countdownDuration: Duration.zero,
      random: Random(4),
      onFinished: (value) => result = value,
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump();
    await tester.runAsync(() => game.loaded);
    await tester.pump();

    expect(game.isShowingGameOverPoseForTesting, isFalse);
    game.handlePlayerCollisionForTesting();
    await tester.pump();

    expect(game.isShowingGameOverPoseForTesting, isTrue);
    expect(result?.collisions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('새 위치를 누르기만 하면 이동하지 않고 드래그한 만큼만 움직인다', (tester) async {
    final game = DungDodgeV2Game(
      gameDuration: const Duration(minutes: 5),
      countdownDuration: Duration.zero,
      random: Random(5),
      onFinished: (_) {},
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => game.loaded);
    final startingX = game.playerXForTesting;

    game.beginRelativeDragForTesting(300);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.playerXForTesting, startingX);

    game.updateRelativeDragForTesting(304);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.playerXForTesting, startingX);

    game.updateRelativeDragForTesting(312);
    expect(game.playerXForTesting, closeTo(startingX + 12, 0.0001));

    game.updateRelativeDragForTesting(330);
    expect(game.playerXForTesting, closeTo(startingX + 30, 0.0001));

    game.endPointerDragForTesting(0);
    expect(game.playerXForTesting, closeTo(startingX + 30, 0.0001));

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('드래그는 가로 경계를 넘지 않고 새 터치 위치로 순간이동하지 않는다', (tester) async {
    final game = DungDodgeV2Game(
      gameDuration: const Duration(minutes: 5),
      countdownDuration: Duration.zero,
      random: Random(6),
      onFinished: (_) {},
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => game.loaded);
    final startingX = game.playerXForTesting;

    game.beginRelativeDragForTesting(20);
    expect(game.playerXForTesting, closeTo(startingX, 0.0001));
    game.updateRelativeDragForTesting(1000);
    expect(
      game.playerXForTesting,
      DungDodgeV2Game.playerHorizontalBounds(
        displaySize: DungDodgeV2Game.playerSize,
        edgePadding: 0,
      ).maximum,
    );

    game.beginRelativeDragForTesting(340);
    expect(game.playerXForTesting, closeTo(328, 0.0001));
    game.updateRelativeDragForTesting(-1000);
    expect(
      game.playerXForTesting,
      DungDodgeV2Game.playerHorizontalBounds(
        displaySize: DungDodgeV2Game.playerSize,
        edgePadding: 0,
      ).minimum,
    );

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('viewport 크기가 달라도 손가락의 논리 가로 이동량을 그대로 사용한다', (tester) async {
    final game = DungDodgeV2Game(
      gameDuration: const Duration(minutes: 5),
      countdownDuration: Duration.zero,
      random: Random(7),
      onFinished: (_) {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 393,
          height: 852,
          child: GameWidget(key: const Key('dung-real-game'), game: game),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => game.loaded);

    final logicalStart = Vector2(80, 300);
    final logicalEnd = Vector2(140, 300);
    final canvasStart = game.camera.viewport.localToGlobal(logicalStart);
    final canvasEnd = game.camera.viewport.localToGlobal(logicalEnd);

    expect(
      game.logicalDragXForTesting(canvasEnd) -
          game.logicalDragXForTesting(canvasStart),
      closeTo(60, 0.0001),
    );

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('첫 번째 손가락만 드래그를 소유하고 다른 손가락 종료는 무시한다', (tester) async {
    final game = DungDodgeV2Game(
      gameDuration: const Duration(minutes: 5),
      countdownDuration: Duration.zero,
      random: Random(8),
      onFinished: (_) {},
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => game.loaded);
    final startingX = game.playerXForTesting;

    game.beginPointerDragForTesting(1, 100);
    game.beginPointerDragForTesting(2, 200);
    game.updatePointerDragForTesting(2, 280);
    expect(game.playerXForTesting, closeTo(startingX, 0.0001));

    game.updatePointerDragForTesting(1, 120);
    expect(game.playerXForTesting, closeTo(startingX + 20, 0.0001));
    game.endPointerDragForTesting(2);
    game.updatePointerDragForTesting(1, 140);
    expect(game.playerXForTesting, closeTo(startingX + 40, 0.0001));

    game.endPointerDragForTesting(1);
    game.beginPointerDragForTesting(2, 300);
    game.updatePointerDragForTesting(2, 310);
    expect(game.playerXForTesting, closeTo(startingX + 50, 0.0001));

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('실제 드래그는 작은 이동과 큰 이동을 합쳐 정확한 끝점에 멈춘다', (tester) async {
    final game = DungDodgeV2Game(
      gameDuration: const Duration(minutes: 5),
      countdownDuration: Duration.zero,
      random: Random(9),
      onFinished: (_) {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 393,
          height: 852,
          child: GameWidget(key: const Key('dung-real-game'), game: game),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => game.loaded);
    await tester.pump();

    final gameRect = tester.getRect(find.byKey(const Key('dung-real-game')));
    final viewport = game.camera.viewport;
    final logicalStart = Vector2(120, 300);
    final logicalSmallMove = Vector2(124, 300);
    final logicalEnd = Vector2(150, 300);
    Offset canvasPosition(Vector2 logicalPosition) {
      final canvasPoint = viewport.localToGlobal(logicalPosition);
      return gameRect.topLeft + Offset(canvasPoint.x, canvasPoint.y);
    }

    final startingX = game.playerXForTesting;
    final gesture = await tester.startGesture(canvasPosition(logicalStart));
    await gesture.moveBy(
      canvasPosition(logicalSmallMove) - canvasPosition(logicalStart),
    );
    await tester.pump();
    expect(game.playerXForTesting, closeTo(startingX, 0.0001));

    await gesture.moveBy(
      canvasPosition(logicalEnd) - canvasPosition(logicalSmallMove),
    );
    await tester.pump();
    expect(game.playerXForTesting, closeTo(startingX + 30, 0.0001));

    await gesture.up();
    await tester.pump();
    expect(game.playerXForTesting, closeTo(startingX + 30, 0.0001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('초반 실제 이동은 즉시 게임오버를 만들지 않는다', (tester) async {
    for (final seed in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      GameResult? result;
      final game = DungDodgeV2Game(
        gameDuration: const Duration(seconds: 10),
        countdownDuration: Duration.zero,
        random: Random(seed),
        onFinished: (value) => result = value,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 393,
            height: 852,
            child: GameWidget(key: const Key('dung-repro-game'), game: game),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => game.loaded);
      await tester.pump();

      final gameRect = tester.getRect(find.byKey(const Key('dung-repro-game')));
      final viewport = game.camera.viewport;
      Offset canvasPosition(Vector2 logicalPosition) {
        final canvasPoint = viewport.localToGlobal(logicalPosition);
        return gameRect.topLeft + Offset(canvasPoint.x, canvasPoint.y);
      }

      final gesture = await tester.startGesture(
        canvasPosition(Vector2(120, 300)),
      );
      await gesture.moveBy(
        canvasPosition(Vector2(136, 300)) - canvasPosition(Vector2(120, 300)),
      );
      for (var frame = 0; frame < 30; frame++) {
        if (frame % 3 == 0) {
          final direction = (frame ~/ 3).isEven ? -1 : 1;
          await gesture.moveBy(
            canvasPosition(Vector2(120 + direction * 16, 300)) -
                canvasPosition(Vector2(120, 300)),
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();

      expect(result, isNull, reason: 'seed=$seed');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('머리 위 똥은 안전하고 실제 세로 통과만 한 번 충돌한다', (tester) async {
    var finishes = 0;
    final game = DungDodgeV2Game(
      countdownDuration: Duration.zero,
      random: Random(3),
      onFinished: (_) => finishes++,
    );
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump();
    await tester.runAsync(() => game.loaded);
    game.addHazardForTesting(x: game.playerXForTesting, y: -48, speed: 170);
    await tester.pump();
    game.pauseEngine();
    game.update(0.1);
    expect(finishes, 0, reason: '가로 위치가 같아도 위쪽의 똥은 닿지 않았다');
    game.addHazardForTesting(x: game.playerXForTesting, y: 490, speed: 900);
    await tester.pump();
    game.update(0.1);
    expect(finishes, 1, reason: '한 프레임 사이 캐릭터를 통과한 똥은 충돌');
    game.update(0.1);
    expect(finishes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('빠른 가로 이동도 안전한 똥과 실제 접촉을 구분한다', (tester) async {
    var finishes = 0;
    final game = DungDodgeV2Game(
      countdownDuration: Duration.zero,
      random: Random(3),
      onFinished: (_) => finishes++,
    );
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump();
    await tester.runAsync(() => game.loaded);
    game.addHazardForTesting(x: 240, y: 100);
    await tester.pump();
    game.pauseEngine();
    game.beginRelativeDragForTesting(180);
    game.updateRelativeDragForTesting(290);
    expect(finishes, 0);
    game.updateRelativeDragForTesting(180);
    expect(finishes, 0);
    game.addHazardForTesting(x: 240, y: 544);
    await tester.pump();
    game.update(0);
    game.updateRelativeDragForTesting(290);
    expect(finishes, 1, reason: '끝점 밖이어도 이동 구간의 실제 똥은 충돌');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('똥 아랫면이 지면에 닿는 순간 충돌한다', () {
    expect(
      DungDodgeV2Game.hasReachedGround(
        centerY: 552,
        objectHeight: 48,
        groundY: DungDodgeV2Game.groundY,
      ),
      isTrue,
    );
    expect(
      DungDodgeV2Game.hasReachedGround(
        centerY: 550,
        objectHeight: 48,
        groundY: DungDodgeV2Game.groundY,
      ),
      isFalse,
    );
  });
}

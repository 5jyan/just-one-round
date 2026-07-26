import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/star_dodge/star_dodge_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('똥피하기 2 런타임 에셋 크기가 계약과 일치한다', () async {
    const contract = {
      'assets/images/dung_dodge_v2/background_map.png': (360, 960),
      'assets/images/dung_dodge_v2/ground_strip.png': (360, 208),
      'assets/images/dung_dodge_v2/player_idle_sheet.png': (128, 128),
      'assets/images/dung_dodge_v2/player_run_sheet.png': (128, 128),
      'assets/images/dung_dodge_v2/poop_fall_sheet.png': (96, 96),
      'assets/images/dung_dodge_v2/dust_sheet.png': (32, 32),
      'assets/images/dung_dodge_v2/poop_impact_sheet.png': (128, 128),
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
      StarDodgeGame.viewportResolutionForCanvas(Vector2(360, 640)),
      Vector2(360, 640),
    );
    expect(
      StarDodgeGame.viewportResolutionForCanvas(Vector2(393, 852)).y,
      closeTo(780.46, 0.01),
    );
    expect(
      StarDodgeGame.viewportResolutionForCanvas(Vector2(360, 900)),
      Vector2(360, 800),
    );
  });

  test('올라간 지면 스트립은 가장 긴 일반 폰 뷰포트 아래까지 덮는다', () {
    const groundStripHeight = 208.0;
    const tallestViewportBottom = 720.0;

    expect(
      StarDodgeGame.uglyCuteGroundY + groundStripHeight,
      greaterThanOrEqualTo(tallestViewportBottom),
    );
  });

  test('똥피하기 2 캐릭터는 가독성을 위해 64픽셀로 표시한다', () {
    expect(StarDodgeGame.uglyCutePlayerSize, 64);
    expect(
      StarDodgeGame.uglyCutePlayerSize / StarDodgeGame.classicPlayerSize,
      closeTo(1, 0.00001),
    );
  });

  test('똥피하기 2 캐릭터는 잘리지 않는 범위에서 양끝까지 이동한다', () {
    final bounds = StarDodgeGame.playerHorizontalBounds(
      displaySize: StarDodgeGame.uglyCutePlayerSize,
      edgePadding: 0,
    );

    expect(bounds.minimum, 32);
    expect(bounds.maximum, 328);
  });

  testWidgets('똥피하기 2 에셋으로 실제 Flame 화면을 구성한다', (tester) async {
    final game = StarDodgeGame(
      gameDuration: const Duration(seconds: 60),
      countdownDuration: Duration.zero,
      assetSet: StarDodgeAssetSet.uglyCute,
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

  testWidgets('새 위치를 누르기만 하면 이동하지 않고 드래그한 만큼만 움직인다', (tester) async {
    final game = StarDodgeGame(
      gameDuration: const Duration(minutes: 5),
      countdownDuration: Duration.zero,
      assetSet: StarDodgeAssetSet.uglyCute,
      random: Random(5),
      onFinished: (_) {},
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 100));
    final startingX = game.playerXForTesting;

    game.beginRelativeDragForTesting(300);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.playerXForTesting, startingX);

    game.updateRelativeDragForTesting(304);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.playerXForTesting, startingX);

    game.updateRelativeDragForTesting(312);
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.playerXForTesting, greaterThan(startingX));

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('똥 아랫면이 지면에 닿는 순간 충돌한다', () {
    expect(
      StarDodgeGame.hasReachedGround(
        centerY: 552,
        objectHeight: 48,
        groundY: StarDodgeGame.uglyCuteGroundY,
      ),
      isTrue,
    );
    expect(
      StarDodgeGame.hasReachedGround(
        centerY: 550,
        objectHeight: 48,
        groundY: StarDodgeGame.uglyCuteGroundY,
      ),
      isFalse,
    );
  });
}

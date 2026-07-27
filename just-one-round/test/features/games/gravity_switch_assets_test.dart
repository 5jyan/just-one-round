import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/gravity_switch/gravity_switch_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('자석 진드기 플레이어 시트가 네이티브 48픽셀 2x2 프레임이다', () async {
    final data = await rootBundle.load(
      'assets/images/gravity_switch_v2/player_magnet_mite_sheet_v3.png',
    );
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    addTearDown(codec.dispose);
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);

    expect((frame.image.width, frame.image.height), (96, 96));
  });

  test('자석 진드기 GAME OVER 에셋이 투명 48픽셀 단일 프레임이다', () async {
    final data = await rootBundle.load(
      'assets/images/gravity_switch_v2/player_game_over.png',
    );
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    addTearDown(codec.dispose);
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);

    expect((frame.image.width, frame.image.height), (48, 48));
  });

  test('메인과 설명서 캡처는 실제 런타임의 다중 프레임 애니메이션이다', () async {
    const captures = {
      'gravity_runtime_main.webp': (360, 462),
      'gravity_runtime_tap.webp': (360, 268),
      'gravity_runtime_control.webp': (360, 268),
      'gravity_runtime_obstacle.webp': (360, 268),
      'gravity_runtime_hard.webp': (360, 268),
      'gravity_runtime_collision.webp': (360, 268),
    };
    for (final entry in captures.entries) {
      final data = await rootBundle.load(
        'assets/images/gravity_switch_v2/${entry.key}',
      );
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      addTearDown(codec.dispose);
      expect(codec.frameCount, greaterThan(1), reason: entry.key);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);
      expect(
        (frame.image.width, frame.image.height),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('v3와 v4 고철 모듈 31개가 온전한 48픽셀 셀 크기로 포함된다', () async {
    const v4Specs = {
      'scrap_basic_1x1_01': (1, 1),
      'scrap_basic_1x1_02': (1, 1),
      'scrap_basic_1x1_03': (1, 1),
      'scrap_basic_1x1_04': (1, 1),
      'scrap_basic_1x2_01': (1, 2),
      'scrap_basic_1x2_02': (1, 2),
      'scrap_basic_2x1_01': (2, 1),
      'scrap_basic_2x1_02': (2, 1),
      'scrap_basic_2x2_01': (2, 2),
      'scrap_basic_2x2_02': (2, 2),
      'scrap_basic_3x1_01': (3, 1),
      'scrap_basic_3x1_02': (3, 1),
      'scrap_basic_1x3_01': (1, 3),
      'scrap_basic_1x3_02': (1, 3),
      'scrap_basic_3x2_01': (3, 2),
    };
    const v3Specs = {
      'scrap_module_1x1_01': (1, 1),
      'scrap_module_1x1_02': (1, 1),
      'scrap_module_1x1_03': (1, 1),
      'scrap_module_1x1_04': (1, 1),
      'scrap_module_1x2_01': (1, 2),
      'scrap_module_1x2_02': (1, 2),
      'scrap_module_2x1_01': (2, 1),
      'scrap_module_2x1_02': (2, 1),
      'scrap_module_2x2_01': (2, 2),
      'scrap_module_2x2_02': (2, 2),
      'scrap_module_3x1_01': (3, 1),
      'scrap_module_3x1_02': (3, 1),
      'scrap_module_1x3_01': (1, 3),
      'scrap_module_1x3_02': (1, 3),
      'scrap_module_3x2_01': (3, 2),
      'scrap_module_2x3_01': (2, 3),
    };
    for (final entry in v4Specs.entries) {
      final data = await rootBundle.load(
        'assets/images/gravity_switch_v2/platform_modules_v4/${entry.key}.png',
      );
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      addTearDown(codec.dispose);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);
      expect(
        (frame.image.width, frame.image.height),
        (entry.value.$1 * 48, entry.value.$2 * 48),
        reason: entry.key,
      );
    }
    for (final entry in v3Specs.entries) {
      final data = await rootBundle.load(
        'assets/images/gravity_switch_v2/platform_modules_v3/${entry.key}.png',
      );
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      addTearDown(codec.dispose);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);
      expect(
        (frame.image.width, frame.image.height),
        (entry.value.$1 * 48, entry.value.$2 * 48),
        reason: entry.key,
      );
    }
  });

  testWidgets('v3와 v4 고철 모듈로 실제 Flame 화면을 구성한다', (tester) async {
    final game = GravitySwitchGame(
      countdownDuration: Duration.zero,
      random: Random(3),
      onFinished: (_) {},
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

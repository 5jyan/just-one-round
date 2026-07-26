import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/gravity_switch/gravity_switch_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scenarios = <_CaptureScenario>[
    const _CaptureScenario(
      id: 'control',
      patternIds: ['large_m'],
      tapAtSeconds: [0.8, 2.35],
      frameCount: 38,
    ),
    const _CaptureScenario(
      id: 'obstacle',
      patternIds: ['missile'],
      tapAtSeconds: [0.1],
      initialSafeColumnCount: 8,
      frameCount: 38,
    ),
    const _CaptureScenario(
      id: 'hard',
      patternIds: ['v_hard', 'tick_hard'],
      tapAtSeconds: [60.8, 62.25],
      initialElapsedSeconds: 60,
      initialSafeColumnCount: 5,
      frameCount: 30,
    ),
    const _CaptureScenario(
      id: 'collision',
      patternIds: ['missile'],
      initialSafeColumnCount: 5,
      frameCount: 30,
    ),
  ];

  for (final scenario in scenarios) {
    testWidgets('capture ${scenario.id}', (tester) async {
      await tester.runAsync(() async {
        final output = Directory(
          'assets/source/runtime_capture/gravity_switch/frames/${scenario.id}',
        );
        if (output.existsSync()) output.deleteSync(recursive: true);
        output.createSync(recursive: true);

        final game = GravitySwitchGame(
          countdownDuration: Duration.zero,
          random: Random(2707),
          captureConfig: GravitySwitchCaptureConfig(
            patternIds: scenario.patternIds,
            tapAtSeconds: scenario.tapAtSeconds,
            initialElapsedSeconds: scenario.initialElapsedSeconds,
            initialSafeColumnCount: scenario.initialSafeColumnCount,
          ),
          onFinished: (_) {},
        );
        game.onGameResize(Vector2(360, 640));
        await game.load();
        game.mount();
        game.update(0);

        for (var frame = 0; frame < scenario.frameCount; frame++) {
          if (frame > 0 && !game.paused) game.update(0.1);

          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          game.render(canvas);
          final picture = recorder.endRecording();
          final image = await picture.toImage(360, 640);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          File(
            '${output.path}/${frame.toString().padLeft(3, '0')}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        }
        game.disposeController();
      });
    });
  }
}

class _CaptureScenario {
  const _CaptureScenario({
    required this.id,
    required this.patternIds,
    this.tapAtSeconds = const [],
    this.initialElapsedSeconds = 0,
    this.initialSafeColumnCount,
    required this.frameCount,
  });

  final String id;
  final List<String> patternIds;
  final List<double> tapAtSeconds;
  final double initialElapsedSeconds;
  final int? initialSafeColumnCount;
  final int frameCount;
}

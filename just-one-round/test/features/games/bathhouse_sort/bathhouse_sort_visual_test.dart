import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/bathhouse_sort/bathhouse_sort_game.dart';
import 'package:just_one_round/features/games/bathhouse_sort/domain/bathhouse_sort_rules.dart';
import 'package:just_one_round/features/games/bathhouse_sort/presentation/bathhouse_sort_preview.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await loader.load();
  });

  testWidgets('고급 목욕탕 에셋이 360x640 화면을 채운다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('bathhouse-sort-runtime-capture');
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      random: Random(20260815),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && !game.isReady; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(game.isReady, isTrue);
    game.tapLogical(
      game.currentGuest.entrance == BathEntrance.mens
          ? Vector2(80, 590)
          : Vector2(280, 590),
    );
    await tester.pump(const Duration(milliseconds: 100));
    game.pauseEngine();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/bathhouse_sort_runtime_360x640.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('긴 360x800 화면도 위아래 빈 공간 없이 채운다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('bathhouse-sort-tall-capture');
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      random: Random(20260815),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && !game.isReady; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    game.pauseEngine();

    expect(game.isReady, isTrue);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/bathhouse_sort_runtime_360x800.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('짧은 400x640 화면도 좌우 빈 공간 없이 채운다', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('bathhouse-sort-short-capture');
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      random: Random(20260815),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && !game.isReady; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    game.pauseEngine();

    expect(game.isReady, isTrue);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/bathhouse_sort_runtime_400x640.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('미리보기 루프는 화면·점수·콤보·시간을 한 프레임에서 함께 되감는다', () {
    final first = BathhouseSortPreviewFrame.fromCycle(0);
    final wrapped = BathhouseSortPreviewFrame.fromCycle(1);

    expect(wrapped.isWomensTurn, first.isWomensTurn);
    expect(wrapped.actionProgress, first.actionProgress);
    expect(wrapped.isDeparting, first.isDeparting);
    expect(wrapped.combo, first.combo);
    expect(wrapped.score, first.score);
    expect(wrapped.secondsLeft, first.secondsLeft);
  });

  testWidgets('홈 미리보기가 공통 360x462 카드에서 핵심 장면을 보여준다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 462)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('bathhouse-sort-preview-capture');
    await tester.pumpWidget(
      const MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(
            child: BathhouseSortPreview(
              scene: BathhouseSortPreviewScene.home,
              animate: false,
            ),
          ),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 100 &&
          find
              .byKey(const Key('bathhouse-sort-preview-ready'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.byKey(const Key('bathhouse-sort-preview')), findsOneWidget);
    expect(
      find.byKey(const Key('bathhouse-sort-preview-ready')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/bathhouse_sort_preview_360x462.png'),
    );
  });

  testWidgets('설명 애니메이션은 350x360에서도 캐릭터 비율과 핵심 UI를 유지한다', (tester) async {
    tester.view
      ..physicalSize = const Size(350, 360)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('bathhouse-sort-guide-capture');
    await tester.pumpWidget(
      const MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(
            child: BathhouseSortPreview(
              scene: BathhouseSortPreviewScene.controls,
              animate: false,
            ),
          ),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 100 &&
          find
              .byKey(const Key('bathhouse-sort-preview-ready'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/bathhouse_sort_guide_350x360.png'),
    );
  });

  testWidgets('네 설명 장면 모두 실제 스프라이트와 안전영역을 유지한다', (tester) async {
    tester.view
      ..physicalSize = const Size(700, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('bathhouse-sort-guide-scenes-capture');
    const scenes = <(BathhouseSortPreviewScene, double)>[
      (BathhouseSortPreviewScene.controls, 0.22),
      (BathhouseSortPreviewScene.queue, 0.42),
      (BathhouseSortPreviewScene.unlock, 0.55),
      (BathhouseSortPreviewScene.scoring, 0.82),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: Column(
            children: [
              for (var row = 0; row < 2; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (var column = 0; column < 2; column++)
                        Expanded(
                          child: BathhouseSortPreview(
                            scene: scenes[row * 2 + column].$1,
                            animate: false,
                            staticCycle: scenes[row * 2 + column].$2,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 100 &&
          find
                  .byKey(const Key('bathhouse-sort-preview-ready'))
                  .evaluate()
                  .length <
              4;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(
      find.byKey(const Key('bathhouse-sort-preview-ready')),
      findsNWidgets(4),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/bathhouse_sort_guide_scenes_700x720.png'),
    );
  });

  testWidgets('15초 새 얼굴표가 플레이를 가리지 않고 빛난다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('bathhouse-sort-unlock-capture');
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      random: Random(20260815),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && !game.isReady; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    game.update(15);
    game.update(0.4);
    await tester.pump();
    game.pauseEngine();

    expect(game.gamePhase, BathhouseSortPhase.playing);
    expect(game.activePairCount, 2);
    expect(game.rosterRevealPairIndex, 1);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/bathhouse_sort_unlock_360x640.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('25콤보 성공 이펙트가 크게 터지며 점수를 보여준다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('bathhouse-sort-fever-capture');
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      random: Random(20260815),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && !game.isReady; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    for (var index = 0; index < 25; index++) {
      game.tapLogical(
        game.currentGuest.entrance == BathEntrance.mens
            ? Vector2(80, 590)
            : Vector2(280, 590),
      );
      game.update(0.046);
    }
    game.update(0.08);
    await tester.pump();
    game.pauseEngine();

    expect(game.combo, 25);
    expect(game.hud.value.score, 5500);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/bathhouse_sort_fever_360x640.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

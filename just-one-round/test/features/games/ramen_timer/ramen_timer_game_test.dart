import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/ramen_timer/domain/ramen_timer_rules.dart';
import 'package:just_one_round/features/games/ramen_timer/ramen_timer_game.dart';

void main() {
  test('세로 화면은 360 폭과 최대 800 높이의 오버스캔을 유지한다', () {
    expect(
      RamenTimerGame.viewportResolutionForCanvas(Vector2(360, 640)),
      Vector2(360, 640),
    );
    expect(
      RamenTimerGame.viewportResolutionForCanvas(Vector2(430, 932)).y,
      closeTo(780.28, 0.02),
    );
    expect(
      RamenTimerGame.viewportResolutionForCanvas(Vector2(360, 1200)),
      Vector2(360, 800),
    );
  });

  testWidgets('3초는 보이고 3.2초부터만 입력을 받는다', (tester) async {
    final clock = FakeRamenTimerClock();
    final game = RamenTimerGame(
      countdownDuration: Duration.zero,
      clock: clock,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);

    clock.setMilliseconds(2999);
    await tester.pump();
    expect(game.gamePhase, RamenTimerPhase.calibrationVisible);
    expect(game.canTap, isFalse);
    game.triggerPrimaryAction();
    expect(game.tapMilliseconds, isEmpty);

    clock.setMilliseconds(3000);
    await tester.pump();
    expect(game.gamePhase, RamenTimerPhase.clockCovering);
    clock.setMilliseconds(3199);
    await tester.pump();
    expect(game.canTap, isFalse);

    clock.setMilliseconds(3200);
    await tester.pump();
    expect(game.gamePhase, RamenTimerPhase.waitingFor10);
    expect(game.canTap, isTrue);
    expect(game.hud.value.primaryActionEnabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('승인 예시를 프레임과 무관한 시각으로 기록해 한 번만 끝낸다', (tester) async {
    final clock = FakeRamenTimerClock();
    GameResult? result;
    var finishCount = 0;
    final game = RamenTimerGame(
      countdownDuration: Duration.zero,
      clock: clock,
      onFinished: (value) {
        result = value;
        finishCount++;
      },
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    clock.setMilliseconds(3200);
    await tester.pump();

    for (final milliseconds in [9820, 20310, 29900]) {
      clock.setMilliseconds(milliseconds);
      game.triggerPrimaryAction();
    }

    expect(game.tapMilliseconds, [9820, 20310, 29900]);
    expect(game.lockedScore, 3599410);
    expect(game.gamePhase, RamenTimerPhase.resultReveal);
    expect(finishCount, 0);

    await tester.pump(const Duration(milliseconds: 2400));
    expect(game.resultRevealProgress, 1);
    expect(finishCount, 0);
    await tester.pump(const Duration(milliseconds: 5500));
    expect(finishCount, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(finishCount, 1);
    expect(result!.score, 3599410);
    expect(result!.duration, const Duration(milliseconds: 29900));
    expect(result!.starsCollected, 0);
    expect(result!.collisions, 0);
    expect(result!.endType, GameEndType.clear);
    await tester.pump(const Duration(seconds: 2));
    expect(finishCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('250ms 잠금은 우발적 이중 탭을 무시한다', (tester) async {
    final clock = FakeRamenTimerClock();
    final game = RamenTimerGame(
      countdownDuration: Duration.zero,
      clock: clock,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    clock.setMilliseconds(10000);
    await tester.pump();
    game.triggerPrimaryAction();

    clock.setMilliseconds(10249);
    game.triggerPrimaryAction();
    expect(game.tapMilliseconds, [10000]);
    expect(game.hud.value.primaryActionEnabled, isFalse);

    clock.setMilliseconds(10250);
    await tester.pump();
    expect(game.hud.value.primaryActionEnabled, isTrue);
    game.triggerPrimaryAction();
    expect(game.tapMilliseconds, [10000, 10250]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('45초에 세 번째 탭이 없으면 시간 초과를 한 번 제출한다', (tester) async {
    final clock = FakeRamenTimerClock();
    final results = <GameResult>[];
    final game = RamenTimerGame(
      countdownDuration: Duration.zero,
      clock: clock,
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    clock.setMilliseconds(RamenTimerRules.timeoutMilliseconds);
    game.update(0);

    expect(results, hasLength(1));
    expect(results.single.score, 0);
    expect(results.single.duration, const Duration(milliseconds: 45000));
    expect(results.single.endType, GameEndType.timeUp);
    game.triggerPrimaryAction();
    await tester.pump(const Duration(seconds: 1));
    expect(results, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('정확히 45초의 pointer down은 업데이트보다 먼저 오면 유효하다', (tester) async {
    final clock = FakeRamenTimerClock();
    GameResult? result;
    final game = RamenTimerGame(
      countdownDuration: Duration.zero,
      clock: clock,
      onFinished: (value) => result = value,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    clock.setMilliseconds(44500);
    await tester.pump();
    game.triggerPrimaryAction();
    clock.setMilliseconds(44750);
    game.triggerPrimaryAction();
    clock.setMilliseconds(45000);
    game.triggerPrimaryAction();

    expect(game.gamePhase, RamenTimerPhase.resultReveal);
    expect(game.lockedScore, RamenTimerRules.minimumNormalRankingScore);
    await tester.pump(const Duration(milliseconds: 8100));
    expect(result!.endType, GameEndType.clear);
    expect(result!.duration, const Duration(milliseconds: 45000));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('중단은 결과를 만들지 않는다', (tester) async {
    final clock = FakeRamenTimerClock();
    var finishCount = 0;
    final game = RamenTimerGame(
      countdownDuration: Duration.zero,
      clock: clock,
      onFinished: (_) => finishCount++,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    clock.setMilliseconds(10000);
    await tester.pump();
    game.triggerPrimaryAction();
    game.interrupt();
    game.interrupt();

    expect(game.gamePhase, RamenTimerPhase.interrupted);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    expect(finishCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class FakeRamenTimerClock implements RamenTimerClock {
  Duration _elapsed = Duration.zero;
  var _isRunning = false;

  @override
  Duration get elapsed => _elapsed;

  @override
  bool get isRunning => _isRunning;

  void setMilliseconds(int value) {
    _elapsed = Duration(milliseconds: value);
  }

  @override
  void start() => _isRunning = true;

  @override
  void stop() => _isRunning = false;
}

Future<void> _waitUntilLoaded(WidgetTester tester, RamenTimerGame game) async {
  for (var attempt = 0; attempt < 30 && !game.assetsReady; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(game.assetsReady, isTrue);
}

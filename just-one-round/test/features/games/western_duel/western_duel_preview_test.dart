import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/western_duel/presentation/western_duel_preview.dart';
import 'package:just_one_round/features/games/western_duel/western_duel_game.dart';

void main() {
  test('short and tall slots use one width based scene scale', () {
    const shortSlot = Size(320, 300);
    const tallSlot = Size(430, 932);

    expect(
      WesternDuelPreview.logicalHeightForSlot(shortSlot),
      WesternDuelPreview.minimumLogicalHeight,
    );
    expect(
      WesternDuelPreview.logicalHeightForSlot(tallSlot),
      closeTo(780.279, 0.001),
    );

    final shortScene = WesternDuelPreview.sceneRectForSlot(shortSlot);
    final tallScene = WesternDuelPreview.sceneRectForSlot(tallSlot);
    expect(shortScene.width, shortSlot.width);
    expect(shortScene.height, closeTo(426.667, 0.001));
    expect(tallScene, const Rect.fromLTWH(0, 0, 430, 932));
  });

  test('home cycle has explicit wait, draw, result, and reset boundaries', () {
    final wait = WesternDuelPreview.frameForElapsed(0);
    final draw = WesternDuelPreview.frameForElapsed(
      WesternDuelPreview.waitDurationSeconds,
    );
    final flash = WesternDuelPreview.frameForElapsed(
      WesternDuelPreview.waitDurationSeconds + 0.22,
    );
    final result = WesternDuelPreview.frameForElapsed(
      WesternDuelPreview.waitDurationSeconds +
          WesternDuelPreview.drawDurationSeconds,
    );
    final reset = WesternDuelPreview.frameForElapsed(
      WesternDuelPreview.cycleDurationSeconds,
    );

    expect(wait.phase, WesternDuelPreviewPhase.wait);
    expect(wait.showMuzzleFlash, isFalse);
    expect(draw.phase, WesternDuelPreviewPhase.draw);
    expect(draw.playerFrame, WesternDuelGame.playerActionFrameForElapsed(0));
    expect(flash.showMuzzleFlash, isTrue);
    expect(result.phase, WesternDuelPreviewPhase.result);
    expect(result.playerFrame, WesternDuelGame.playerActionFrameCount - 1);
    expect(reset.phase, wait.phase);
    expect(reset.playerFrame, wait.playerFrame);
    expect(reset.opponentFrame, wait.opponentFrame);
    expect(reset.showMuzzleFlash, isFalse);
  });

  test(
    'signal and name badges stay above the opponent in every supported slot',
    () {
      for (final height in [480.0, 640.0, 780.279]) {
        final opponent = WesternDuelGame.opponentRectForHeight(height);
        final name = WesternDuelPreview.opponentNameRectForHeight(height);
        final signal = WesternDuelPreview.signalRectForHeight(height);
        final result = WesternDuelPreview.resultRectForHeight(height);

        expect(signal.bottom, lessThan(name.top));
        expect(name.bottom, lessThan(opponent.top));
        expect(signal.left, greaterThanOrEqualTo(0));
        expect(signal.right, lessThanOrEqualTo(360));
        expect(result.left, greaterThanOrEqualTo(0));
        expect(result.right, lessThanOrEqualTo(360));
        expect(result.top, signal.top);
        expect(name.left, greaterThanOrEqualTo(0));
        expect(name.right, lessThanOrEqualTo(360));
        expect(
          WesternDuelGame.playerMuzzlePositionForHeight(height).dy,
          inInclusiveRange(0, height),
        );
      }
    },
  );

  testWidgets('guide scenes render inside short and tall slots', (
    tester,
  ) async {
    for (final size in [const Size(320, 300), const Size(430, 932)]) {
      for (final scene in WesternDuelPreviewScene.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: WesternDuelPreview(scene: scene),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('맥크리'), findsOneWidget);
        expect(find.textContaining('BOT'), findsNothing);
      }
    }
  });
}

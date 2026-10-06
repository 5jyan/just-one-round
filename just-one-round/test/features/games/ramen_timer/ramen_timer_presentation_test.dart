import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/ramen_timer/presentation/ramen_timer_presentation.dart';
import 'package:just_one_round/features/games/ramen_timer/presentation/ramen_timer_preview.dart';

void main() {
  test('three guide pages cover the approved valuable-attempt rules', () {
    final pages = ramenTimerPresentation.guidePages;
    final copy = pages
        .expand((page) => [page.title, page.description, page.detail])
        .join(' ');

    expect(pages, hasLength(3));
    expect(pages.first.visual.name, 'ramenCheckpoints');
    expect(pages[1].visual.name, 'ramenCalibration');
    expect(pages[2].visual.name, 'ramenResult');
    expect(copy, contains('10초·파 넣기'));
    expect(copy, contains('20초·계란 넣기'));
    expect(copy, contains('30초·뚜껑 열기'));
    expect(copy, contains('처음 3초'));
    expect(copy, contains('3.2초'));
    expect(copy, contains('목표보다 몇 초 빠르거나 늦었는지'));
    expect(copy, isNot(contains('12~13초')));
    expect(copy, isNot(contains('22~23초')));
    expect(copy, contains('세 기록'));
    expect(copy, contains('45초'));
    expect(copy, contains('일시정지는 다시 이어도'));
    expect(copy, contains('스톱워치가 계속 흐르고'));
    expect(copy, contains('명시적 나가기는 미완료 시도로 끝나요'));
  });

  test('home loop derives the full recipe from one wrapped frame', () {
    final initial = RamenTimerPreviewSnapshot.forFrame(0);
    final clockVisible = RamenTimerPreviewSnapshot.forFrame(5);
    final hiddenBeforeUnlock = RamenTimerPreviewSnapshot.forFrame(6);
    final ready = RamenTimerPreviewSnapshot.forFrame(7);
    final firstAction = RamenTimerPreviewSnapshot.forFrame(20);
    final secondAction = RamenTimerPreviewSnapshot.forFrame(40);
    final thirdAction = RamenTimerPreviewSnapshot.forFrame(60);
    final result = RamenTimerPreviewSnapshot.forFrame(64);

    expect(initial.elapsedMilliseconds, 0);
    expect(initial.timerText, '0.00초');
    expect(initial.clockCovered, isFalse);
    expect(initial.inputReady, isFalse);
    expect(initial.stageLabel, '10초·파 넣기');

    expect(clockVisible.timerText, '2.50초');
    expect(clockVisible.clockCovered, isFalse);
    expect(hiddenBeforeUnlock.timerText, '??.??초');
    expect(hiddenBeforeUnlock.clockCovered, isTrue);
    expect(hiddenBeforeUnlock.inputReady, isFalse);
    expect(ready.inputReady, isTrue);

    expect(firstAction.tapCount, 1);
    expect(firstAction.cupFrame, 1);
    expect(firstAction.ingredientFrame, 2);
    expect(firstAction.poseFrame, 2);
    expect(firstAction.caption, '10초 · 파 넣기');
    expect(RamenTimerPreviewSnapshot.forFrame(22).cupFrame, 0);
    expect(secondAction.tapCount, 2);
    expect(secondAction.cupFrame, 2);
    expect(secondAction.ingredientFrame, 3);
    expect(secondAction.poseFrame, 3);
    expect(secondAction.caption, '20초 · 계란 넣기');
    expect(RamenTimerPreviewSnapshot.forFrame(42).cupFrame, 0);
    expect(thirdAction.tapCount, 3);
    expect(thirdAction.cupFrame, 3);
    expect(thirdAction.resultVisible, isFalse);
    expect(thirdAction.poseFrame, 4);
    expect(thirdAction.caption, '30초 · 뚜껑 열기');
    expect(result.resultVisible, isTrue);
    expect(result.tapCount, 3);
    expect(result.cupFrame, 3);
    expect(result.poseFrame, 5);
    expect(result.caption, '세 오차를 더해요');
  });

  test('each checkpoint shows only its signed error, then hides again', () {
    final firstFeedback = RamenTimerPreviewSnapshot.forFrame(20);
    final firstHidden = RamenTimerPreviewSnapshot.forFrame(24);
    final secondFeedback = RamenTimerPreviewSnapshot.forFrame(40);
    final secondHidden = RamenTimerPreviewSnapshot.forFrame(44);

    expect(firstFeedback.clockCovered, isTrue);
    expect(firstFeedback.timerText, '??.??초');
    expect(firstFeedback.checkpointDeltaText, '-0.18초');
    expect(firstHidden.timerText, '??.??초');
    expect(firstHidden.checkpointDeltaText, isNull);
    expect(secondFeedback.timerText, '??.??초');
    expect(secondFeedback.checkpointDeltaText, '+0.31초');
    expect(secondHidden.timerText, '??.??초');
    expect(secondHidden.checkpointDeltaText, isNull);
  });

  test('home loop resets every dependent state at the boundary', () {
    final before = RamenTimerPreviewSnapshot.forFrame(79);
    final after = RamenTimerPreviewSnapshot.forFrame(80);

    expect(before.resultVisible, isTrue);
    expect(before.tapCount, 3);
    expect(after.frame, 0);
    expect(after.elapsedMilliseconds, 0);
    expect(after.resultVisible, isFalse);
    expect(after.tapCount, 0);
    expect(after.poseFrame, -1);
    expect(after.ingredientFrame, -1);
    expect(after.clockCovered, isFalse);
    expect(after.smokeProgress, 0);
    expect(after.timerText, '0.00초');
    expect(
      RamenTimerPreviewSnapshot.forFrame(160).frame,
      RamenTimerPreviewSnapshot.forFrame(0).frame,
    );
  });

  testWidgets('all guide scenes fit short and tall guide viewports', (
    tester,
  ) async {
    for (final size in const [Size(393, 268), Size(393, 360)]) {
      for (final scene in RamenTimerPreviewScene.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: RamenTimerPreview(scene: scene, animate: false),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${scene.name} $size');
      }
    }
  });

  testWidgets('home preview shows the compressed full-sequence label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 360,
          height: 460,
          child: RamenTimerPreview(
            scene: RamenTimerPreviewScene.home,
            animate: false,
            initialFrame: 41,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('ramen-timer-preview-demo-label')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ramen-timer-preview-result')), findsNothing);
    expect(find.text('30초·뚜껑 열기'), findsNWidgets(2));
    expect(find.text('빠르게 보는 플레이 예시 · 실제 30초 압축'), findsOneWidget);
    expect(find.text('??.??초'), findsOneWidget);
    expect(find.text('+0.31초'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

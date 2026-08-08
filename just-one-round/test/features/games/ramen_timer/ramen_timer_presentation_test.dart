import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/ramen_timer/presentation/ramen_timer_presentation.dart';
import 'package:just_one_round/features/games/ramen_timer/presentation/ramen_timer_preview.dart';

void main() {
  test('three guide pages cover every valuable-attempt rule', () {
    final pages = ramenTimerPresentation.guidePages;
    final copy = pages
        .expand((page) => [page.title, page.description, page.detail])
        .join(' ');

    expect(pages, hasLength(3));
    expect(pages.first.title, '10·20·30초에 찍기');
    expect(pages.first.visual.name, 'ramenCheckpoints');
    expect(pages[1].title, '연기 사이 힌트 보기');
    expect(pages[1].visual.name, 'ramenCalibration');
    expect(copy, contains('처음 3초'));
    expect(copy, contains('3.2초'));
    expect(copy, contains('12~13초'));
    expect(copy, contains('22~23초'));
    expect(copy, contains('10·20·30초'));
    expect(copy, contains('마지막까지 알려주지 않아요'));
    expect(copy, contains('세 기록'));
    expect(copy, contains('45초'));
    expect(copy, contains('점수 없이 오늘 기회가 소진'));
  });

  test('home loop only teaches 1, 2, 3 and the first 10-second target', () {
    final one = RamenTimerPreviewSnapshot.forFrame(0);
    final two = RamenTimerPreviewSnapshot.forFrame(10);
    final three = RamenTimerPreviewSnapshot.forFrame(20);
    final covered = RamenTimerPreviewSnapshot.forFrame(40);

    expect(one.timerText, '1.00초');
    expect(two.timerText, '2.00초');
    expect(three.timerText, '3.00초');
    expect(covered.clockCovered, isTrue);
    expect(covered.smokeProgress, 1);
    expect(covered.clockPeekStrength, 0);
    expect(covered.timerText, '??.??초');
    expect(covered.tapCount, 0);
    expect(covered.resultVisible, isFalse);
    expect(covered.ingredientFrame, -1);
  });

  test('guide keeps the faint 12-second smoke hint outside the home loop', () {
    final hint = RamenTimerPreviewSnapshot.calibrationGuide;

    expect(hint.clockCovered, isTrue);
    expect(hint.smokeProgress, 1);
    expect(hint.clockPeekStrength, 1);
    expect(hint.timerText, '12.50초');
  });

  test('home loop resets every dependent state at the boundary', () {
    final before = RamenTimerPreviewSnapshot.forFrame(59);
    final after = RamenTimerPreviewSnapshot.forFrame(60);

    expect(before.clockCovered, isTrue);
    expect(before.smokeProgress, 1);
    expect(before.timerText, '??.??초');
    expect(before.resultVisible, isFalse);
    expect(before.tapCount, 0);
    expect(after.resultVisible, isFalse);
    expect(after.tapCount, 0);
    expect(after.poseFrame, -1);
    expect(after.ingredientFrame, -1);
    expect(after.clockCovered, isFalse);
    expect(after.smokeProgress, 0);
    expect(after.timerText, '1.00초');
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

  testWidgets('home preview labels its compressed timing as a demo', (
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
            initialFrame: 45,
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
    expect(find.text('10초 지금 찍기!'), findsOneWidget);
    expect(find.text('??.??초'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

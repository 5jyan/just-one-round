import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

void main() {
  testWidgets('좁은 버튼에서도 긴 한국어 라벨은 한 줄 높이를 유지한다', (tester) async {
    for (final width in [159.0, 167.0, 193.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              child: PixelButton(
                label: '딱 한판만 더!',
                icon: Icons.play_arrow_rounded,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(PixelButton)).height, 56);
      final label = tester.widget<Text>(find.text('딱 한판만 더!'));
      expect(label.maxLines, 1);
      expect(label.softWrap, isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('activateOnTapDown records before pointer up', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PixelButton(
            label: '찍기!',
            activateOnTapDown: true,
            onPressed: () => presses++,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PixelButton)),
    );
    expect(presses, 1);
    await gesture.up();
    expect(presses, 1);
  });

  testWidgets('default button behavior remains pointer up', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PixelButton(label: '확인', onPressed: () => presses++),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PixelButton)),
    );
    expect(presses, 0);
    await gesture.up();
    expect(presses, 1);
  });

  testWidgets('pointer-down callback may disable the button immediately', (
    tester,
  ) async {
    var enabled = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Center(
            child: PixelButton(
              label: '찍기!',
              activateOnTapDown: true,
              onPressed: enabled ? () => setState(() => enabled = false) : null,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PixelButton)),
    );
    await tester.pump();
    expect(enabled, isFalse);
    expect(tester.takeException(), isNull);

    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pointer-down mode ignores extra fingers until release', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PixelButton(
            label: '찍기!',
            activateOnTapDown: true,
            onPressed: () => presses++,
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(PixelButton));
    final first = await tester.startGesture(center, pointer: 1);
    final second = await tester.startGesture(center, pointer: 2);
    expect(presses, 1);

    await second.up();
    expect(presses, 1);
    await first.up();

    final third = await tester.startGesture(center, pointer: 3);
    expect(presses, 2);
    await third.up();
  });
}

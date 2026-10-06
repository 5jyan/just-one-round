import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

void main() {
  testWidgets('한글 어절 안에서 줄바꿈하지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 90,
            child: WordSafeText(
              '버튼을 탭하세요',
              key: Key('word-safe-text'),
              style: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );

    expect(find.text('버튼을 탭하세요'), findsOneWidget);
    final renderedWords = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byKey(const Key('word-safe-text')),
            matching: find.byType(RichText),
          ),
        )
        .toList(growable: false);
    expect(
      renderedWords.map(
        (text) => text.text.toPlainText().replaceAll('\u200B', ''),
      ),
      ['버튼을', '탭하세요'],
    );
    expect(renderedWords.every((text) => text.maxLines == null), isTrue);
    expect(renderedWords.every((text) => text.softWrap), isTrue);
    expect(
      renderedWords.every((text) => text.overflow == TextOverflow.visible),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('긴 단어도 한 줄에서 잘리지 않고 내부에서 안전하게 줄바꿈한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 48,
            child: WordSafeText(
              '가나다라마바사아자차카타파하',
              key: Key('long-word-safe-text'),
              style: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );

    final rendered = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byKey(const Key('long-word-safe-text')),
            matching: find.byType(RichText),
          ),
        )
        .single;
    expect(rendered.softWrap, isTrue);
    expect(rendered.maxLines, isNull);
    expect(rendered.overflow, TextOverflow.visible);
    final longText = find.byKey(const Key('long-word-safe-text'));
    final longRichText = find.descendant(
      of: longText,
      matching: find.byType(RichText),
    );
    expect(tester.getSize(longRichText).height, greaterThan(24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('singleLine은 점수·버튼처럼 명시한 예외에서만 native 동작을 쓴다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 48,
          child: WordSafeText(
            '한 줄 값',
            key: Key('single-line-safe-text'),
            singleLine: true,
            maxLines: 1,
          ),
        ),
      ),
    );

    final widget = tester.widget<WordSafeText>(
      find.byKey(const Key('single-line-safe-text')),
    );
    expect(widget.singleLine, isTrue);
    expect(widget.maxLines, 1);
  });
}

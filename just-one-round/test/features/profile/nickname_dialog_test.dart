import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/profile/presentation/nickname_dialog.dart';

void main() {
  testWidgets('닉네임은 2자 이상이어야 저장된다', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showNicknameDialog(context);
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nickname-field')), '별');
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pump();

    expect(find.text('2~12자로 입력해 주세요.'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byKey(const Key('nickname-field')), '별하나');
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pumpAndSettle();
    expect(result, '별하나');
  });
}

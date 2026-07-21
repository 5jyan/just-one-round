import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';

void main() {
  testWidgets('제한 시간이 끝나면 결과를 보여준다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          gameDuration: Duration(milliseconds: 100),
          countdownDuration: Duration.zero,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(find.text('한 판 종료!'), findsOneWidget);
    expect(find.byKey(const Key('final-score')), findsOneWidget);
    expect(find.text('홈으로'), findsOneWidget);
  });
}

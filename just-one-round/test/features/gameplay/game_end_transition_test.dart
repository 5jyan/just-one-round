import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/presentation/game_end_transition.dart';

void main() {
  for (final endType in GameEndType.values) {
    testWidgets('${endType.label}가 공통 종료 화면 상단에 표시된다', (tester) async {
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: GameEndTransition(
            endType: endType,
            onCompleted: () => completed = true,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('game-end-title')), findsOneWidget);
      expect(find.text(endType.label), findsNWidgets(2));
      expect(
        tester.getSize(find.byKey(const Key('game-end-backdrop'))),
        const Size(800, 600),
      );
      expect(
        tester.getCenter(find.byKey(const Key('game-end-title'))).dy,
        lessThan(150),
      );
      expect(completed, isFalse);

      await tester.pump(
        gameEndTransitionDuration + const Duration(milliseconds: 100),
      );

      expect(completed, isTrue);
    });
  }
}

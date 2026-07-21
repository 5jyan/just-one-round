import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';

void main() {
  testWidgets('오늘의 게임과 플레이 기회를 보여준다', (tester) async {
    await tester.pumpWidget(const JustOneRoundApp());

    expect(find.text('딱한판만'), findsOneWidget);
    expect(find.text('별빛 피하기'), findsOneWidget);
    expect(find.text('오늘의 한 판 시작'), findsOneWidget);
    expect(find.text('아직 플레이하지 않았어요 · 기회 1회'), findsOneWidget);
  });
}

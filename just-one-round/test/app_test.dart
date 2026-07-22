import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

void main() {
  testWidgets('오늘의 게임과 플레이 기회를 보여준다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('딱한판만'), findsOneWidget);
    expect(find.text('별빛 피하기'), findsOneWidget);
    expect(find.text('오늘의 한 판 시작'), findsOneWidget);
    expect(find.text('아직 플레이하지 않았어요 · 기회 1회'), findsOneWidget);
  });

  testWidgets('시작 버튼으로 게임 화면에 진입한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pumpAndSettle();

    final startButton = find.byType(PixelButton);
    await tester.ensureVisible(startButton);
    await tester.pump();
    await tester.tap(startButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('SURVIVE'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('화면을 좌우로 드래그하세요'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

void main() {
  testWidgets('빙글개굴 설명서는 조작·속도·점수·실패를 여섯 페이지로 안내한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            PreviewDailyGameRepository(initialGameId: 'lily_frog'),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('빙글개굴'), findsOneWidget);
    expect(
      find.byKey(const Key('lily-frog-home-runtime-preview')),
      findsOneWidget,
    );
    final guideButton = find.byKey(const Key('game-guide-button'));
    await tester.ensureVisible(guideButton);
    await tester.tap(guideButton);
    await tester.pump(const Duration(milliseconds: 500));

    final previous = tester.widget<OutlinedButton>(
      find.byKey(const Key('guide-previous-button')),
    );
    expect(previous.onPressed, isNull);

    const pages = [
      ('탭하면 90° 접선 점프', '점선을 따라 실제로'),
      ('점선은 처음 3번만', '4번째 점프부터'),
      ('갈수록 더 빨라져요', '한 바퀴 시간도'),
      ('착지 점수와 콤보', '콤보×10점'),
      ('황금 연잎과 파리 POP!', '각각 +100점'),
      ('150초 · 풍덩이면 끝', '앱을 닫아도'),
    ];
    for (var index = 0; index < pages.length; index++) {
      expect(find.text('HOW TO PLAY · ${index + 1}/6'), findsOneWidget);
      expect(find.text(pages[index].$1), findsOneWidget);
      expect(find.textContaining(pages[index].$2), findsOneWidget);
      expect(
        find.byKey(const Key('lily-frog-guide-runtime-preview')),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      if (index < pages.length - 1) {
        tester
            .widget<PixelButton>(find.byKey(const Key('guide-next-button')))
            .onPressed!();
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }
    }
    expect(find.text('설명 끝'), findsOneWidget);
  });
}

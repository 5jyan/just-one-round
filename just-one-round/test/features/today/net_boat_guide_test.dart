import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';
import 'package:just_one_round/features/games/net_boat/domain/net_boat_rules.dart';
import 'package:just_one_round/features/games/net_boat/presentation/net_boat_presentation.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

void main() {
  test('만선호 미리보기는 v3와 300초 TodayGame을 사용한다', () async {
    final state = await PreviewDailyGameRepository(
      initialGameId: 'net_boat',
    ).fetchToday();

    expect(state.game?.id, 'net_boat');
    expect(state.game?.version, NetBoatRules.rulesVersion);
    expect(state.game?.durationSeconds, NetBoatRules.gameDuration.inSeconds);
  });

  testWidgets('만선호 설명서는 조작·포획·실패·점수·그물 한계를 5쪽으로 안내한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            PreviewDailyGameRepository(initialGameId: 'net_boat'),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('만선호'), findsOneWidget);
    expect(netBoatPresentation.durationLabel, contains('300초'));
    expect(netBoatPresentation.guideDurationText, contains('300초'));
    expect(find.byKey(const Key('net-boat-preview-clip')), findsOneWidget);
    final guideButton = find.byKey(const Key('game-guide-button'));
    await tester.ensureVisible(guideButton);
    await tester.tap(guideButton);
    await tester.pump(const Duration(milliseconds: 500));

    final previous = tester.widget<OutlinedButton>(
      find.byKey(const Key('guide-previous-button')),
    );
    expect(previous.onPressed, isNull);

    const pages = [
      ('탭하면 오른쪽으로 90°', '무조건 오른쪽으로 정확히 90°'),
      ('그물로 사각형을 만들어요', '고래는 그물을 통과할 수 있어요'),
      ('정어리는 안전해요', '절대 게임이 끝나지 않아요'),
      ('물고기마다 점수가 달라요', '위협적이지 않아요'),
      ('그물 최대 길이는 1000', '1000에 닿으면'),
    ];
    for (var index = 0; index < pages.length; index++) {
      expect(find.text('HOW TO PLAY · ${index + 1}/5'), findsOneWidget);
      expect(find.text(pages[index].$1), findsOneWidget);
      expect(find.textContaining(pages[index].$2), findsOneWidget);
      expect(find.byKey(const Key('net-boat-preview-clip')), findsWidgets);
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
    expect(find.textContaining('그물 길이 800부터는 끊길 위험이 있고'), findsOneWidget);
    expect(find.text('설명 끝'), findsOneWidget);
  });

  testWidgets('작은 화면에서도 다섯 쪽 설명과 이동 버튼이 잘리지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            PreviewDailyGameRepository(initialGameId: 'net_boat'),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final guideButton = find.byKey(const Key('game-guide-button'));
    await tester.ensureVisible(guideButton);
    await tester.tap(guideButton);
    await tester.pump(const Duration(milliseconds: 500));

    for (var page = 1; page <= 5; page++) {
      expect(find.text('HOW TO PLAY · $page/5'), findsOneWidget);
      expect(find.byKey(const Key('guide-next-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (page < 5) {
        tester
            .widget<PixelButton>(find.byKey(const Key('guide-next-button')))
            .onPressed!();
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }
    }
  });
}

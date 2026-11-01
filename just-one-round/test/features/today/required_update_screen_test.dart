import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  testWidgets('일반 업데이트는 기존 안내와 스토어 버튼을 보여준다', (tester) async {
    final repository = PreviewDailyGameRepository(
      compatibility: const ClientCompatibility(
        currentBuild: 1,
        minimumSupportedBuild: 2,
        updateRequired: true,
        storeUrl: 'https://example.com/store',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('required-update-screen')), findsOneWidget);
    expect(find.text('게임이 업데이트 되었어요'), findsOneWidget);
    expect(find.text('원활한 게임 플레이를 위해\n앱을 업데이트 해주세요'), findsOneWidget);
    expect(find.text('스토어에서 업데이트'), findsOneWidget);
    expect(find.byKey(const Key('required-update-button')), findsOneWidget);
  });

  testWidgets('Alpha 빌드는 정식 버전 안내와 Google Play 버튼을 보여준다', (tester) async {
    final repository = PreviewDailyGameRepository(
      compatibility: const ClientCompatibility(
        currentBuild: 29,
        minimumSupportedBuild: 22,
        updateRequired: true,
        storeUrl: 'https://example.com/google-play',
        reason: 'production_release_required',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('required-update-screen')), findsOneWidget);
    expect(find.text('정식 버전으로 업데이트해 주세요'), findsOneWidget);
    expect(find.text('알파 테스트 대신 Google Play의 정식 버전을 이용해 주세요.'), findsOneWidget);
    expect(find.text('정식 버전 받기'), findsOneWidget);
    expect(find.text('게임이 업데이트 되었어요'), findsNothing);
    expect(find.text('스토어에서 업데이트'), findsNothing);
    expect(find.byKey(const Key('required-update-button')), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/level_up_reward.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/level_up_reward_dialog.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';

void main() {
  testWidgets('shows an aggregated level-up reward and acknowledges once', (
    tester,
  ) async {
    var acknowledgeCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLevelUpRewardDialog(
              context,
              reward: const LevelUpReward(
                userId: 'user-1',
                fromLevel: 4,
                toLevel: 6,
                challengeTickets: 2,
              ),
              onConfirm: () async => acknowledgeCalls++,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('level-up-reward-dialog')), findsOneWidget);
    expect(find.byKey(const Key('level-up-new-level')), findsOneWidget);
    expect(find.text('LV.4 → LV.6'), findsOneWidget);
    expect(find.text('도전권 +2장'), findsOneWidget);

    await tester.tap(find.byKey(const Key('level-up-reward-confirm')));
    await tester.pumpAndSettle();

    expect(acknowledgeCalls, 1);
    expect(find.byKey(const Key('level-up-reward-dialog')), findsNothing);
  });

  testWidgets('reduced motion starts in the final static state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: LevelUpRewardDialog(
            reward: const LevelUpReward(
              userId: 'user-1',
              fromLevel: 1,
              toLevel: 2,
              challengeTickets: 1,
            ),
            onConfirm: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    final customPaint = tester.widget<CustomPaint>(
      find.byKey(const Key('level-up-celebration')),
    );
    expect(customPaint.painter, isNotNull);
  });

  testWidgets(
    'TodayScreen only acknowledges the server pending reward on confirm',
    (tester) async {
      final repository = _PendingLevelUpRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dailyGameRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: TodayScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('level-up-reward-dialog')), findsOneWidget);
      expect(repository.acknowledgeCalls, 0);

      await tester.tap(find.byKey(const Key('level-up-reward-confirm')));
      await tester.pumpAndSettle();

      expect(repository.acknowledgeCalls, 1);
      expect(find.byKey(const Key('level-up-reward-dialog')), findsNothing);
    },
  );
  testWidgets('waits until startup is ready without polling rewards', (
    tester,
  ) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    final repository = _PendingLevelUpRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (_, value, child) =>
                LevelUpCelebrationGate(ready: value, child: child!),
            child: const TodayScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.fetchCalls, 0);
    expect(find.byKey(const Key('level-up-reward-dialog')), findsNothing);
    ready.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repository.fetchCalls, 1);
    expect(find.byKey(const Key('level-up-reward-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('level-up-reward-confirm')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.acknowledgeCalls, 1);
    expect(find.byKey(const Key('level-up-reward-dialog')), findsNothing);
  });

  testWidgets(
    'failed acknowledgement leaves the granted reward visible for retry',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpRewardDialog(
            reward: const LevelUpReward(
              userId: 'u',
              fromLevel: 1,
              toLevel: 2,
              challengeTickets: 1,
            ),
            onConfirm: () async {
              calls++;
              throw StateError('offline');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('level-up-reward-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('보상을 확인하지 못했어요. 잠시 후 다시 눌러 주세요.'), findsOneWidget);
      expect(find.text('도전권 +1장'), findsOneWidget);
      await tester.tap(find.byKey(const Key('level-up-reward-confirm')));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
}

class _PendingLevelUpRepository extends PreviewDailyGameRepository {
  _PendingLevelUpRepository()
    : super(
        initialEconomy: PlayerEconomy.fromTotals(
          coins: 0,
          experiencePoints: 100,
        ),
      );

  var acknowledgeCalls = 0;
  var fetchCalls = 0;

  @override
  Future<TodayState> fetchToday() async {
    final state = await super.fetchToday();
    return TodayState(
      playDate: state.playDate,
      game: state.game,
      attempts: state.attempts,
      adAttemptAvailable: state.adAttemptAvailable,
      testMode: state.testMode,
      result: state.result,
      nickname: state.nickname,
      economy: state.economy,
      levelRewardedThrough: 2,
      levelCelebrationSeenThrough: acknowledgeCalls == 0 ? 1 : 2,
    );
  }

  @override
  Future<LevelUpReward?> fetchPendingLevelUpReward() async {
    fetchCalls++;
    return const LevelUpReward(
      userId: 'preview-user',
      fromLevel: 1,
      toLevel: 2,
      challengeTickets: 1,
    );
  }

  @override
  Future<void> acknowledgeLevelUpReward({
    required int throughLevel,
    required String expectedUserId,
  }) async {
    acknowledgeCalls++;
    await super.acknowledgeLevelUpReward(
      throughLevel: throughLevel,
      expectedUserId: expectedUserId,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/daily_nonplayer.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  testWidgets('nonplayer directory is lazy and filters anonymous rows', (
    tester,
  ) async {
    final repository = _TrackingPreviewRepository();
    final nonplayers = _FakeDailyNonplayersRepository([
      const DailyNonplayersPage(
        players: [
          DailyNonplayer(
            userId: 'user-1',
            nickname: '  아직감자  ',
            nicknameColor: 'mint',
            level: 7,
          ),
          DailyNonplayer(
            userId: 'user-anonymous',
            nickname: '신원미상#42',
            nicknameColor: 'default',
            level: 2,
          ),
          DailyNonplayer(
            userId: 'user-blank',
            nickname: '   ',
            nicknameColor: 'default',
            level: 1,
          ),
        ],
        nextCursor: null,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(repository),
          dailyNonplayersRepositoryProvider.overrideWithValue(nonplayers),
        ],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(nonplayers.fetchCalls, 0);
    await tester.ensureVisible(find.byKey(const Key('ranking-button')));
    await tester.tap(find.byKey(const Key('ranking-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-nonplayers-button')), findsOneWidget);
    expect(nonplayers.fetchCalls, 0);

    await tester.tap(find.byKey(const Key('daily-nonplayers-button')));
    await tester.pumpAndSettle();

    expect(nonplayers.fetchCalls, 1);
    expect(find.byKey(const Key('daily-nonplayer-user-1')), findsOneWidget);
    expect(find.text('아직감자'), findsOneWidget);
    expect(find.text('신원미상#42'), findsNothing);
    expect(find.text('LV.7'), findsOneWidget);
    expect(
      find.byKey(const Key('daily-nonplayer-more-user-1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'nonplayer cursor pagination keeps rows and retries a failed page',
    (tester) async {
      final nonplayers = _FakeDailyNonplayersRepository([
        const DailyNonplayersPage(
          players: [
            DailyNonplayer(
              userId: 'user-1',
              nickname: '첫 번째',
              nicknameColor: 'default',
              level: 1,
            ),
          ],
          nextCursor: 'cursor-1',
        ),
        StateError('page failed'),
        const DailyNonplayersPage(
          players: [
            DailyNonplayer(
              userId: 'user-1',
              nickname: '첫 번째',
              nicknameColor: 'default',
              level: 1,
            ),
            DailyNonplayer(
              userId: 'user-2',
              nickname: '두 번째',
              nicknameColor: 'blue',
              level: 3,
            ),
          ],
          nextCursor: null,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dailyNonplayersRepositoryProvider.overrideWithValue(nonplayers),
          ],
          child: const JustOneRoundApp(),
        ),
      );
      await tester.pumpAndSettle();
      await _openNonplayers(tester);

      expect(find.byKey(const Key('daily-nonplayer-user-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('daily-nonplayers-more-button')));
      await tester.pumpAndSettle();
      expect(nonplayers.fetchCalls, 2);
      expect(find.byKey(const Key('daily-nonplayer-user-1')), findsOneWidget);
      expect(
        find.byKey(const Key('daily-nonplayers-more-retry')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('daily-nonplayers-more-retry')));
      await tester.pumpAndSettle();
      expect(nonplayers.fetchCalls, 3);
      expect(find.byKey(const Key('daily-nonplayer-user-1')), findsOneWidget);
      expect(find.byKey(const Key('daily-nonplayer-user-2')), findsOneWidget);
      expect(
        find.byKey(const Key('daily-nonplayers-more-button')),
        findsNothing,
      );
    },
  );

  testWidgets('nonplayer actions send the displayed target identity', (
    tester,
  ) async {
    final repository = _TrackingPreviewRepository(
      initialEconomy: PlayerEconomy.fromTotals(
        coins: 1000,
        experiencePoints: 0,
      ),
    );
    await repository.purchaseShopItem(
      itemId: 'practice_ticket',
      requestId: 'nonplayer-action-test',
    );
    final nonplayers = _FakeDailyNonplayersRepository([
      const DailyNonplayersPage(
        players: [
          DailyNonplayer(
            userId: 'target-user',
            nickname: '관전감자',
            nicknameColor: 'mint',
            level: 4,
          ),
        ],
        nextCursor: null,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(repository),
          dailyNonplayersRepositoryProvider.overrideWithValue(nonplayers),
        ],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();
    await _openNonplayers(tester);

    await tester.tap(find.byKey(const Key('daily-nonplayer-more-target-user')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rank-action-poke')));
    await tester.pumpAndSettle();
    expect(repository.socialActions, [('target-user', 'poke')]);
    await tester.tap(find.byKey(const Key('social-poke-completed-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('daily-nonplayer-more-target-user')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rank-action-gift')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('연습권 1장'));
    await tester.pumpAndSettle();
    expect(repository.gifts, [('target-user', 'practice_ticket')]);
  });

  testWidgets('directory button remains available with an empty ranking', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            _EmptyRankingRepository(),
          ),
          dailyNonplayersRepositoryProvider.overrideWithValue(
            _FakeDailyNonplayersRepository([
              const DailyNonplayersPage(players: [], nextCursor: null),
            ]),
          ),
        ],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ranking-button')));
    await tester.tap(find.byKey(const Key('ranking-button')));
    await tester.pumpAndSettle();

    expect(find.text('아직 등록된 기록이 없어요.'), findsOneWidget);
    expect(find.byKey(const Key('daily-nonplayers-button')), findsOneWidget);
  });
}

Future<void> _openNonplayers(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('ranking-button')));
  await tester.tap(find.byKey(const Key('ranking-button')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('daily-nonplayers-button')));
  await tester.tap(find.byKey(const Key('daily-nonplayers-button')));
  await tester.pumpAndSettle();
}

class _FakeDailyNonplayersRepository implements DailyNonplayersRepository {
  _FakeDailyNonplayersRepository(this.responses);

  final List<Object> responses;
  var fetchCalls = 0;

  @override
  Future<DailyNonplayersPage> fetchDailyNonplayers({
    required DateTime playDate,
    required String gameId,
    String? afterUserId,
  }) async {
    fetchCalls++;
    final response = responses.removeAt(0);
    if (response is DailyNonplayersPage) return response;
    throw response;
  }
}

class _TrackingPreviewRepository extends PreviewDailyGameRepository {
  _TrackingPreviewRepository({super.initialEconomy});

  final socialActions = <(String, String)>[];
  final gifts = <(String, String)>[];

  @override
  Future<void> sendSocialAction({
    required String targetUserId,
    required String action,
  }) async {
    socialActions.add((targetUserId, action));
  }

  @override
  Future<void> giftShopItem({
    required String targetUserId,
    required String itemId,
  }) async {
    gifts.add((targetUserId, itemId));
  }
}

class _EmptyRankingRepository extends PreviewDailyGameRepository {
  @override
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) async =>
      const DailyRankResult(
        score: null,
        rank: null,
        participants: 0,
        topPercent: null,
        nickname: null,
        nearby: [],
        leaders: [],
      );
}

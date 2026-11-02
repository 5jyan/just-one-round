import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/features/duels/data/duel_repository.dart';
import 'package:just_one_round/features/duels/domain/duel_state.dart';
import 'package:just_one_round/features/duels/presentation/duel_lobby_screen.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

void main() {
  testWidgets('lobby cannot create a duel even with local test opponents', (
    tester,
  ) async {
    final repository = _TestDuelRepository(
      testPlayers: const [
        DuelTestPlayer(
          userId: 'test-opponent',
          nickname: '시뮬 상대',
          testGameId: 'dung_dodge_v2',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelRepositoryProvider.overrideWithValue(repository),
          _todayStateOverride(coins: 100),
        ],
        child: const MaterialApp(home: DuelLobbyScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('테스트 상대'), findsNothing);
    expect(find.text('대결방 만들기'), findsNothing);
    expect(find.textContaining('랭킹에서 상대를 선택해'), findsOneWidget);
  });

  testWidgets(
    'keeps the normal ranking guidance when server returns no test players',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duelRepositoryProvider.overrideWithValue(_TestDuelRepository()),
            _todayStateOverride(coins: 100),
          ],
          child: const MaterialApp(home: DuelLobbyScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('랭킹에서 상대를 선택해'), findsOneWidget);
      expect(find.text('테스트 상대'), findsNothing);
    },
  );

  testWidgets('blocks creating a duel when the wallet has zero coins', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelRepositoryProvider.overrideWithValue(
            _TestDuelRepository(
              testPlayers: [
                DuelTestPlayer(userId: 'test-opponent', nickname: '시뮬 상대'),
              ],
            ),
          ),
          _todayStateOverride(coins: 0),
        ],
        child: const MaterialApp(
          home: DuelLobbyScreen(
            initialOpponentUserId: 'test-opponent',
            initialOpponentNickname: '시뮬 상대',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('보유 코인 0 · 최소 10코인이 필요해요.'), findsOneWidget);
    final createButton = tester.widget<PixelButton>(
      find.byType(PixelButton).last,
    );
    expect(createButton.onPressed, isNull);
  });

  testWidgets('shows the create form for an opponent selected in ranking', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelRepositoryProvider.overrideWithValue(_TestDuelRepository()),
          _todayStateOverride(coins: 100),
        ],
        child: const MaterialApp(
          home: DuelLobbyScreen(
            initialOpponentUserId: 'ranked-opponent',
            initialOpponentNickname: '랭킹 상대',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('랭킹 상대님에게 방을 만들어요.'), findsOneWidget);
    expect(find.text('대결방 만들기'), findsOneWidget);
  });

  testWidgets('opens a settled row as a read-only result room', (tester) async {
    final repository = _TestDuelRepository(matches: [_settledMatch()]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelRepositoryProvider.overrideWithValue(repository),
          _todayStateOverride(coins: 100),
        ],
        child: const MaterialApp(home: DuelLobbyScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('결과 보기'));
    await tester.pumpAndSettle();

    expect(find.text('대결 결과'), findsOneWidget);
    expect(repository.joinCalls, 0);
  });

  testWidgets('refreshes the wallet after returning from a settled room', (
    tester,
  ) async {
    final repository = _TestDuelRepository(
      matches: [_settledMatch()],
      testPlayers: const [
        DuelTestPlayer(userId: 'test-opponent', nickname: '시뮬 상대'),
      ],
    );
    var walletFetches = 0;
    final walletOverride = todayStateProvider.overrideWith((ref) async {
      final coins = walletFetches++ == 0 ? 200 : 100;
      return _todayState(coins: coins);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelRepositoryProvider.overrideWithValue(repository),
          walletOverride,
        ],
        child: const MaterialApp(
          home: DuelLobbyScreen(
            initialOpponentUserId: 'test-opponent',
            initialOpponentNickname: '시뮬 상대',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('보유 코인 200 · 최대 200코인까지 걸 수 있어요.'), findsOneWidget);

    await tester.tap(find.text('결과 보기'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('대결 결과'))).pop();
    await tester.pumpAndSettle();

    expect(walletFetches, greaterThanOrEqualTo(2));
    expect(find.text('보유 코인 100 · 최대 100코인까지 걸 수 있어요.'), findsOneWidget);
  });

  testWidgets('keeps dropdown values valid after a room-return refresh', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duelRepositoryProvider.overrideWithValue(
            _TestDuelRepository(
              testPlayers: const [
                DuelTestPlayer(userId: 'test-opponent', nickname: '시뮬 상대'),
              ],
            ),
          ),
          _todayStateOverride(coins: 100),
        ],
        child: const MaterialApp(
          home: DuelLobbyScreen(
            initialOpponentUserId: 'test-opponent',
            initialOpponentNickname: '시뮬 상대',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, 260));
    await tester.pumpAndSettle();

    expect(find.text('시뮬 상대님에게 방을 만들어요.'), findsOneWidget);
    expect(find.text('똥피하기'), findsOneWidget);
  });
}

dynamic _todayStateOverride({required int coins}) =>
    todayStateProvider.overrideWith((ref) async => _todayState(coins: coins));

TodayState _todayState({required int coins}) => TodayState(
  playDate: DateTime.utc(2026, 11, 2),
  game: null,
  attempts: const [],
  adAttemptAvailable: false,
  testMode: true,
  result: null,
  nickname: 'tester',
  economy: PlayerEconomy.fromTotals(coins: coins, experiencePoints: 0),
);

class _TestDuelRepository extends NoopDuelRepository {
  _TestDuelRepository({this.testPlayers = const [], this.matches = const []});

  final List<DuelTestPlayer> testPlayers;
  final List<DuelMatch> matches;
  int joinCalls = 0;

  @override
  Future<DuelOptions> fetchDuelOptions() async => const DuelOptions(
    games: [
      DuelGameOption(id: 'dung_dodge_v2', displayName: '똥피하기', version: 1),
    ],
    minStake: 10,
    maxStake: 200,
    stakeStep: 10,
    defaultStake: 100,
  );

  @override
  Future<List<DuelTestPlayer>> fetchDuelTestPlayers() async => testPlayers
      .map(
        (player) => DuelTestPlayer(
          userId: player.userId,
          nickname: player.nickname,
          testGameId: player.testGameId,
        ),
      )
      .toList(growable: false);

  @override
  Future<List<DuelMatch>> fetchDuels() async => matches;

  @override
  Future<DuelMatch> fetchDuel(String matchId) async =>
      matches.firstWhere((match) => match.id == matchId);

  @override
  Future<DuelMatch> joinDuel(
    String matchId, {
    String? deviceSessionId,
    String? clientRuntimeRevision,
  }) async {
    joinCalls++;
    return fetchDuel(matchId);
  }
}

DuelMatch _settledMatch() => DuelMatch.fromJson({
  'id': 'settled-1',
  'requester_id': 'me',
  'opponent_id': 'other',
  'game_id': 'number_rush',
  'game_name': '탭50',
  'game_version': 1,
  'stake': 100,
  'status': 'settled',
  'outcome': 'requester_win',
  'winner_id': 'me',
  'created_at': '2026-11-02T00:00:00Z',
  'waiting_expires_at': '2026-11-02T00:10:00Z',
  'runs': [
    {'user_id': 'me', 'raw_score': 90, 'joined': true},
    {'user_id': 'other', 'raw_score': 70, 'joined': true},
  ],
});

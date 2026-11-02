import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/game.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/features/gameplay/data/duel_runtime_launch_guard.dart';
import 'package:just_one_round/features/gameplay/domain/duel_play_context.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/presentation/game_end_transition.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';

void main() {
  testWidgets('a duel entry past the grace window forfeits instead of replaying the run', (
    tester,
  ) async {
    var forfeits = 0;
    final context = _duelContext(
      startAt: DateTime.now().toUtc().subtract(const Duration(seconds: 6)),
      forfeit: () async => forfeits++,
    );
    final router = _router(context);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    // A late run is rejected as soon as Flame finishes loading. Capture the
    // game before the rejection can navigate the route home.
    final gameFinder = find.byWidgetPredicate((widget) => widget is GameWidget);
    final gameWidget = tester.widget<GameWidget>(gameFinder);
    final game = gameWidget.game;
    if (game is! FlameGame) {
      throw StateError('Expected GameScreen to host a FlameGame');
    }
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.runAsync(() => game.loaded);
    await tester.pump();
    await _pumpUntil(tester, () => forfeits > 0);

    expect(forfeits, 1);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byKey(const Key('game-exit-warning-title')), findsNothing);
  });

  testWidgets('backgrounding a duel forfeits and never offers resume', (
    tester,
  ) async {
    var forfeits = 0;
    final launchStore = InMemoryDuelRuntimeLaunchStore();
    final context = _duelContext(
      startAt: DateTime.now().toUtc().add(const Duration(seconds: 30)),
      forfeit: () async => forfeits++,
    );
    final router = _router(context, launchStore: launchStore);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _pumpUntil(tester, () => forfeits > 0);

    expect(forfeits, 1);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(launchStore.claimedRunKeys, {'match-runtime-test:run-runtime-test'});
    expect(find.byKey(const Key('game-exit-warning-title')), findsNothing);
  });

  testWidgets('duel result home unwinds the imperative game route', (
    tester,
  ) async {
    var submissions = 0;
    final context = _duelContext(
      startAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
      gameDuration: const Duration(milliseconds: 100),
      submitResult: (_) async => submissions++,
      forfeit: () async {},
    );
    final nestedNavigatorKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Navigator(
            key: nestedNavigatorKey,
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Material(child: Text('home')),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    final navigator = nestedNavigatorKey.currentState!;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          duelContext: context,
          duelLaunchGuard: DuelRuntimeLaunchGuard(
            store: InMemoryDuelRuntimeLaunchStore(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(GameScreen), findsOneWidget);
    await _waitForFlameGameLoaded(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    await tester.pump();
    await _pumpUntil(tester, () => submissions > 0);
    await tester.pump(gameEndTransitionDuration + const Duration(milliseconds: 100));
    await tester.pump(gameEndResultRevealDuration);

    expect(find.byKey(const Key('duel-result-room-button')), findsOneWidget);
    expect(find.text('홈으로'), findsOneWidget);
    await tester.tap(find.text('홈으로'));
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });
}

DuelPlayContext _duelContext({
  required DateTime startAt,
  required Future<void> Function() forfeit,
  Duration gameDuration = const Duration(seconds: 60),
  Future<void> Function(GameResult result)? submitResult,
}) => DuelPlayContext(
  matchId: 'match-runtime-test',
  runId: 'run-runtime-test',
  gameId: 'dung_dodge_v2',
  gameVersion: 1,
  challengeSeed: 42,
  startAt: startAt,
  gameDuration: gameDuration,
  submitResult: submitResult,
  forfeit: forfeit,
);

GoRouter _router(
  DuelPlayContext duel, {
  InMemoryDuelRuntimeLaunchStore? launchStore,
}) => GoRouter(
  initialLocation: '/play',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Material(child: Text('home')),
    ),
    GoRoute(
      path: '/play',
      builder: (context, state) => GameScreen(
        duelContext: duel,
        duelLaunchGuard: DuelRuntimeLaunchGuard(
          store: launchStore ?? InMemoryDuelRuntimeLaunchStore(),
        ),
      ),
    ),
  ],
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 100; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) return;
  }
  throw TestFailure('Timed out waiting for condition');
}

Future<void> _waitForFlameGameLoaded(WidgetTester tester) async {
  final gameFinder = find.byWidgetPredicate((widget) => widget is GameWidget);
  final gameWidget = tester.widget<GameWidget>(gameFinder);
  final game = gameWidget.game;
  if (game is! FlameGame) {
    throw StateError('Expected GameScreen to host a FlameGame');
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  await tester.runAsync(() => game.loaded);
  await tester.pump();
}

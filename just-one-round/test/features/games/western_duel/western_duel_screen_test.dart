import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/games/western_duel/western_duel_game.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  testWidgets(
    'western guide starts a first-person duel with a fixed bot fallback',
    (tester) async {
      tester.view
        ..physicalSize = const Size(360, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const attempt = PlayAttempt(
        id: 'western-practice',
        ordinal: 1,
        status: 'practice',
        grantType: 'practice',
        gameId: 'western_duel',
        gameVersion: 1,
      );
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: GameScreen(attempt: attempt)),
        ),
      );
      for (
        var i = 0;
        i < 100 &&
            find.byKey(const Key('game-start-guide-button')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byKey(const Key('game-start-guide-button')), findsOneWidget);
      expect(find.textContaining('DRAW!'), findsOneWidget);
      await tester.tap(find.byKey(const Key('game-start-guide-button')));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.byKey(const Key('game-start-guide')), findsNothing);
      final game =
          tester
                  .widget<GameWidget>(
                    find.byWidgetPredicate((widget) => widget is GameWidget),
                  )
                  .game
              as WesternDuelGame;
      expect(game.opponent?.isBot, isTrue);
      expect(game.opponent?.reactionMilliseconds, 440);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/wind_darts_game.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';

void main() {
  test(
    'developer preview selects wind darts and resolves its runtime',
    () async {
      final repository = PreviewDailyGameRepository(
        testMode: true,
        initialGameId: 'wind_darts',
      );
      final games = await repository.fetchDeveloperGames();
      final selected = await repository.fetchToday();
      expect(games.any((game) => game.id == 'wind_darts'), isTrue);
      expect(selected.game?.id, 'wind_darts');

      expect(
        GameRegistry.supports('wind_darts', WindDartsRules.rulesVersion),
        isTrue,
      );
      expect(
        GameRegistry.forId('wind_darts').hudStyle,
        MiniGameHudStyle.custom,
      );
      expect(
        GameRegistry.forId('wind_darts').playingInstruction,
        contains('7발'),
      );
      expect(
        GameRegistry.forId('wind_darts').playingInstruction,
        contains('황금'),
      );
      expect(GameRegistry.forId('wind_darts').resultUnitLabel, '7발 합계 점수');
      expect(WindDartsRules.maximumScore, 480);
      final controller = GameRegistry.forId('wind_darts').create(
        gameDuration: WindDartsRules.gameDuration,
        countdownDuration: Duration.zero,
        attemptOrdinal: 1,
        challengeSeed: 42,
        onFinished: (_) {},
      );
      expect(controller, isA<WindDartsGame>());
      expect(controller.hud.value.phase, MiniGamePhase.countdown);
      controller.disposeController();
    },
  );
}

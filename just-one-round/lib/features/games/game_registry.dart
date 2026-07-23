import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/apple_game/apple_game.dart';
import 'package:just_one_round/features/games/apple_game/domain/apple_game_rules.dart';
import 'package:just_one_round/features/games/failed_bakery/domain/failed_bakery_rules.dart';
import 'package:just_one_round/features/games/failed_bakery/failed_bakery_game.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';
import 'package:just_one_round/features/games/gravity_switch/gravity_switch_game.dart';
import 'package:just_one_round/features/games/star_dodge/domain/star_dodge_rules.dart';
import 'package:just_one_round/features/games/star_dodge/star_dodge_game.dart';

abstract final class GameRegistry {
  static const fallbackGameId = 'dung_dodge';

  static final _definitions = <String, MiniGameDefinition>{
    fallbackGameId: MiniGameDefinition(
      id: fallbackGameId,
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required onFinished,
          }) => StarDodgeGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            onFinished: onFinished,
          ),
      countdownInstruction: '화면을 좌우로 드래그하세요',
      playingInstruction: '떨어지는 똥을 피하세요! · 충돌하면 종료',
      scoreLabel: 'SURVIVAL TIME',
      formatScore: StarDodgeRules.formatSurvival,
    ),
    'gravity_switch': MiniGameDefinition(
      id: 'gravity_switch',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required onFinished,
          }) => GravitySwitchGame(
            countdownDuration: countdownDuration,
            onFinished: onFinished,
          ),
      countdownInstruction: '탭해서 중력을 뒤집고 반대편으로 이동하세요',
      playingInstruction: '돌출 기둥이 오기 전에 중력을 뒤집으세요!',
      scoreLabel: 'SURVIVAL TIME',
      formatScore: GravitySwitchRules.formatSurvival,
      hudStyle: MiniGameHudStyle.gravitySwitch,
    ),
    'failed_bakery': MiniGameDefinition(
      id: 'failed_bakery',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required onFinished,
          }) => FailedBakeryGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            onFinished: onFinished,
          ),
      countdownInstruction: '움직이는 케이크가 겹칠 때 탭하세요',
      playingInstruction: '어긋난 부분은 잘려요 · 3연속 퍼펙트면 크기 회복!',
      scoreLabel: 'CAKE TOWER',
      formatScore: FailedBakeryRules.formatLayers,
      hudStyle: MiniGameHudStyle.failedBakery,
      resultUnitLabel: '쌓은 케이크 층',
    ),
    'apple_game': MiniGameDefinition(
      id: 'apple_game',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required onFinished,
          }) => AppleGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            onFinished: onFinished,
          ),
      countdownInstruction: '드래그한 사과 숫자의 합을 10으로 만드세요',
      playingInstruction: '합이 10이면 제거 · 많이 묶을수록 고득점!',
      scoreLabel: 'APPLES',
      formatScore: AppleGameRules.formatApples,
      defaultDuration: const Duration(seconds: 120),
      hudStyle: MiniGameHudStyle.appleGame,
      resultUnitLabel: '제거한 사과',
    ),
  };

  static MiniGameDefinition forId(String? id) =>
      _definitions[id] ?? _definitions[fallbackGameId]!;

  static String formatScore(String? gameId, int score) =>
      forId(gameId).formatScore(score);
}

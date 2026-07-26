import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/apple_game/apple_game.dart';
import 'package:just_one_round/features/games/apple_game/domain/apple_game_rules.dart';
import 'package:just_one_round/features/games/failed_bakery/domain/failed_bakery_rules.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';
import 'package:just_one_round/features/games/gravity_switch/gravity_switch_game.dart';
import 'package:just_one_round/features/games/number_rush/domain/number_rush_rules.dart';
import 'package:just_one_round/features/games/number_rush/number_rush_game.dart';
import 'package:just_one_round/features/games/star_dodge/domain/star_dodge_rules.dart';
import 'package:just_one_round/features/games/star_dodge/star_dodge_game.dart';

abstract final class GameRegistry {
  static final _definitions = <String, MiniGameDefinition>{
    'dung_dodge_v2': MiniGameDefinition(
      id: 'dung_dodge_v2',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required onFinished,
          }) => StarDodgeGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            assetSet: StarDodgeAssetSet.uglyCute,
            onFinished: onFinished,
          ),
      countdownInstruction: '화면을 좌우로 드래그하세요',
      playingInstruction: '떨어지는 똥을 피하세요! · 충돌하면 종료',
      scoreLabel: 'SURVIVAL TIME',
      formatScore: StarDodgeRules.formatSurvival,
      defaultDuration: const Duration(minutes: 5),
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
    'apple_game_v2': MiniGameDefinition(
      id: 'apple_game_v2',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required onFinished,
          }) => AppleGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            assetSet: AppleGameAssetSet.midnightOrchard,
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
    'number_rush': MiniGameDefinition(
      id: 'number_rush',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required onFinished,
          }) => NumberRushGame(
            countdownDuration: countdownDuration,
            maxDuration: gameDuration,
            onFinished: onFinished,
          ),
      countdownInstruction: '1부터 50까지 순서대로 터치하세요',
      playingInstruction: '틀려도 멈추지 않아요 · 최대한 빠르게!',
      scoreLabel: 'CLEAR TIME',
      formatScore: NumberRushRules.formatRankingScore,
      defaultDuration: const Duration(minutes: 3),
      hudStyle: MiniGameHudStyle.numberRush,
      resultUnitLabel: '기록 시간 · 최대 3분',
    ),
  };

  static const _supportedVersions = <String, int>{
    'dung_dodge_v2': 1,
    'gravity_switch': 1,
    'apple_game_v2': 1,
    'number_rush': 1,
  };

  static MiniGameDefinition? tryForId(String? id) => _definitions[id];

  static MiniGameDefinition forId(String? id) =>
      tryForId(id) ??
      (throw UnsupportedError('Unsupported game id: ${id ?? '(null)'}'));

  static bool supports(String? id, int? version) =>
      id != null &&
      version != null &&
      _definitions.containsKey(id) &&
      _supportedVersions[id] == version;

  static Set<String> get registeredIds => Set.unmodifiable(_definitions.keys);

  static String formatScore(String? gameId, int score) => switch (gameId) {
    'failed_bakery' => FailedBakeryRules.formatLayers(score),
    'apple_game' => AppleGameRules.formatApples(score),
    'star_dodge' || 'dung_dodge' => StarDodgeRules.formatSurvival(score),
    _ => forId(gameId).formatScore(score),
  };
}

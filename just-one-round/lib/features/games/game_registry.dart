import 'dart:math';

import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/beat_the_dealer/beat_the_dealer_game.dart';
import 'package:just_one_round/features/games/beat_the_dealer/domain/beat_the_dealer_rules.dart';
import 'package:just_one_round/features/games/apple_game_v2/apple_game_v2.dart';
import 'package:just_one_round/features/games/apple_game_v2/domain/apple_game_v2_rules.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/domain/dung_dodge_v2_rules.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/dung_dodge_v2_game.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';
import 'package:just_one_round/features/games/gravity_switch/gravity_switch_game.dart';
import 'package:just_one_round/features/games/mama_duck_trail/domain/mama_duck_trail_rules.dart';
import 'package:just_one_round/features/games/mama_duck_trail/mama_duck_trail_game.dart';
import 'package:just_one_round/features/games/number_rush/domain/number_rush_rules.dart';
import 'package:just_one_round/features/games/number_rush/number_rush_game.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/midnight_snake/midnight_snake_game.dart';
import 'package:just_one_round/features/games/sausage_dachshund/domain/sausage_dachshund_rules.dart';

abstract final class GameRegistry {
  static final _definitions = <String, MiniGameDefinition>{
    'dung_dodge_v2': MiniGameDefinition(
      id: 'dung_dodge_v2',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => DungDodgeV2Game(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            random: Random(challengeSeed),
            onFinished: onFinished,
          ),
      countdownInstruction: '화면을 좌우로 드래그하세요',
      playingInstruction: '떨어지는 똥을 피하세요! · 충돌하면 종료',
      scoreLabel: 'SURVIVAL TIME',
      formatScore: DungDodgeV2Rules.formatSurvival,
      hudScoreFormatter: DungDodgeV2Rules.formatHudTime,
      defaultDuration: const Duration(minutes: 5),
      hudStyle: MiniGameHudStyle.survivalTime,
    ),
    'gravity_switch': MiniGameDefinition(
      id: 'gravity_switch',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => GravitySwitchGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            random: Random(challengeSeed),
            onFinished: onFinished,
          ),
      countdownInstruction: '탭해서 중력을 뒤집고 반대편으로 이동하세요',
      playingInstruction: '돌출 기둥이 오기 전에 중력을 뒤집으세요!',
      scoreLabel: 'SURVIVAL TIME',
      formatScore: GravitySwitchRules.formatSurvival,
      hudScoreFormatter: GravitySwitchRules.formatHudTime,
      defaultDuration: GravitySwitchRules.gameDuration,
      hudStyle: MiniGameHudStyle.survivalTime,
    ),
    'apple_game_v2': MiniGameDefinition(
      id: 'apple_game_v2',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => AppleGameV2(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            assetSet: AppleGameV2AssetSet.midnightOrchard,
            random: Random(challengeSeed),
            onFinished: onFinished,
          ),
      countdownInstruction: '드래그한 사과 숫자의 합을 10으로 만드세요',
      playingInstruction: '합이 10이면 제거 · 많이 묶을수록 고득점!',
      scoreLabel: 'APPLES',
      formatScore: AppleGameV2Rules.formatApples,
      defaultDuration: AppleGameV2Rules.gameDuration,
      hudStyle: MiniGameHudStyle.appleGame,
      resultUnitLabel: '제거한 사과',
    ),
    'number_rush': MiniGameDefinition(
      id: 'number_rush',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => NumberRushGame(
            countdownDuration: countdownDuration,
            maxDuration: gameDuration,
            random: Random(challengeSeed),
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
    'mama_duck_trail': MiniGameDefinition(
      id: 'mama_duck_trail',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => MamaDuckTrailGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            random: Random(challengeSeed),
            onFinished: onFinished,
          ),
      countdownInstruction: '엄마 오리의 발자국을 기억하세요',
      playingInstruction: '사라진 길을 출발점부터 드래그하세요!',
      scoreLabel: 'TRAIL SCORE',
      formatScore: MamaDuckTrailRules.formatScore,
      hudScoreFormatter: MamaDuckTrailRules.formatHudScore,
      defaultDuration: MamaDuckTrailRules.gameDuration,
      hudStyle: MiniGameHudStyle.mamaDuckTrail,
      resultUnitLabel: '완성 경로 점수',
    ),
    'midnight_snake': MiniGameDefinition(
      id: 'midnight_snake',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => MidnightSnakeGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            random: Random(challengeSeed),
            onFinished: onFinished,
          ),
      countdownInstruction: '상하좌우로 스와이프해 방향을 바꾸세요',
      playingInstruction: '야식을 먹고 몸과 벽을 피하세요!',
      scoreLabel: 'MIDNIGHT SNACKS',
      formatScore: MidnightSnakeRules.formatScore,
      hudScoreFormatter: MidnightSnakeRules.formatHudScore,
      defaultDuration: MidnightSnakeRules.gameDuration,
      resultUnitLabel: '먹은 야식',
    ),
    'beat_the_dealer': MiniGameDefinition(
      id: 'beat_the_dealer',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => BeatTheDealerGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            attemptOrdinal: attemptOrdinal,
            challengeSeed: challengeSeed,
            onFinished: onFinished,
          ),
      countdownInstruction: '딜러 공개 카드를 보고 코인을 거세요',
      playingInstruction: '21에 가깝게 · 한 장 더 또는 멈추기',
      scoreLabel: 'COINS',
      formatScore: BeatTheDealerRules.formatScore,
      defaultDuration: BeatTheDealerRules.gameDuration,
      hudStyle: MiniGameHudStyle.beatTheDealer,
      resultUnitLabel: '최종 보유 코인',
    ),
  };

  static const _supportedVersions = <String, int>{
    'dung_dodge_v2': 1,
    'gravity_switch': 1,
    'apple_game_v2': 1,
    'number_rush': 1,
    'mama_duck_trail': 1,
    'midnight_snake': MidnightSnakeRules.rulesVersion,
    'beat_the_dealer': BeatTheDealerRules.rulesVersion,
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
    // Historical records can outlive a removed game implementation.
    'failed_bakery' => '$score층',
    'apple_game' => AppleGameV2Rules.formatApples(score),
    'star_dodge' || 'dung_dodge' => DungDodgeV2Rules.formatSurvival(score),
    'sausage_dachshund' => SausageDachshundRules.formatScore(score),
    _ => forId(gameId).formatScore(score),
  };
}

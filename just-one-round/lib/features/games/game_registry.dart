import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/beat_the_dealer/beat_the_dealer_game.dart';
import 'package:just_one_round/features/games/beat_the_dealer/domain/beat_the_dealer_rules.dart';
import 'package:just_one_round/features/games/bathhouse_sort/bathhouse_sort_game.dart';
import 'package:just_one_round/features/games/bathhouse_sort/domain/bathhouse_sort_rules.dart';
import 'package:just_one_round/features/games/apple_game_v2/apple_game_v2.dart';
import 'package:just_one_round/features/games/apple_game_v2/domain/apple_game_v2_rules.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/domain/dung_dodge_v2_rules.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/dung_dodge_v2_game.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';
import 'package:just_one_round/features/games/gravity_switch/gravity_switch_game.dart';
import 'package:just_one_round/features/games/lily_frog/domain/lily_frog_rules.dart';
import 'package:just_one_round/features/games/lily_frog/lily_frog_game.dart';
import 'package:just_one_round/features/games/mama_duck_trail/domain/mama_duck_trail_rules.dart';
import 'package:just_one_round/features/games/mama_duck_trail/mama_duck_trail_game.dart';
import 'package:just_one_round/features/games/net_boat/domain/net_boat_rules.dart';
import 'package:just_one_round/features/games/net_boat/net_boat_game.dart';
import 'package:just_one_round/features/games/number_rush/domain/number_rush_rules.dart';
import 'package:just_one_round/features/games/number_rush/number_rush_game.dart';
import 'package:just_one_round/features/games/mole_reaction/domain/mole_reaction_rules.dart';
import 'package:just_one_round/features/games/mole_reaction/mole_reaction_game.dart';
import 'package:just_one_round/features/games/western_duel/domain/western_duel_rules.dart';
import 'package:just_one_round/features/games/western_duel/western_duel_game.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/wind_darts_game.dart';
import 'package:just_one_round/features/games/ramen_timer/domain/ramen_timer_rules.dart';
import 'package:just_one_round/features/games/ramen_timer/ramen_timer_game.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/midnight_snake/midnight_snake_game.dart';
import 'package:just_one_round/features/games/sausage_dachshund/domain/sausage_dachshund_rules.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/domain/ten_pitch_slugger_rules.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/ten_pitch_slugger_game.dart';

const _gravitySwitchStartSeconds = int.fromEnvironment(
  'GRAVITY_SWITCH_START_SECONDS',
  defaultValue: 0,
);

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
      startInstruction: '손가락을 움직인 만큼 캐릭터를 좌우로 옮겨 떨어지는 똥을 피하세요!',
      countdownInstruction: '손가락을 움직인 만큼 캐릭터가 좌우로 따라가요',
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
            captureConfig:
                (kDebugMode || kProfileMode) && _gravitySwitchStartSeconds > 0
                ? GravitySwitchCaptureConfig(
                    initialElapsedSeconds: _gravitySwitchStartSeconds
                        .toDouble(),
                  )
                : null,
            random: Random(challengeSeed),
            onFinished: onFinished,
          ),
      startInstruction: '벽에 박지 않도록 화면을 탭해 중력을 뒤집으세요!',
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
      startInstruction: '사과를 드래그해 숫자의 합을 10으로 만드세요!',
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
      startInstruction: '1부터 50까지 숫자를 순서대로 빠르게 터치하세요!',
      countdownInstruction: '1부터 50까지 순서대로 터치하세요',
      playingInstruction: '틀려도 멈추지 않아요 · 최대한 빠르게!',
      scoreLabel: 'CLEAR TIME',
      formatScore: NumberRushRules.formatRankingScore,
      defaultDuration: const Duration(minutes: 3),
      hudStyle: MiniGameHudStyle.numberRush,
      resultUnitLabel: '기록 시간 · 최대 3분',
    ),
    'mole_reaction': MiniGameDefinition(
      id: 'mole_reaction',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => MoleReactionGame(
            countdownDuration: countdownDuration,
            maxDuration: gameDuration,
            challengeSeed: challengeSeed,
            attemptOrdinal: attemptOrdinal,
            onFinished: onFinished,
          ),
      startInstruction: '최대한 빠르게 두더지를 잡으세요!',
      countdownInstruction: '준비 한 번 후, 다음 황금 두더지가 진짜 기록이에요',
      playingInstruction: '준비 1회 후 진짜 1회 · 황금 반응시간 ×2',
      scoreLabel: 'REACTION TIME',
      formatScore: MoleReactionRules.formatRankingScore,
      hudScoreFormatter: MoleReactionRules.formatTotalMs,
      defaultDuration: MoleReactionRules.gameDuration,
      hudStyle: MiniGameHudStyle.moleReaction,
      resultUnitLabel: '가중 반응시간',
    ),
    'western_duel': MiniGameDefinition(
      id: 'western_duel',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => WesternDuelGame(
            onFinished: onFinished,
            challengeSeed: challengeSeed,
          ),
      startInstruction: 'DRAW!가 뜨면 화면을 한 번 눌러 발사하세요. 그전에 누르면 패배합니다!',
      countdownInstruction: '상대와 대치합니다. DRAW!를 기다리세요',
      playingInstruction: 'DRAW!가 보이면 화면을 눌러 단 한 발!',
      scoreLabel: 'REACTION TIME',
      formatScore: WesternDuelRules.formatRankingScore,
      defaultDuration: WesternDuelRules.gameDuration,
      hudStyle: MiniGameHudStyle.westernDuel,
      resultUnitLabel: '반응속도',
    ),
    'wind_darts': MiniGameDefinition(
      id: 'wind_darts',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => WindDartsGame(
            onFinished: onFinished,
            challengeSeed: challengeSeed,
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
          ),
      startInstruction: '바람을 읽고 조준한 뒤 손을 놓아 던지세요!',
      countdownInstruction: '12방향 바람과 풍속을 확인하세요',
      playingInstruction: '원하는 만큼 조준 · 놓으면 투척 · 총 6발',
      scoreLabel: 'DART SCORE',
      formatScore: WindDartsRules.formatScore,
      defaultDuration: WindDartsRules.gameDuration,
      hudStyle: MiniGameHudStyle.custom,
      resultUnitLabel: '6발 합계 점수',
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
      startInstruction: '엄마 오리의 첫 7칸 발자국을 기억했다가 순서대로 드래그하세요!',
      countdownInstruction: '첫 7칸 발자국을 기억하세요',
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
      startInstruction: '상하좌우 버튼으로 방향을 바꿔 야식을 먹으세요!',
      countdownInstruction: '뱀은 자동으로 움직여요 · 상하좌우 버튼을 누르세요',
      playingInstruction: '뱀은 자동으로 계속 움직여요 · 야식을 먹고 몸과 벽을 피하세요!',
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
      startInstruction: '21을 넘지 않으면서 딜러보다 21에 가까운 패를 만드세요!',
      countdownInstruction: '딜러 공개 카드를 보고 코인을 거세요',
      playingInstruction: '21에 가깝게 · 한 장 더 또는 멈추기',
      scoreLabel: 'COINS',
      formatScore: BeatTheDealerRules.formatScore,
      defaultDuration: BeatTheDealerRules.gameDuration,
      hudStyle: MiniGameHudStyle.beatTheDealer,
      resultUnitLabel: '최종 보유 코인',
    ),
    'ten_pitch_slugger': MiniGameDefinition(
      id: 'ten_pitch_slugger',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => TenPitchSluggerGame(
            countdownDuration: countdownDuration,
            watchdogDuration: gameDuration,
            challengeSeed: challengeSeed,
            onFinished: onFinished,
          ),
      startInstruction: '공이 타격점에 왔을 때 탭해 공을 최대한 멀리 치세요!',
      countdownInstruction: '준비가 끝나면 언제든 탭해 스윙하세요',
      playingInstruction: '뒤로 갈수록 더 빠르고, 같은 정타도 더 멀리!',
      scoreLabel: 'MAX DISTANCE',
      formatScore: TenPitchSluggerRules.formatScore,
      hudScoreFormatter: TenPitchSluggerRules.formatHudScore,
      defaultDuration: TenPitchSluggerRules.watchdogDuration,
      hudStyle: MiniGameHudStyle.tenPitchSlugger,
      resultUnitLabel: '10구 최대 비거리',
    ),
    'ramen_timer': MiniGameDefinition(
      id: 'ramen_timer',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => RamenTimerGame(
            countdownDuration: countdownDuration,
            challengeSeed: challengeSeed,
            onFinished: onFinished,
          ),
      startInstruction: '10초에 파, 20초에 계란, 30초에 뚜껑을 열어 주세요!',
      countdownInstruction: '처음 3초를 기억하고 조리 타이밍을 준비하세요',
      playingInstruction: '첫 두 입력의 오차를 보정하며 파 · 계란 · 뚜껑 순서대로!',
      scoreLabel: 'TOTAL COOKING ERROR',
      formatScore: RamenTimerRules.formatRankingScore,
      defaultDuration: const Duration(
        milliseconds: RamenTimerRules.timeoutMilliseconds,
      ),
      hudStyle: MiniGameHudStyle.ramenTimer,
      resultUnitLabel: '10·20·30초 총 조리 오차',
    ),
    'bathhouse_sort': MiniGameDefinition(
      id: 'bathhouse_sort',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => BathhouseSortGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            random: Random(challengeSeed),
            onFinished: onFinished,
          ),
      startInstruction: '동물을 보고 남탕은 왼쪽, 여탕은 오른쪽으로 빠르게 보내세요!',
      countdownInstruction: '흑곰은 남탕 · 흰토끼는 여탕',
      playingInstruction: '동물을 보고 아래 좌우를 빠르게 탭!',
      scoreLabel: 'BATH SCORE',
      formatScore: BathhouseSortRules.formatScore,
      hudScoreFormatter: BathhouseSortRules.formatHudScore,
      defaultDuration: BathhouseSortRules.gameDuration,
      hudStyle: MiniGameHudStyle.bathhouseSort,
      resultUnitLabel: '안내 점수',
    ),
    'lily_frog': MiniGameDefinition(
      id: 'lily_frog',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => LilyFrogGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            random: Random(challengeSeed),
            onFinished: onFinished,
          ),
      startInstruction: '빙글 도는 개구리를 탭해 다음 연잎으로 날려 보내세요!',
      countdownInstruction: '접선이 다음 연잎을 향할 때 화면을 탭하세요',
      playingInstruction: '한 바퀴 전 점프 · 연속 착지 콤보 · 물에 빠지면 종료',
      scoreLabel: 'POND SCORE',
      formatScore: LilyFrogRules.formatScore,
      hudScoreFormatter: LilyFrogRules.formatHudScore,
      defaultDuration: LilyFrogRules.gameDuration,
      resultUnitLabel: '연못 횡단 점수',
    ),
    'net_boat': MiniGameDefinition(
      id: 'net_boat',
      create:
          ({
            required gameDuration,
            required countdownDuration,
            required attemptOrdinal,
            required challengeSeed,
            required onFinished,
          }) => NetBoatGame(
            gameDuration: gameDuration,
            countdownDuration: countdownDuration,
            random: Random(challengeSeed),
            onFinished: onFinished,
          ),
      startInstruction: '배를 회전해 그물로 해양 생물을 가둬 잡으세요!',
      countdownInstruction: '돌 벽 안쪽에서 탭할 때마다 오른쪽으로 90°',
      playingInstruction: 'NET이 차면 1초간 끊김 · 배가 돌 벽이나 생물에 닿으면 종료',
      scoreLabel: 'NET SCORE',
      formatScore: NetBoatRules.formatScore,
      hudScoreFormatter: NetBoatRules.formatHudScore,
      defaultDuration: NetBoatRules.gameDuration,
      hudStyle: MiniGameHudStyle.netBoat,
      resultUnitLabel: '포획 점수',
    ),
  };

  static const _supportedVersions = <String, Set<int>>{
    'dung_dodge_v2': {1},
    'gravity_switch': {1},
    'apple_game_v2': {1},
    'number_rush': {1},
    'mama_duck_trail': {1},
    'midnight_snake': {MidnightSnakeRules.rulesVersion},
    'beat_the_dealer': {3, BeatTheDealerRules.rulesVersion},
    'ten_pitch_slugger': {7, TenPitchSluggerRules.rulesVersion},
    'ramen_timer': {3, RamenTimerRules.rulesVersion},
    'bathhouse_sort': {BathhouseSortRules.rulesVersion},
    'lily_frog': {3, LilyFrogRules.rulesVersion},
    'net_boat': {NetBoatRules.rulesVersion},
    'mole_reaction': {MoleReactionRules.rulesVersion},
    'western_duel': {WesternDuelRules.rulesVersion},
    'wind_darts': {WindDartsRules.rulesVersion},
  };

  static MiniGameDefinition? tryForId(String? id) => _definitions[id];

  static MiniGameDefinition forId(String? id) =>
      tryForId(id) ??
      (throw UnsupportedError('Unsupported game id: ${id ?? '(null)'}'));

  static bool supports(String? id, int? version) =>
      id != null &&
      version != null &&
      _definitions.containsKey(id) &&
      _supportedVersions[id]?.contains(version) == true;

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

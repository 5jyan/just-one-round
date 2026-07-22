import 'package:just_one_round/features/games/domain/mini_game.dart';
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
  };

  static MiniGameDefinition forId(String? id) =>
      _definitions[id] ?? _definitions[fallbackGameId]!;
}

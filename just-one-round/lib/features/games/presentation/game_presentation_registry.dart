import 'package:just_one_round/features/games/apple_game/presentation/apple_game_v2_presentation.dart';
import 'package:just_one_round/features/games/gravity_switch/presentation/gravity_switch_presentation.dart';
import 'package:just_one_round/features/games/number_rush/presentation/number_rush_presentation.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';
import 'package:just_one_round/features/games/star_dodge/presentation/dung_dodge_v2_presentation.dart';

abstract final class GamePresentationRegistry {
  static const _definitions = <String, GamePresentationDefinition>{
    'dung_dodge_v2': dungDodgeV2Presentation,
    'gravity_switch': gravitySwitchPresentation,
    'apple_game_v2': appleGameV2Presentation,
    'number_rush': numberRushPresentation,
  };

  static List<GamePresentationDefinition> get all =>
      List.unmodifiable(_definitions.values);

  static GamePresentationDefinition? tryForId(String? id) => _definitions[id];

  static GamePresentationDefinition forId(String? id) =>
      tryForId(id) ??
      (throw UnsupportedError(
        'Unsupported game presentation id: ${id ?? '(null)'}',
      ));
}

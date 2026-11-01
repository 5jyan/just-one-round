import 'package:just_one_round/features/games/apple_game_v2/presentation/apple_game_v2_presentation.dart';
import 'package:just_one_round/features/games/beat_the_dealer/presentation/beat_the_dealer_presentation.dart';
import 'package:just_one_round/features/games/bathhouse_sort/presentation/bathhouse_sort_presentation.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/presentation/dung_dodge_v2_presentation.dart';
import 'package:just_one_round/features/games/gravity_switch/presentation/gravity_switch_presentation.dart';
import 'package:just_one_round/features/games/lily_frog/presentation/lily_frog_presentation.dart';
import 'package:just_one_round/features/games/mama_duck_trail/presentation/mama_duck_trail_presentation.dart';
import 'package:just_one_round/features/games/net_boat/presentation/net_boat_presentation.dart';
import 'package:just_one_round/features/games/number_rush/presentation/number_rush_presentation.dart';
import 'package:just_one_round/features/games/mole_reaction/presentation/mole_reaction_presentation.dart';
import 'package:just_one_round/features/games/western_duel/presentation/western_duel_presentation.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_presentation.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';
import 'package:just_one_round/features/games/ramen_timer/presentation/ramen_timer_presentation.dart';
import 'package:just_one_round/features/games/midnight_snake/presentation/midnight_snake_presentation.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_presentation.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_presentation.dart';

abstract final class GamePresentationRegistry {
  static const _definitions = <String, GamePresentationDefinition>{
    'dung_dodge_v2': dungDodgeV2Presentation,
    'gravity_switch': gravitySwitchPresentation,
    'apple_game_v2': appleGameV2Presentation,
    'number_rush': numberRushPresentation,
    'mole_reaction': moleReactionPresentation,
    'western_duel': westernDuelPresentation,
    'wind_darts': windDartsPresentation,
    'mama_duck_trail': mamaDuckTrailPresentation,
    'midnight_snake': midnightSnakePresentation,
    'beat_the_dealer': beatTheDealerPresentation,
    'ten_pitch_slugger': tenPitchSluggerPresentation,
    'ramen_timer': ramenTimerPresentation,
    'bathhouse_sort': bathhouseSortPresentation,
    'lily_frog': lilyFrogPresentation,
    'net_boat': netBoatPresentation,
    'temple_run': templeRunPresentation,
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

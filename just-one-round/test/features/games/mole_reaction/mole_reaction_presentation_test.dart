import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/mole_reaction/presentation/mole_reaction_presentation.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_registry.dart';

void main() {
  test('가이드는 2×2·준비 1회·실전 1회·황금 ×2 규칙을 안내한다', () {
    final definition = GamePresentationRegistry.forId('mole_reaction');

    expect(definition, same(moleReactionPresentation));
    expect(definition.guidePages, hasLength(3));
    final copy = definition.guidePages
        .map((page) => '${page.title} ${page.description} ${page.detail}')
        .join(' ');
    expect(copy, contains('2×2'));
    expect(copy, contains('준비판'));
    expect(copy, contains('한 마리'));
    expect(copy, contains('황금'));
    expect(copy, contains('×2'));
    expect(copy, contains('1,000ms'));
    expect(copy, contains('4,000ms'));
    expect(copy, contains('1,500ms'));
  });
}

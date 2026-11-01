import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_registry.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';

void main() {
  test('Temple Run is registered with the approved five-page guide', () async {
    final definition = GameRegistry.forId('temple_run');
    final presentation = GamePresentationRegistry.forId('temple_run');
    final preview = PreviewDailyGameRepository(initialGameId: 'temple_run');
    final today = await preview.fetchToday();
    final developerGames = await preview.fetchDeveloperGames();

    expect(definition.id, 'temple_run');
    expect(definition.startInstruction, contains('기울'));
    expect(definition.startInstruction, isNot(contains('중앙')));
    expect(definition.countdownInstruction, contains('점프'));
    expect(definition.countdownInstruction, contains('코너'));
    expect(definition.playingInstruction, contains('코너'));
    expect(definition.playingInstruction, contains('덮개 자재'));
    expect(definition.playingInstruction, contains('작업발판'));
    expect(definition.playingInstruction, isNot(contains('상자')));
    expect(definition.playingInstruction, isNot(contains('셔터')));
    expect(GameRegistry.supports('temple_run', 1), isTrue);
    expect(GameRegistry.supports('temple_run', 2), isFalse);

    expect(presentation.homePreview.name, 'templeRun');
    expect(presentation.homeAspectRatio, 0.78);
    expect(presentation.guidePages, hasLength(5));
    final copy = presentation.guidePages
        .expand((page) => [page.title, page.description, page.detail])
        .join(' ');
    expect(copy, contains('90°'));
    expect(copy, contains('스와이프'));
    expect(copy, contains('기울'));
    expect(copy, isNot(contains('주자는 중앙')));
    expect(copy, contains('6m'));
    expect(copy, contains('덮개 자재'));
    expect(copy, contains('열린 통로'));
    expect(copy, isNot(contains('밝은 안전 띠')));
    expect(copy, contains('차단대'));
    expect(copy, contains('작업발판'));
    expect(copy, isNot(contains('상자')));
    expect(copy, isNot(contains('셔터')));
    expect(copy, contains('점프'));
    expect(copy, contains('슬라이드'));
    expect(copy, contains('0.30초'));
    expect(copy, contains('3초'));
    expect(copy, contains('약 6초'));
    expect(copy, contains('2–4개'));
    expect(copy, contains('1.40초'));
    expect(copy, contains('0.86초'));
    expect(copy, isNot(contains('1.80초')));
    expect(copy, isNot(contains('0.72초')));
    expect(copy, contains('자석'));
    expect(copy, contains('보호막'));
    expect(copy, isNot(contains('틈')));
    expect(copy, contains('기회가 소진'));
    expect(presentation.durationLabel, contains('300초'));
    expect(presentation.guideDurationText, contains('300초'));

    expect(today.game?.id, 'temple_run');
    expect(today.game?.displayName, '집에 좀 가자');
    expect(
      developerGames.singleWhere((game) => game.id == 'temple_run').displayName,
      '집에 좀 가자',
    );
  });
}

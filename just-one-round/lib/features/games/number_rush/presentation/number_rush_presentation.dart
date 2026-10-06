import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const numberRushPresentation = GamePresentationDefinition(
  id: 'number_rush',
  durationLabel: '최대 3분',
  guideDurationText: '최대 3분 동안 도전할 수 있어요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.numberRush,
  guidePages: [
    GameGuidePageDefinition(
      title: '1부터 차례대로 탭',
      description: '5×5 보드에서 1을 찾고, 이어서 2·3·4 순서로 숫자 타일을 하나씩 탭하세요.',
      detail: '누른 타일은 네온이 꺼져요. 50까지 순서를 놓치지 않고 이어가세요.',
      visual: GameGuideVisualKind.numberSequence,
    ),
    GameGuidePageDefinition(
      title: 'NEXT 숫자를 확인',
      description: '상단 NEXT에는 지금 찾아야 할 숫자가 표시됩니다. 타일을 누를 때마다 다음 숫자로 바뀌어요.',
      detail: '3초 동안 다음 숫자를 못 찾으면 해당 타일 테두리가 은은하게 점멸해요.',
      visual: GameGuideVisualKind.numberNext,
    ),
    GameGuidePageDefinition(
      title: '빈칸에 새 숫자가 켜져요',
      description:
          '처음에는 1부터 25가 보입니다. 켜진 타일이 15개보다 적어지면 빈칸에 26부터 50까지 차례로 추가됩니다.',
      detail: '새 숫자는 약 0.5~2초 뒤 켜져요. 어두운 빈칸도 계속 살펴보세요.',
      visual: GameGuideVisualKind.numberRefill,
    ),
    GameGuidePageDefinition(
      title: '틀리면 시간 손해',
      description: '순서가 아닌 숫자를 누르면 해당 타일이 잠깐 흔들리지만 게임은 계속됩니다.',
      detail: '오답을 눌러도 타이머는 계속 흘러요. 연속으로 추측하기보다 NEXT 숫자를 정확히 찾으세요.',
      visual: GameGuideVisualKind.numberMistake,
    ),
    GameGuidePageDefinition(
      title: '50을 누르면 기록 확정',
      description: '50을 누르는 순간 기록이 끝납니다. 완료 시간이 짧을수록 오늘의 랭킹이 높아집니다.',
      detail:
          '최대 3분 안에 끝내야 해요. 3분 안에 50까지 누르지 못하면 0점입니다. 홈으로 나가거나 앱을 닫거나 백그라운드로 보내면 기회가 소진되고 기록은 제출되지 않습니다.',
      visual: GameGuideVisualKind.numberResult,
    ),
  ],
);

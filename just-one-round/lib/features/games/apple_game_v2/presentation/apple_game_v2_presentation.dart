import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const appleGameV2Presentation = GamePresentationDefinition(
  id: 'apple_game_v2',
  durationLabel: '2분 20초',
  guideDurationText: '2분 20초 동안 도전할 수 있어요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.appleGameV2,
  guidePages: [
    GameGuidePageDefinition(
      title: '보드 안에서 시작해 드래그',
      description:
          '보드 안의 한 칸을 누른 채 다른 칸까지 드래그한 뒤 손을 떼세요. '
          '시작 칸과 끝 칸을 모서리로 하는 직사각형 안의 사과가 모두 선택됩니다.',
      detail: '보드 밖에서 시작하면 선택되지 않아요. 원하는 범위가 아니면 손을 떼고 보드 안에서 다시 시작하세요.',
      visual: GameGuideVisualKind.appleDrag,
    ),
    GameGuidePageDefinition(
      title: '4 + 6으로 10 만들기',
      description:
          '앞에서 선택한 4와 6을 더하면 정확히 10입니다. '
          '손을 떼는 순간 두 사과가 차례로 터지고 2점이 올라갑니다.',
      detail: '합이 10이 아니면 선택만 취소되고 사과는 그대로예요. 하지만 제한시간은 계속 흐릅니다.',
      visual: GameGuideVisualKind.appleTarget,
    ),
    GameGuidePageDefinition(
      title: 'ㄱ자 세 개도 네모로 선택',
      description:
          '사과가 ㄱ자 모양으로 세 개만 남아 있어도 빈 칸까지 포함해 '
          '2×2 직사각형으로 드래그하세요. 빈 칸은 0으로 계산되어 '
          '2+3+5=10이면 세 사과가 모두 사라집니다.',
      detail: '사과가 직사각형을 가득 채울 필요는 없어요. 선택 네모 안에 남은 사과 숫자만 더합니다.',
      visual: GameGuideVisualKind.appleSparseRectangle,
    ),
    GameGuidePageDefinition(
      title: '한 번에 많이 지우기',
      description:
          '점수는 지운 사과의 개수만큼 올라갑니다. 같은 합 10이라도 4+6은 2점, '
          '1+2+3+4는 4점이에요.',
      detail: '큰 숫자 두 개보다 작은 숫자 여러 개로 10을 만들 수 있는 직사각형을 먼저 찾아보세요.',
      visual: GameGuideVisualKind.appleScoring,
    ),
    GameGuidePageDefinition(
      title: '2분 20초 동안 최대한 많이',
      description: '140초가 끝나면 지운 사과 수가 즉시 기록됩니다. 더 많은 사과를 지울수록 오늘의 랭킹이 올라갑니다.',
      detail:
          '일시정지는 지원하지 않아요. 게임 중 홈으로 나가거나 앱을 닫거나 백그라운드로 보내면 이번 기회가 소진되고 기록도 제출되지 않습니다.',
      visual: GameGuideVisualKind.appleResult,
    ),
  ],
);

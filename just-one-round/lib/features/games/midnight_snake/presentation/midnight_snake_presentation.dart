import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const midnightSnakePresentation = GamePresentationDefinition(
  id: 'midnight_snake',
  loadingLabel: '냉장고 불빛 켜는 중...',
  durationLabel: '최대 5분',
  guideDurationText: '최대 5분 동안 야식을 최대한 많이 훔쳐 먹어요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.midnightSnake,
  guidePages: [
    GameGuidePageDefinition(
      title: '짧게 드래그해 방향 전환',
      description: '청록색 바닥 안에서 원하는 방향으로 손가락을 짧게 끌었다 놓으면 뱀이 다음 이동부터 방향을 바꿉니다.',
      detail: '길게 끌 필요는 없어요. 현재 진행 방향의 정반대 입력은 안전을 위해 받지 않습니다.',
      visual: GameGuideVisualKind.snakeSwipe,
    ),
    GameGuidePageDefinition(
      title: '야식을 먹고 길어지기',
      description: '일반 야식은 1점, 모서리에 한 번 나타나는 황금 소시지는 3점, 천천히 움직이는 쥐는 2점을 줍니다.',
      detail:
          '황금 소시지와 쥐는 한 판에 한 번씩만 나타나며 서로 동시에 나오지 않아요. 무엇을 먹어도 몸은 한 칸만 길어집니다.',
      visual: GameGuideVisualKind.snakeGrow,
    ),
    GameGuidePageDefinition(
      title: '방향을 최대 3개까지 예약',
      description: '뱀이 움직이는 동안 다음 방향을 미리 입력하면 순서대로 최대 3개까지 저장됩니다.',
      detail: '화면의 화살표가 하나씩 사라지며 실제 회전에 적용돼요. 연속 코너를 여유 있게 준비하세요.',
      visual: GameGuideVisualKind.snakeQueue,
    ),
    GameGuidePageDefinition(
      title: '벽과 자기 몸은 즉시 종료',
      description: '머리가 바닥 밖으로 나가거나 자기 몸과 부딪히면 그 자리에서 게임이 끝납니다.',
      detail: '5분이 지나면 먹은 개수로 정상 제출됩니다. 중간에 앱을 나가면 점수 없이 오늘 기회가 소진돼요.',
      visual: GameGuideVisualKind.snakeCollision,
    ),
  ],
);

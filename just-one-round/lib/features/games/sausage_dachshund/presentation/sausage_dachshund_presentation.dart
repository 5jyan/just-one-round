import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const sausageDachshundPresentation = GamePresentationDefinition(
  id: 'sausage_dachshund',
  loadingLabel: '냉장고 문 여는 중...',
  durationLabel: '최대 2분 30초',
  guideDurationText: '최대 150초 동안 소시지를 최대한 많이 먹어요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.sausageDachshund,
  guidePages: [
    GameGuidePageDefinition(
      title: '상하좌우로 짧게 스와이프',
      description: '보드 안을 스와이프하면 닥스훈트가 다음 이동 틱에 그 방향으로 돌아갑니다.',
      detail: '진행 방향의 정반대로는 바로 돌 수 없고, 한 이동 사이에는 첫 입력 하나만 예약돼요.',
      visual: GameGuideVisualKind.sausageSwipe,
    ),
    GameGuidePageDefinition(
      title: '소시지마다 몸이 한 칸 증가',
      description: '구운 소시지를 먹을 때마다 1점이 오르고 앞다리와 뒷다리 사이의 몸통이 한 칸 길어집니다.',
      detail: '새 소시지는 현재 머리에서 도달 가능한 빈칸에만 나타나요.',
      visual: GameGuideVisualKind.sausageGrow,
    ),
    GameGuidePageDefinition(
      title: '벽과 자기 몸을 피하기',
      description: '머리가 주방 벽 밖으로 나가거나 자기 몸에 닿으면 즉시 끝납니다.',
      detail: '최대 150초 동안 먹은 소시지 개수가 기록됩니다. 앱을 나가면 점수 없이 기회가 소진돼요.',
      visual: GameGuideVisualKind.sausageCollision,
    ),
  ],
);

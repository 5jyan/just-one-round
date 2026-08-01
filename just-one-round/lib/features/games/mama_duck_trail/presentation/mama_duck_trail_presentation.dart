import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const mamaDuckTrailPresentation = GamePresentationDefinition(
  id: 'mama_duck_trail',
  loadingLabel: '엄마 발자국 찾는 중...',
  durationLabel: '120초',
  guideDurationText: '120초 동안 목숨 3개로 최대한 많은 길에 도전해요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.mamaDuckTrail,
  guidePages: [
    GameGuidePageDefinition(
      title: '엄마 발자국을 기억',
      description: '엄마 오리가 지나가며 남기는 밝은 발자국의 순서와 방향을 보세요. 비가 오면 길이 사라집니다.',
      detail: '첫 길은 4칸이며 성공할 때마다 한 칸씩 늘어나요. 엄마는 마지막 칸에서 기다립니다.',
      visual: GameGuideVisualKind.mamaObserve,
    ),
    GameGuidePageDefinition(
      title: '출발점부터 계속 드래그',
      description: '맨 아래 첫 발자국을 누른 채 손을 떼지 말고 상하좌우로 같은 길을 이어가세요.',
      detail: '대각선·재방문은 안 돼요. 엄마에게 도착하기 전에 손을 떼도 현재 오리를 잃습니다.',
      visual: GameGuideVisualKind.mamaRecall,
    ),
    GameGuidePageDefinition(
      title: '목숨은 3개',
      description: '잘못된 칸에 들어가면 목숨이 하나 줄어요. 목숨 3개를 모두 잃거나 120초가 지나면 끝납니다.',
      detail: '첫 길부터 바로 목숨이 줄어요. 위쪽 오리 얼굴은 남은 목숨 표시예요. 홈 이동이나 앱 중단도 조심하세요.',
      visual: GameGuideVisualKind.mamaFailure,
    ),
  ],
);

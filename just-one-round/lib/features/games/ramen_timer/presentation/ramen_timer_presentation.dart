import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const ramenTimerPresentation = GamePresentationDefinition(
  id: 'ramen_timer',
  loadingLabel: '야근 너구리 깨우는 중...',
  durationLabel: '약 30초 · 최대 45초',
  guideDurationText: '처음 3초와 두 번의 흐릿한 힌트를 보고, 체감 10·20·30초를 찍어요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.ramenTimer,
  guidePages: [
    GameGuidePageDefinition(
      title: '10·20·30초에 찍기',
      description: '같은 찍기 버튼을 체감 10초, 20초, 30초에 한 번씩 누르세요.',
      detail: '파와 계란은 입력 확인용입니다. 앞선 기록의 빠름·느림은 마지막까지 알려주지 않아요.',
      visual: GameGuideVisualKind.ramenCheckpoints,
    ),
    GameGuidePageDefinition(
      title: '연기 사이 힌트 보기',
      description: '처음 3초 동안 실제 1초의 길이를 익히면, 컵에서 올라온 증기가 시계를 덮어요.',
      detail: '3.2초부터 버튼이 켜지고, 12~13초와 22~23초에는 실제 시간이 잠깐 희미하게 비칩니다.',
      visual: GameGuideVisualKind.ramenCalibration,
    ),
    GameGuidePageDefinition(
      title: '세 오차의 합으로 승부',
      description: '세 기록의 목표 대비 오차를 모두 더한 총 오차가 0.00초에 가까울수록 높은 순위입니다.',
      detail: '45초까지 세 번 누르지 않으면 시간 초과입니다. 앱을 나가면 점수 없이 오늘 기회가 소진돼요.',
      visual: GameGuideVisualKind.ramenResult,
    ),
  ],
);

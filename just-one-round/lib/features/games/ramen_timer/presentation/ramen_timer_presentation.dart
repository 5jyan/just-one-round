import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const ramenTimerPresentation = GamePresentationDefinition(
  id: 'ramen_timer',
  durationLabel: '약 30초 · 최대 45초',
  guideDurationText: '처음 3초로 감각을 익히고, 누적 10·20·30초를 맞춰요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.ramenTimer,
  guidePages: [
    GameGuidePageDefinition(
      title: '파·계란·뚜껑 순서대로',
      description: '게임 시작부터 누적 10초, 20초, 30초라고 느끼는 순간에 한 번씩 눌러요.',
      detail: '10초·파 넣기 → 20초·계란 넣기 → 30초·뚜껑 열기. 첫 두 입력 뒤에는 목표와의 차이를 바로 알려줘요.',
      visual: GameGuideVisualKind.ramenCheckpoints,
    ),
    GameGuidePageDefinition(
      title: '누른 뒤 오차로 보정',
      description: '처음 3초는 시계가 보여요. 3.2초부터 입력이 켜지고, 그 뒤에는 시간이 계속 가려져요.',
      detail: '10초와 20초에 누르면 목표보다 몇 초 빠르거나 늦었는지만 약 2초간 보여줘요.',
      visual: GameGuideVisualKind.ramenCalibration,
    ),
    GameGuidePageDefinition(
      title: '오차 합·시간 초과·나가기',
      description: '세 기록의 목표 대비 절대 오차를 더한 총 오차가 0초에 가까울수록 높은 순위예요.',
      detail:
          '45초까지 세 번 누르지 않으면 시간 초과예요. 일시정지는 다시 이어도 스톱워치가 계속 흐르고, 완료 전 명시적 나가기는 미완료 시도로 끝나요.',
      visual: GameGuideVisualKind.ramenResult,
    ),
  ],
);

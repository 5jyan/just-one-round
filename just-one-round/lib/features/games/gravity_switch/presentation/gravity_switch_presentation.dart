import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const gravitySwitchPresentation = GamePresentationDefinition(
  id: 'gravity_switch',
  loadingLabel: '고철 수집 중...',
  durationLabel: '제한 없음',
  guideDurationText: '시간 제한 없이 도전할 수 있어요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.gravitySwitch,
  guidePages: [
    GameGuidePageDefinition(
      title: '탭해서 중력 뒤집기',
      description:
          '캐릭터는 화면 왼쪽에 있고 맵 전체가 오른쪽에서 왼쪽으로 흐릅니다. 화면 아무 곳이나 한 번 탭하면 중력이 뒤집혀 반대편으로 이동합니다.',
      detail: '탭 한 번이면 충분해요. 캐릭터가 회전하며 바닥이나 천장에 착지합니다.',
      visual: GameGuideVisualKind.gravityControl,
    ),
    GameGuidePageDefinition(
      title: '벽에 박기 전에 안전한 쪽으로',
      description: '다가오는 고철 벽을 보고, 캐릭터가 부딪히기 전에 빈 공간이 있는 쪽으로 중력을 바꾸세요.',
      detail: '안전한 쪽에 착지하면 고철 벽이 캐릭터 옆을 지나갑니다. 다음 벽의 빈 공간도 미리 확인하세요.',
      visual: GameGuideVisualKind.gravityObstacle,
    ),
    GameGuidePageDefinition(
      title: '갈수록 더 빠르고 어려워져요',
      description: '시간이 지날수록 맵이 점점 더 빠르게 흐르고, 복잡한 고철 통로도 등장합니다.',
      detail: '눈앞의 기둥만 보지 말고 그다음 바닥과 천장의 빈 공간까지 함께 확인하세요.',
      visual: GameGuideVisualKind.gravityDifficulty,
    ),
    GameGuidePageDefinition(
      title: '한 번 부딪히면 GAME OVER',
      description:
          '고철 기둥에 닿는 순간 캐릭터가 KO 상태로 바뀌고 게임이 즉시 종료됩니다. 시간 제한 없이 그때까지 살아남은 시간이 기록됩니다.',
      detail:
          '기록은 0.01초 단위로 비교돼요. 홈으로 나가거나 앱을 닫거나 백그라운드로 보내면 기회가 소진되고 기록은 제출되지 않습니다.',
      visual: GameGuideVisualKind.gravitySurvival,
    ),
  ],
);

import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const windDartsPresentation = GamePresentationDefinition(
  id: 'wind_darts',
  durationLabel: '7발 · 최대 480점 · 시간 제한 없음',
  guideDurationText: '시간 제한 없이 총 일곱 발을 던져요. 마지막은 황금 다트예요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.windDarts,
  guidePages: [
    GameGuidePageDefinition(
      title: '누르고, 조준하고, 놓으세요',
      description: '화면을 누른 채 손가락을 상대적으로 끌어 조준점을 옮기세요. 손을 놓는 순간 다트가 발사돼요.',
      detail:
          '게이지는 6초 동안 차지만 파워가 아니에요. 다 찬 뒤에도 계속 조준할 수 있고, 놓는 순간의 조준점과 바람이 착탄을 정해요.',
      visual: GameGuideVisualKind.windDartsHold,
    ),
    GameGuidePageDefinition(
      title: '바람 반대쪽을 조준하세요',
      description: '화살표 방향으로 다트가 밀려요. 숫자가 클수록 더 많이 밀려요.',
      detail: '놓는 순간의 조준점에서 바람 방향으로 착탄점이 옮겨져요. 화살표 반대쪽을 미리 조준하세요.',
      visual: GameGuideVisualKind.windDartsWind,
    ),
    GameGuidePageDefinition(
      title: '7라운드, 점점 더 멀리',
      description: '첫 여섯 발은 1m부터 3.5m까지 멀어지고, 마지막 발은 3.5m에서 던져요.',
      detail: '준비할 때는 멀어진 만큼 판이 작게 보이고, 다트가 날아갈 때 카메라가 판까지 전진해 착탄 지점을 보여 줘요.',
      visual: GameGuideVisualKind.windDartsDistance,
    ),
    GameGuidePageDefinition(
      title: '황금 다트는 점수 2배',
      description: '싱글은 숫자만큼, 더블은 2배, 트리플은 3배예요. S-BULL은 25점, D-BULL은 50점이에요.',
      detail:
          '판 밖은 0점이에요. 일곱 발의 합계로 상대와 겨루고, 마지막 GOLD는 점수가 2배예요. 합계가 기록으로 제출되며 게임을 나가거나 앱을 백그라운드로 보내면 시도가 종료돼요.',
      visual: GameGuideVisualKind.windDartsScoring,
    ),
  ],
);

import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const windDartsPresentation = GamePresentationDefinition(
  id: 'wind_darts',
  durationLabel: '6발 · 최대 360점 · 시간 제한 없음',
  guideDurationText: '시간 제한 없이 1m부터 3.5m까지 총 여섯 발을 던져요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.windDarts,
  guidePages: [
    GameGuidePageDefinition(
      title: '누른 채 조준하고 놓으세요',
      description: '화면을 누른 채 손가락을 끌어 중앙 조준점을 움직이세요. 손을 놓는 순간 다트가 발사돼요.',
      detail:
          '게이지는 6초 동안 차지만 파워가 아니에요. 게이지가 다 차도 계속 조준할 수 있고, 마지막 조준점과 바람만 착탄을 정해요.',
      visual: GameGuideVisualKind.windDartsHold,
    ),
    GameGuidePageDefinition(
      title: '바람 화살표와 세기를 읽으세요',
      description: '바람은 12시부터 시계 방향 12방향으로 표시하고 풍속은 m/s로 보여 줘요.',
      detail: '놓는 순간의 조준점에 바람이 더해져요. 방향과 m/s를 읽고 바람이 미는 방향의 반대쪽으로 미리 조준하세요.',
      visual: GameGuideVisualKind.windDartsWind,
    ),
    GameGuidePageDefinition(
      title: '거리가 늘고 카메라가 따라가요',
      description: '여섯 발의 거리는 1m, 1.5m, 2m, 2.5m, 3m, 3.5m 순서로 멀어져요.',
      detail: '준비할 때는 멀어진 만큼 판이 작게 보이고, 다트가 날아갈 때 카메라가 판까지 전진해 착탄 지점을 보여 줘요.',
      visual: GameGuideVisualKind.windDartsDistance,
    ),
    GameGuidePageDefinition(
      title: '표준 점수를 여섯 발 합산해요',
      description: '싱글은 숫자만큼, 더블은 2배, 트리플은 3배예요. 불은 50점입니다.',
      detail:
          '판 밖은 0점이에요. 여섯 발의 합계가 기록으로 제출되며, 게임을 나가거나 앱을 백그라운드로 보내면 시도가 종료돼요.',
      visual: GameGuideVisualKind.windDartsScoring,
    ),
  ],
);

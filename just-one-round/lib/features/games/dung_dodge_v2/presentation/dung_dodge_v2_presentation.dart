import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const dungDodgeV2Presentation = GamePresentationDefinition(
  id: 'dung_dodge_v2',
  durationLabel: '최대 5분',
  guideDurationText: '최대 5분 동안 도전할 수 있어요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.dungDodgeV2,
  guidePages: [
    GameGuidePageDefinition(
      title: '누른 채로 좌우로 드래그',
      description:
          '화면의 아무 곳이나 손가락으로 누른 뒤, 떼지 않고 왼쪽이나 오른쪽으로 밀어보세요. '
          '캐릭터는 손가락의 가로 이동 거리만큼 바로 따라갑니다.',
      detail:
          '가볍게 터치만 하면 움직이지 않아요. 누른 위치로 순간이동하지 않고, '
          '손가락을 뗀 곳에서 멈춥니다. 다른 곳에서 다시 드래그해도 바로 이어서 움직일 수 있어요.',
      visual: GameGuideVisualKind.dungSwipe,
    ),
    GameGuidePageDefinition(
      title: '떨어지는 똥 사이로 피하기',
      description: '화면 위에서 떨어지는 똥의 위치를 먼저 보고, 빈 공간을 향해 짧고 정확하게 움직이세요.',
      detail: '한 방향으로 계속 달리기보다 가까운 안전지대로 조금씩 이동하면 다음 장애물에 대응하기 쉬워요.',
      visual: GameGuideVisualKind.dungGameplay,
    ),
    GameGuidePageDefinition(
      title: '시간이 갈수록 더 어려워져요',
      description: '처음에는 천천히 떨어지지만, 생존 시간이 길어질수록 똥이 더 자주 나타나고 낙하 속도도 빨라집니다.',
      detail: '후반에는 화면 전체를 한 번에 보고 미리 움직여야 해요. 눈앞의 한 개만 따라가면 퇴로가 막힐 수 있습니다.',
      visual: GameGuideVisualKind.dungDifficulty,
    ),
    GameGuidePageDefinition(
      title: '한 번 부딪히면 즉시 종료',
      description: '캐릭터에게 똥이 닿는 순간 그 판은 끝나고, 그때까지 살아남은 시간이 기록됩니다.',
      detail: '게임 도중 홈으로 이동하거나 앱을 종료해도 기회가 소진되니, 시작하기 전에 집중할 시간을 확보하세요.',
      visual: GameGuideVisualKind.dungCollision,
    ),
    GameGuidePageDefinition(
      title: '최대한 오래 살아남으세요',
      description: '최대 5분 동안 버틸 수 있습니다. 생존 시간이 길수록 오늘의 랭킹이 올라갑니다.',
      detail: '기록은 0.01초 단위로 비교돼요. 마지막까지 침착하게 빈 공간을 찾는 것이 최고 기록의 핵심입니다.',
      visual: GameGuideVisualKind.dungSurvival,
    ),
  ],
);

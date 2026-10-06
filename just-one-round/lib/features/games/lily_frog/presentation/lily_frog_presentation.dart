import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const lilyFrogPresentation = GamePresentationDefinition(
  id: 'lily_frog',
  durationLabel: '150초 · 물에 빠지면 종료',
  guideDurationText: '150초 동안 연잎을 건너며 점수를 모으세요. 물에 빠지면 즉시 끝나요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.lilyFrog,
  guidePages: [
    GameGuidePageDefinition(
      title: '탭하면 90° 접선 점프',
      description: '개구리는 연잎 가장자리를 돌다가 탭한 순간, 반지름과 90°인 접선 방향으로 곧게 뛰어요.',
      detail:
          '개구리 앞의 점선이 바로 그 접선 점프 방향이에요. 화면 아무 곳이나 한 번 탭하면 점선을 따라 실제로 날아갑니다.',
      visual: GameGuideVisualKind.lilyOrbit,
    ),
    GameGuidePageDefinition(
      title: '점선은 처음 3번만',
      description: '첫 3번의 점프에는 실제 접선 경로와 착지 원이 보여요. 점선 끝이 연잎에 닿을 때 탭하세요.',
      detail: '4번째 점프부터 점선과 착지 원이 사라져요. 처음 3번 동안 접선 타이밍을 익혀두세요.',
      visual: GameGuideVisualKind.lilyTangent,
    ),
    GameGuidePageDefinition(
      title: '갈수록 더 빨라져요',
      description: '회전 속도는 0초 1.35에서 140초 2.80까지 20초 기준점 사이를 일정하게 높여가요.',
      detail:
          '140초부터 종료까지 최고 속도를 유지해요. 한 바퀴 시간도 시작 약 4.65초에서 마지막 약 2.24초로 줄어들어요.',
      visual: GameGuideVisualKind.lilySpeed,
    ),
    GameGuidePageDefinition(
      title: '착지 점수와 콤보',
      description:
          '새 연잎 착지는 기본 300점에 현재 콤보×10점을 더 받아요. 황금 착지는 기본 포함 1,000점이에요.',
      detail:
          'COMBO 아래 게이지가 비기 전에 뛰어 다음 새 연잎에 착지하면 콤보가 올라가고 그 착지부터 추가점수를 받아요. 한 바퀴를 넘기거나 밟았던 연잎으로 돌아가면 끊겨요.',
      visual: GameGuideVisualKind.lilyScoring,
    ),
    GameGuidePageDefinition(
      title: '황금 연잎과 파리 POP!',
      description:
          '연잎 5개마다 작은 황금 연잎과 일반 연잎 중 하나를 고르세요. 황금 착지는 1,000점에 콤보 점수도 더해요.',
      detail: '파리는 황금 선택 구간이 아닌 일반 길에서 나와요. 2~3마리를 통과하면 각각 +100점과 함께 팍 터집니다.',
      visual: GameGuideVisualKind.lilyBonus,
    ),
    GameGuidePageDefinition(
      title: '150초 · 풍덩이면 끝',
      description: '최대 150초 동안 도전해요. 연잎을 놓쳐 물에 빠지면 남은 시간과 관계없이 점수가 바로 제출돼요.',
      detail: '일시정지는 지원하지 않아요. 홈으로 나가거나 앱을 닫아도 사용한 도전은 되돌아오지 않습니다.',
      visual: GameGuideVisualKind.lilyFailure,
    ),
  ],
);

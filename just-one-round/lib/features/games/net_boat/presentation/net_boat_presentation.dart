import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const netBoatPresentation = GamePresentationDefinition(
  id: 'net_boat',
  durationLabel: '최대 300초 · 돌 벽이나 위험 생물에 닿으면 종료',
  guideDurationText: '최대 300초 동안 물고기를 그물로 몰아 둘러싸 잡으세요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.netBoat,
  guidePages: [
    GameGuidePageDefinition(
      title: '탭하면 오른쪽으로 90°',
      description: '화면을 탭하면 배가 무조건 오른쪽으로 정확히 90° 회전해요.',
      detail: '화면 어디를 눌러도 같은 규칙으로 돌아요. 배는 회전한 방향으로 계속 앞으로 나아가요.',
      visual: GameGuideVisualKind.netBoatTurn,
    ),
    GameGuidePageDefinition(
      title: '그물로 사각형을 만들어요',
      description: '배가 지나간 자리에 그물이 생겨요. 그물을 이어 사각형을 만들면 안의 물고기를 잡을 수 있어요.',
      detail:
          '배가 내 그물에 다시 닿아 구역이 닫히는 순간 포획돼요. 고래를 제외한 물고기는 열린 그물에 닿으면 튕겨 나가고, 고래는 그물을 통과할 수 있어요.',
      visual: GameGuideVisualKind.netBoatTurn,
    ),
    GameGuidePageDefinition(
      title: '정어리는 안전해요',
      description: '배가 피라냐·청새치·상어·고래 또는 바깥 돌 벽에 박으면 게임이 끝나요.',
      detail: '정어리는 배에 부딪혀도 절대 게임이 끝나지 않아요. 피라냐·청새치·상어·고래와 돌 벽만 피하세요.',
      visual: GameGuideVisualKind.netBoatFailure,
    ),
    GameGuidePageDefinition(
      title: '물고기마다 점수가 달라요',
      description: '정어리 10점, 피라냐 100점, 청새치 300점, 상어 700점, 고래 2,500점이에요.',
      detail: '정어리는 점수는 낮지만 위협적이지 않아요. 위험한 물고기를 여러 마리 한 번에 잡으면 추가 보너스가 붙어요.',
      visual: GameGuideVisualKind.netBoatScore,
    ),
    GameGuidePageDefinition(
      title: '그물 최대 길이는 1000',
      description:
          '상단 NET 게이지로 그물 길이를 확인하세요. 그물 길이 800부터는 끊길 위험이 있고, 최대 1000까지만 펼칠 수 있어요.',
      detail:
          '고래를 제외한 물고기는 열린 그물을 통과하지 못하고 튕겨 나가요. 고래는 그물을 통과할 수 있어요. 그물 길이 800부터 끊길 위험이 있고, 1000에 닿으면 그물이 끊기고 1초 뒤 다시 펼쳐져요.',
      visual: GameGuideVisualKind.netBoatLimit,
    ),
  ],
);

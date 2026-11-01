import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const templeRunPresentation = GamePresentationDefinition(
  id: 'temple_run',
  durationLabel: '최대 5분 · 300초',
  guideDurationText: '최대 300초 동안 골목을 달려 집에 도착해요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.templeRun,
  guidePages: [
    GameGuidePageDefinition(
      title: '기울여 위치를 잡고, 90° 코너를 예약해요',
      description:
          '폰을 좌우로 기울이면 주자가 길 위에서 연속으로 움직여요. 좌우 스와이프는 예고된 90° 코너를 예약할 때만 써요.',
      detail:
          '카운트다운 동안 폰을 가만히 두면 기울기 기준이 잡혀요. 방향 표지판 뒤 약 3초 예약 창에서 같은 방향으로 한 번 밀면, 실제 모퉁이에 닿을 때 카메라가 90° 돌아 새 길로 이어져요.',
      visual: GameGuideVisualKind.templeRunControls,
    ),
    GameGuidePageDefinition(
      title: '덮개 자재 사이 좁은 통로를 끝까지 지나가요',
      description: '덮개 자재 더미 사이 열린 통로에 주자의 발을 맞추세요. 폰을 기울여 좌우 위치를 계속 조정해요.',
      detail: '좁은 통로는 6m 동안 이어지고, 양옆은 덮개 자재에 막혀요. 점프·슬라이드·보호막으로 통로를 벗어날 수 없어요.',
      visual: GameGuideVisualKind.templeRunHazards,
    ),
    GameGuidePageDefinition(
      title: '차단대는 점프, 작업발판은 슬라이드',
      description: '낮은 차단대는 위로 밀어 점프하고, 위가 막힌 작업발판은 아래로 밀어 슬라이드하세요.',
      detail:
          '동작 중 세로 스와이프는 한 번만 0.30초 동안 대기해요. 앞 동작이 끝나면 대기 입력이 이어지고, 두 번째 대기 입력은 받지 않아요.',
      visual: GameGuideVisualKind.templeRunManeuvers,
    ),
    GameGuidePageDefinition(
      title: '3초 전에 코너를 예약하고 아이템을 챙겨요',
      description: '방향 표지판은 코너를 약 3초 앞서 알려줘요. 좌우 스와이프로 방향을 예약하고 회전 지점에서 실행하세요.',
      detail:
          '코인 1개는 10점이고, 코인 줄은 약 3.5초마다, 아이템은 약 30초마다 나와요. 자석은 가까운 코인을 끌어오고, 보호막은 단단한 장애물 1회를 막아요. 부스트는 잠깐 무적이며 코너를 자동으로 돌아요. 보호막은 좁은 길 이탈·코너 실패를 막지 않아요.',
      visual: GameGuideVisualKind.templeRunItems,
    ),
    GameGuidePageDefinition(
      title: '골목을 오래 달려 집에 도착해요',
      description: '달린 거리 1m마다 1점, 코인 1개마다 10점이에요. 오래 달리고 틀리지 않는 것이 목표예요.',
      detail:
          '첫 코너는 약 4.2–4.6초, 첫 좁은 통로는 약 6초예요. 그 뒤 장애물이 2–4개 연달아 나오고 90° 코너가 이어져요. 달릴수록 속도와 행동 빈도가 올라가며 간격 목표는 초반 약 1.40초에서 마지막 약 0.86초까지 줄어요. 코너·좁은 통로처럼 안전 여유가 필요한 곳은 실제 간격을 넓혀요. 충돌·코너 실패·좁은 길 이탈·추락은 즉시 종료되고, 앱을 나가면 기회가 소진돼요.',
      visual: GameGuideVisualKind.templeRunScore,
    ),
  ],
);

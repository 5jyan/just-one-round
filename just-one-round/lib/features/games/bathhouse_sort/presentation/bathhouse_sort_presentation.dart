import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const bathhouseSortPresentation = GamePresentationDefinition(
  id: 'bathhouse_sort',
  durationLabel: '60초',
  guideDurationText: '60초 동안 동물 규칙을 기억하고 줄 선 손님을 빠르게 안내하세요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.bathhouseSort,
  guidePages: [
    GameGuidePageDefinition(
      title: '남자는 남탕, 여자는 여탕',
      description: '남자 동물은 남탕으로, 여자 동물은 여탕으로 보내세요.',
      detail: '손님을 잡거나 드래그할 필요 없어요. 뒤의 줄을 읽고 빠르게 연속 탭하면 입력이 순서대로 예약됩니다.',
      visual: GameGuideVisualKind.bathhouseControls,
    ),
    GameGuidePageDefinition(
      title: '동물과 옷 색을 기억하세요',
      description: '남자 동물은 흑곰·갈색 강아지·너구리·회색 늑대, 여자 동물은 흰토끼·핑크돼지·크림 양·치즈 고양이예요.',
      detail: '남자는 파란 옷, 여자는 빨간 옷을 입고 있어요. 동물 종류와 옷 색을 함께 보면 더 빠르게 구분할 수 있습니다.',
      visual: GameGuideVisualKind.bathhouseQueue,
    ),
    GameGuidePageDefinition(
      title: '시간마다 동물이 달라져요',
      description: '시간이 지날수록 등장하는 남자·여자 동물의 종류가 하나씩 늘어나요.',
      detail: '처음에는 흑곰과 흰토끼만 나오고, 15·30·45초마다 새로운 동물 한 쌍이 추가됩니다. 게임은 멈추지 않아요.',
      visual: GameGuideVisualKind.bathhouseUnlock,
    ),
    GameGuidePageDefinition(
      title: '정확한 콤보로 고득점',
      description: '잘못 보내면 콤보가 끊기고 예약 입력도 사라져요. 60초 동안 정확한 연속 탭을 유지하세요.',
      detail:
          '1콤보 100점부터 정답마다 10점씩 올라가고 27콤보부터 360점! 도중에 나가거나 앱을 닫으면 점수 없이 판이 소진됩니다.',
      visual: GameGuideVisualKind.bathhouseScoring,
    ),
  ],
);

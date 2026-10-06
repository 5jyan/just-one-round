import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const beatTheDealerPresentation = GamePresentationDefinition(
  id: 'beat_the_dealer',
  durationLabel: '10라운드 · 최대 3분',
  guideDurationText: '100코인으로 시작해 10라운드 뒤 가장 많은 코인을 남겨요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.beatTheDealer,
  guidePages: [
    GameGuidePageDefinition(
      title: '공개 카드를 보고 배팅',
      description:
          '딜러 카드 한 장을 보고 5~50코인을 걸어요. 마지막 10라운드에는 최대 100코인까지 걸 수 있습니다.',
      detail: '−5와 +5로 조절해요. 최소·최대에서 더 누르면 한도를 알려주고, 8초가 지나면 자동 배팅됩니다.',
      visual: GameGuideVisualKind.dealerBet,
    ),
    GameGuidePageDefinition(
      title: '21에 가깝게 만들기',
      description: 'A는 1 또는 11, J·Q·K는 모두 10으로 계산됩니다. A는 유리한 값으로 자동 계산돼요.',
      detail: '처음 받은 두 장이 A와 10점 카드라면 블랙잭입니다. 카드에 0은 나오지 않아요.',
      visual: GameGuideVisualKind.dealerGoal,
    ),
    GameGuidePageDefinition(
      title: '한 장 더 또는 멈추기',
      description: '카드 두 장을 받은 뒤 부족하면 ‘한 장 더’, 충분하면 ‘멈추기’를 누르세요.',
      detail: '합계가 21을 넘으면 즉시 패배합니다. 8초 동안 고르지 않으면 현재 합계에서 자동으로 멈춰요.',
      visual: GameGuideVisualKind.dealerChoice,
    ),
    GameGuidePageDefinition(
      title: '딜러 규칙은 자동',
      description: '내 선택이 끝나면 딜러의 숨긴 카드를 공개합니다. 딜러는 16 이하면 받고 17 이상이면 멈춰요.',
      detail: '내가 먼저 버스트하면 딜러도 버스트여도 패배합니다. 둘 다 21 이하에서 같은 합계일 때만 무승부예요.',
      visual: GameGuideVisualKind.dealerResult,
    ),
    GameGuidePageDefinition(
      title: '10라운드 코인 랭킹',
      description:
          '7번째 판에는 덱에 A가 남아 있으면 배팅 화면부터 내 앞에 공개돼요. 배팅을 확정하면 그 A를 시작 카드로 받아요. 승리하면 배팅액만큼, 블랙잭이면 1.5배를 받고 패배하면 배팅액을 잃어요.',
      detail: '10라운드 뒤 최종 코인으로 순위가 정해져요. 중간에 앱을 나가면 점수 없이 오늘 기회가 소진됩니다.',
      visual: GameGuideVisualKind.dealerResult,
    ),
  ],
);

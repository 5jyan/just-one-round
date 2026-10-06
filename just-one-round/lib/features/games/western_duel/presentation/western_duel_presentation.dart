import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const westernDuelPresentation = GamePresentationDefinition(
  id: 'western_duel',
  durationLabel: '약 9~15초 · 최대 30초',
  guideDurationText: '신호 전에는 기다리고, DRAW! 뒤 1.000초 안에 새로 한 번 터치하세요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.westernDuel,
  guidePages: [
    GameGuidePageDefinition(
      title: '신호 전에는 손 떼고 기다리기',
      description: '3.2초 카운트다운 뒤 3~8초 대치해요. DRAW! 전(대치 중)에 누르면 조기 입력으로 패배해요.',
      detail:
          '카운트다운 중 터치는 무시되지만, 미리 누른 채 신호를 기다리면 발사되지 않아요. 손을 뗐다가 DRAW! 뒤 새로 터치하세요.',
      visual: GameGuideVisualKind.westernWait,
    ),
    GameGuidePageDefinition(
      title: 'DRAW! 뒤 새로 한 번 터치',
      description: '화면 중앙에 DRAW!가 보이면 상단 표시 영역과 화면 가장자리를 피해 화면 가운데를 한 번 터치하세요.',
      detail:
          '미리 누른 손은 떼고, DRAW!가 뜬 뒤 새로 터치하세요. 신호가 뜬 후 1.000초 안에 누르지 못하면 발사 없이 1.000초 기록으로 종료돼요.',
      visual: GameGuideVisualKind.westernDraw,
    ),
    GameGuidePageDefinition(
      title: '둘 다 발사, 빠른 쪽 승리',
      description:
          '상대가 먼저 쏴도 1.000초 안에 새로 터치하면 내 한 발을 쏠 수 있어요. 두 발사가 끝난 뒤 더 빠른 반응이 승리해요.',
      detail:
          '승패와 관계없이 내 반응시간만 0.123초처럼 소수점 셋째 자리까지 기록돼요. 제한시간 초과는 1.000초로 기록되고, 게임을 나가면 시도가 소모될 수 있어요.',
      visual: GameGuideVisualKind.westernResult,
    ),
  ],
);

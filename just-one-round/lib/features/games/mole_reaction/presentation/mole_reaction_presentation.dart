import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const moleReactionPresentation = GamePresentationDefinition(
  id: 'mole_reaction',
  durationLabel: '약 10~20초 · 최대 180초',
  guideDurationText: '준비 두더지 한 번 뒤, 진짜 황금 두더지 한 마리를 잡아 보세요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.moleReaction,
  guidePages: [
    GameGuidePageDefinition(
      title: '두더지가 보이면 바로 누르기',
      description: '2×2 구멍 중 두더지가 보인 칸을 즉시 눌러요. 등장 전 3~8초 동안 시선을 떼지 마세요.',
      detail: '첫 번째는 손을 풀어 보는 준비판이고, 두 번째 두더지 한 마리의 기록만 최종 점수에 반영돼요.',
      visual: GameGuideVisualKind.moleReaction,
    ),
    GameGuidePageDefinition(
      title: '진짜는 황금 두더지 한 마리',
      description: '준비판이 끝나면 황금 두더지가 한 번만 올라와요. 그 순간이 오늘의 기록입니다.',
      detail: '황금 두더지의 실제 반응시간은 최종 기록에 ×2로 더해지고, 성공하면 금빛 파편과 ×2 효과가 나옵니다.',
      visual: GameGuideVisualKind.moleReaction,
    ),
    GameGuidePageDefinition(
      title: '한 번의 ms가 최종 기록',
      description: '두더지가 보인 뒤 누르기까지의 시간과 실수 벌점을 합산합니다.',
      detail:
          '준비판은 기록에 포함되지 않아요. 진짜 판에서 빈 구멍은 +1,000ms, 1,500ms 안에 못 누르면 +4,000ms예요.',
      visual: GameGuideVisualKind.moleReaction,
    ),
  ],
);

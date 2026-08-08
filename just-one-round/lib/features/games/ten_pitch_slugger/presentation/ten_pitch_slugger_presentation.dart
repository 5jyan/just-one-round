import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';

const tenPitchSluggerPresentation = GamePresentationDefinition(
  id: 'ten_pitch_slugger',
  loadingLabel: '방망이 닦는 중...',
  durationLabel: '10구 · 시간제한 없음',
  guideDurationText: '총 10구를 치고, 그중 가장 멀리 친 기록으로 승부해요.',
  homeAspectRatio: 0.78,
  homePreview: GameHomePreviewKind.tenPitchSlugger,
  guidePages: [
    GameGuidePageDefinition(
      title: '준비가 끝나면 계속 스윙',
      description: '2초 준비 뒤에는 투수가 공을 던지기 전부터 화면 아무 곳이나 탭할 때마다 타자가 스윙합니다.',
      detail: '2초 준비가 끝나면 공이 오기 전부터 0.3초마다 계속 탭할 수 있어요. 누르고 있거나 드래그할 필요는 없습니다.',
      visual: GameGuideVisualKind.sluggerTap,
    ),
    GameGuidePageDefinition(
      title: '배트 끝에서 맞히기',
      description: '공이 방망이 끝에 닿는 순간에 가까울수록 더 멀리 날아갑니다. 일찍 헛스윙하면 다시 노리세요.',
      detail: '투수가 준비하는 동안에도 휘두를 수 있고, 공이 지나가기 전까지만 정타를 만들 수 있어요.',
      visual: GameGuideVisualKind.sluggerTiming,
    ),
    GameGuidePageDefinition(
      title: '100m부터 홈런',
      description: '맞힌 공은 타이밍 정확도에 따라 35m에서 그 공의 최대 비거리까지 기록하며, 100m부터 홈런입니다.',
      detail:
          '홈런은 정타 중심의 좁은 12% 구간에서만 나와요. 성공하면 HOME RUN! 표시가 뜨며, 끝까지 못 맞힌 투구만 0m입니다.',
      visual: GameGuideVisualKind.sluggerDistance,
    ),
    GameGuidePageDefinition(
      title: '10구는 도깨비 마구',
      description: '4구부터 코스가 바뀌고 계속 빨라집니다. 마지막 10구는 0.60초 만에 S자로 휘며 떨어져요.',
      detail:
          '7구부터 비거리 보상이 크게 오르고, 10구는 같은 정확도에도 최대 40m 더 갑니다. 보라색 기운이 보이면 마지막 공이에요.',
      visual: GameGuideVisualKind.sluggerMagic,
    ),
    GameGuidePageDefinition(
      title: '가장 멀리 친 공이 기록',
      description: '10구 중 가장 긴 비거리 하나가 최종 점수입니다. 제한시간은 없어요.',
      detail: '홈으로 나가거나 앱을 중단하면 점수 없이 오늘 기회가 소진됩니다. 10구까지 끝내세요.',
      visual: GameGuideVisualKind.sluggerScore,
    ),
  ],
);

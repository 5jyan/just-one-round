enum GameHomePreviewKind { dungDodgeV2, gravitySwitch, appleGameV2, numberRush }

enum GameGuideVisualKind {
  dungSwipe,
  dungGameplay,
  dungDifficulty,
  dungCollision,
  dungSurvival,
  appleDrag,
  appleTarget,
  appleSparseRectangle,
  appleScoring,
  appleResult,
  gravityControl,
  gravityLanding,
  gravityObstacle,
  gravityDifficulty,
  gravitySurvival,
  numberSequence,
  numberNext,
  numberRefill,
  numberMistake,
  numberResult,
}

class GameGuidePageDefinition {
  const GameGuidePageDefinition({
    required this.title,
    required this.description,
    required this.detail,
    required this.visual,
  });

  final String title;
  final String description;
  final String detail;
  final GameGuideVisualKind visual;
}

class GamePresentationDefinition {
  const GamePresentationDefinition({
    required this.id,
    required this.loadingLabel,
    required this.durationLabel,
    required this.guideDurationText,
    required this.homeAspectRatio,
    required this.homePreview,
    required this.guidePages,
  });

  final String id;
  final String loadingLabel;
  final String durationLabel;
  final String guideDurationText;
  final double homeAspectRatio;
  final GameHomePreviewKind homePreview;
  final List<GameGuidePageDefinition> guidePages;
}

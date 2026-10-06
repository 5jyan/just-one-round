enum GameHomePreviewKind {
  dungDodgeV2,
  gravitySwitch,
  appleGameV2,
  numberRush,
  mamaDuckTrail,
  midnightSnake,
  sausageDachshund,
  beatTheDealer,
  tenPitchSlugger,
  ramenTimer,
  bathhouseSort,
  lilyFrog,
  netBoat,
  moleReaction,
  westernDuel,
  windDarts,
}

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
  mamaObserve,
  mamaRecall,
  mamaFailure,
  snakeButtons,
  snakeQueue,
  snakeGrow,
  snakeCollision,
  sausageSwipe,
  sausageGrow,
  sausageCollision,
  dealerGoal,
  dealerBet,
  dealerChoice,
  dealerResult,
  sluggerTap,
  sluggerTiming,
  sluggerDistance,
  sluggerMagic,
  sluggerScore,
  ramenCalibration,
  ramenCheckpoints,
  ramenResult,
  bathhouseControls,
  bathhouseQueue,
  bathhouseUnlock,
  bathhouseScoring,
  lilyOrbit,
  lilyTangent,
  lilySpeed,
  lilyScoring,
  lilyBonus,
  lilyFailure,
  netBoatTurn,
  netBoatClose,
  netBoatScore,
  netBoatDifficulty,
  netBoatFailure,
  netBoatLimit,
  moleReaction,
  westernWait,
  westernDraw,
  westernResult,
  windDartsHold,
  windDartsWind,
  windDartsDistance,
  windDartsScoring,
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
    required this.durationLabel,
    required this.guideDurationText,
    required this.homeAspectRatio,
    required this.homePreview,
    required this.guidePages,
  });

  final String id;
  final String durationLabel;
  final String guideDurationText;
  final double homeAspectRatio;
  final GameHomePreviewKind homePreview;
  final List<GameGuidePageDefinition> guidePages;
}

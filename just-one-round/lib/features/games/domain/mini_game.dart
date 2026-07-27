import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';

enum MiniGamePhase { countdown, playing, finished }

enum MiniGameHudStyle {
  standard,
  survivalTime,
  failedBakery,
  appleGame,
  numberRush,
}

class MiniGameHudState {
  const MiniGameHudState({
    required this.phase,
    required this.score,
    required this.elapsedSeconds,
    required this.remainingSeconds,
    required this.countdownNumber,
    this.distance = 0,
    this.combo = 0,
    this.perfects = 0,
  });

  final MiniGamePhase phase;
  final int score;
  final int elapsedSeconds;
  final int? remainingSeconds;
  final int countdownNumber;
  final int distance;
  final int combo;
  final int perfects;
}

abstract interface class MiniGameController {
  FlameGame get flameGame;
  ValueListenable<MiniGameHudState> get hud;

  void interrupt();
  void disposeController();
}

typedef MiniGameFactory =
    MiniGameController Function({
      required Duration gameDuration,
      required Duration countdownDuration,
      required ValueChanged<GameResult> onFinished,
    });

class MiniGameDefinition {
  const MiniGameDefinition({
    required this.id,
    required this.create,
    required this.countdownInstruction,
    required this.playingInstruction,
    required this.scoreLabel,
    required this.formatScore,
    this.hudScoreFormatter,
    this.defaultDuration = const Duration(seconds: 60),
    this.hudStyle = MiniGameHudStyle.standard,
    this.resultUnitLabel = '0.01초',
  });

  final String id;
  final MiniGameFactory create;
  final String countdownInstruction;
  final String playingInstruction;
  final String scoreLabel;
  final String Function(int score) formatScore;
  final String Function(int score)? hudScoreFormatter;
  final Duration defaultDuration;
  final MiniGameHudStyle hudStyle;
  final String resultUnitLabel;

  String formatHudScore(int score) => (hudScoreFormatter ?? formatScore)(score);
}

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/beat_the_dealer/domain/beat_the_dealer_rules.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';

enum BeatTheDealerPhase {
  countdown,
  dealerPreview,
  betting,
  playerTurn,
  dealerTurn,
  resolving,
  finished,
}

class BeatTheDealerGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  BeatTheDealerGame({
    required this.onFinished,
    required int attemptOrdinal,
    this.challengeSeed,
    this.gameDuration = BeatTheDealerRules.gameDuration,
    this.countdownDuration = const Duration(seconds: 3),
    DateTime? seedInstant,
  }) : rounds = BeatTheDealerRules.generateRounds(
         challengeSeed ??
             BeatTheDealerRules.dailySeed(
               seedInstant ?? DateTime.now(),
               attemptOrdinal: attemptOrdinal,
             ),
       ),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: BeatTheDealerRules.startingCoins,
           elapsedSeconds: 0,
           remainingSeconds: gameDuration.inSeconds,
           countdownNumber: countdownDuration.inSeconds,
         ),
       );

  static final logicalSize = Vector2(360, 640);
  static final backgroundSize = Vector2(360, 840);

  final Duration gameDuration;
  final Duration countdownDuration;
  final int? challengeSeed;
  final ValueChanged<GameResult> onFinished;
  final List<BeatTheDealerRound> rounds;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _BeatTheDealerTable _table;
  var _phase = BeatTheDealerPhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _phaseRemaining = 0.0;
  var _roundIndex = 0;
  var _coins = BeatTheDealerRules.startingCoins;
  var _bet = BeatTheDealerRules.minimumBet;
  var _playerCardCount = 0;
  var _dealerCardCount = 1;
  static const _initialDealerRevealDuration = 1.0;
  static const _additionalDealerRevealDuration = 1.0;

  var _dealerRevealDuration = _initialDealerRevealDuration;
  var _hasFinished = false;
  var _assetsReady = false;
  var _visualElapsed = 0.0;
  var _dealAnimationStartedAt = 0.0;
  var _dealAnimationUntil = 0.0;
  var _resultAnimationStartedAt = 0.0;
  var _chipFxStartedAt = -10.0;
  var _betLimitMessageUntil = -10.0;
  var _aceGiftAnimationStartedAt = -10.0;
  String? _betLimitMessage;
  BeatTheDealerSettlement? _lastSettlement;

  BeatTheDealerPhase get gamePhase => _phase;
  int get coins => _coins;
  int get bet => _bet;
  int get roundIndex => _roundIndex;
  bool get isFinalRound => _roundIndex == BeatTheDealerRules.roundCount - 1;
  int get maximumBet =>
      BeatTheDealerRules.maximumLegalBet(_coins, roundIndex: _roundIndex);
  @visibleForTesting
  String? get activeBetLimitMessage =>
      _visualElapsed < _betLimitMessageUntil ? _betLimitMessage : null;
  int get visibleCardCount => _playerCardCount;
  @visibleForTesting
  bool get isAceGiftEffectActive =>
      _roundIndex == BeatTheDealerRules.aceGiftRoundIndex &&
      currentRound.hasAceGift &&
      _visualElapsed - _aceGiftAnimationStartedAt < 1.5;
  int get visibleDealerCardCount => _dealerCardCount;
  BeatTheDealerRound get currentRound => rounds[_roundIndex];
  List<BeatTheDealerCard> get playerHand => _playerCardCount == 0
      ? const []
      : currentRound.playerHandAfter(_playerCardCount);
  List<BeatTheDealerCard> get dealerHand => currentRound.dealerHandAfterPlayer(
    max(_playerCardCount, BeatTheDealerRules.initialCardCount),
  );
  List<BeatTheDealerCard> get visibleDealerHand =>
      dealerHand.take(_dealerCardCount).toList(growable: false);
  bool get isDealerCardFaceVisible =>
      _phase != BeatTheDealerPhase.dealerTurn ||
      _phaseRemaining <= _dealerRevealDuration / 2;

  @override
  Color backgroundColor() => const Color(0xFF120F25);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;

    final loaded = await images.loadAll([
      'beat_the_dealer/background_map_v3.png',
      'beat_the_dealer/dealer_idle_sheet_v3.png',
      'beat_the_dealer/dealer_deal_sheet_v3.png',
      'beat_the_dealer/dealer_win_sheet_v3.png',
      'beat_the_dealer/dealer_lose_sheet_v3.png',
      'beat_the_dealer/card_front_v3.png',
      'beat_the_dealer/card_back_v3.png',
      'beat_the_dealer/coin_v3.png',
      'beat_the_dealer/suit_icons_v3.png',
      'beat_the_dealer/suit_icons_small_v3.png',
      'beat_the_dealer/rank_glyphs_v3.png',
      'beat_the_dealer/royal_faces_v3.png',
      'beat_the_dealer/chip_fx_sheet_v3.png',
    ]);
    await world.add(
      SpriteComponent(
        sprite: Sprite(loaded[0]),
        position: Vector2(0, -100),
        size: backgroundSize,
        priority: -20,
      ),
    );
    _table = _BeatTheDealerTable(
      game: this,
      dealerIdleAtlas: loaded[1],
      dealerDealAtlas: loaded[2],
      dealerWinAtlas: loaded[3],
      dealerLoseAtlas: loaded[4],
      cardFront: Sprite(loaded[5]),
      cardBack: Sprite(loaded[6]),
      coin: Sprite(loaded[7]),
      suitAtlas: loaded[8],
      smallSuitAtlas: loaded[9],
      rankAtlas: loaded[10],
      royalAtlas: loaded[11],
      chipFxAtlas: loaded[12],
    );
    await world.add(_table);
    _assetsReady = true;

    if (countdownDuration == Duration.zero) _beginRound();
    _publishHud();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hasFinished || !_assetsReady) return;
    _visualElapsed += dt;

    if (_phase == BeatTheDealerPhase.countdown) {
      _countdownElapsed += dt;
      if (_countdownElapsed >= _seconds(countdownDuration)) _beginRound();
      _publishHud();
      return;
    }

    _playingElapsed += dt;
    if (_playingElapsed >= _seconds(gameDuration)) {
      _playingElapsed = _seconds(gameDuration);
      _finishFromTimeout();
      return;
    }

    _phaseRemaining = max(0, _phaseRemaining - dt);
    if (_phaseRemaining <= 0) {
      switch (_phase) {
        case BeatTheDealerPhase.dealerPreview:
          _startBetting();
        case BeatTheDealerPhase.betting:
          _confirmBet();
        case BeatTheDealerPhase.playerTurn:
          _startDealerTurn();
        case BeatTheDealerPhase.dealerTurn:
          _advanceDealerTurn();
        case BeatTheDealerPhase.resolving:
          _advanceRound();
        case BeatTheDealerPhase.countdown || BeatTheDealerPhase.finished:
          break;
      }
    }
    _publishHud();
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    tapLogicalPosition(camera.viewport.globalToLocal(event.canvasPosition));
  }

  @visibleForTesting
  void tapLogicalPosition(Vector2 position) {
    if (_hasFinished || !_assetsReady) return;
    final offset = Offset(position.x, position.y);
    if (_phase == BeatTheDealerPhase.betting) {
      if (_BeatTheDealerTable.minusButton.contains(offset)) {
        _setBet(_bet - BeatTheDealerRules.betStep);
      } else if (_BeatTheDealerTable.plusButton.contains(offset)) {
        _setBet(_bet + BeatTheDealerRules.betStep);
      } else if (_BeatTheDealerTable.confirmButton.contains(offset)) {
        _confirmBet();
      }
      return;
    }
    if (_phase != BeatTheDealerPhase.playerTurn) return;
    if (_BeatTheDealerTable.hitButton.contains(offset)) {
      _hit();
    } else if (_BeatTheDealerTable.standButton.contains(offset)) {
      _startDealerTurn();
    }
  }

  void _beginRound() {
    _phase = BeatTheDealerPhase.dealerPreview;
    _phaseRemaining = 0.65;
    _playerCardCount = 0;
    _dealerCardCount = 1;
    _lastSettlement = null;
    _betLimitMessage = null;
    _bet = BeatTheDealerRules.normalizeBet(
      _bet,
      _coins,
      roundIndex: _roundIndex,
    );
    _publishHud();
  }

  void _startBetting() {
    _phase = BeatTheDealerPhase.betting;
    _phaseRemaining = _seconds(BeatTheDealerRules.bettingDuration);
    if (currentRound.hasAceGift) {
      _aceGiftAnimationStartedAt = _visualElapsed;
    }
  }

  void _setBet(int requested) {
    final next = BeatTheDealerRules.normalizeBet(
      requested,
      _coins,
      roundIndex: _roundIndex,
    );
    if (next == _bet) {
      if (requested < _bet) {
        _showBetLimitMessage('최소 베팅은 5코인이에요');
      } else if (requested > _bet) {
        final roundLimit = BeatTheDealerRules.maximumBetForRound(_roundIndex);
        _showBetLimitMessage(
          _coins < roundLimit
              ? '보유 코인까지만 걸 수 있어요'
              : '최대 $roundLimit코인까지 걸 수 있어요',
        );
      }
      return;
    }
    _bet = next;
    _betLimitMessage = null;
    _chipFxStartedAt = _visualElapsed;
    unawaited(HapticFeedback.selectionClick());
  }

  void _showBetLimitMessage(String message) {
    _betLimitMessage = message;
    _betLimitMessageUntil = _visualElapsed + 1.4;
    unawaited(HapticFeedback.lightImpact());
  }

  void _confirmBet() {
    if (_phase != BeatTheDealerPhase.betting) return;
    _betLimitMessage = null;
    _bet = BeatTheDealerRules.normalizeBet(
      _bet,
      _coins,
      roundIndex: _roundIndex,
    );
    if (_bet == 0) {
      _finish(GameEndType.gameOver);
      return;
    }
    _playerCardCount = BeatTheDealerRules.initialCardCount;
    _dealAnimationStartedAt = _visualElapsed;
    _dealAnimationUntil = _visualElapsed + 0.55;
    final player = BeatTheDealerRules.handValue(playerHand);
    final dealer = BeatTheDealerRules.handValue(dealerHand.take(2).toList());
    if (player.isBlackjack || dealer.isBlackjack) {
      _startDealerTurn();
    } else {
      _phase = BeatTheDealerPhase.playerTurn;
      _phaseRemaining = _seconds(BeatTheDealerRules.decisionDuration);
    }
    unawaited(HapticFeedback.mediumImpact());
  }

  void _hit() {
    if (_phase != BeatTheDealerPhase.playerTurn) return;
    _playerCardCount++;
    _dealAnimationStartedAt = _visualElapsed;
    _dealAnimationUntil = _visualElapsed + 0.45;
    _phaseRemaining = _seconds(BeatTheDealerRules.decisionDuration);
    unawaited(HapticFeedback.selectionClick());
    final value = BeatTheDealerRules.handValue(playerHand);
    if (value.isBust || value.total == BeatTheDealerRules.blackjackLimit) {
      _startDealerTurn();
    }
  }

  void _startDealerTurn() {
    if (_phase != BeatTheDealerPhase.playerTurn &&
        _phase != BeatTheDealerPhase.betting) {
      return;
    }
    _phase = BeatTheDealerPhase.dealerTurn;
    _dealerCardCount = min(2, dealerHand.length);
    _beginDealerReveal(_initialDealerRevealDuration);
  }

  void _beginDealerReveal(double duration) {
    _dealerRevealDuration = duration;
    _phaseRemaining = duration;
    _dealAnimationStartedAt = _visualElapsed;
    _dealAnimationUntil = _visualElapsed + min(duration, 0.45);
    unawaited(HapticFeedback.selectionClick());
  }

  void _advanceDealerTurn() {
    if (_phase != BeatTheDealerPhase.dealerTurn) return;
    final visibleDealer = BeatTheDealerRules.handValue(visibleDealerHand);
    final dealerMustStop =
        visibleDealer.isBust ||
        visibleDealer.total >= BeatTheDealerRules.dealerStandTotal ||
        _dealerCardCount >= dealerHand.length;
    if (dealerMustStop) {
      _settleRound();
      return;
    }
    _dealerCardCount++;
    _beginDealerReveal(_additionalDealerRevealDuration);
  }

  void _settleRound() {
    if (_phase != BeatTheDealerPhase.dealerTurn) return;
    final settlement = BeatTheDealerRules.settle(
      coins: _coins,
      bet: _bet,
      playerHand: playerHand,
      dealerHand: dealerHand,
      roundIndex: _roundIndex,
    );
    _coins = settlement.coins;
    _lastSettlement = settlement;
    _resultAnimationStartedAt = _visualElapsed;
    _phase = BeatTheDealerPhase.resolving;
    _phaseRemaining = 1.2;
    unawaited(
      settlement.payout > 0
          ? HapticFeedback.mediumImpact()
          : settlement.payout < 0
          ? HapticFeedback.heavyImpact()
          : HapticFeedback.selectionClick(),
    );
  }

  void _advanceRound() {
    if (_coins < BeatTheDealerRules.minimumBet) {
      _finish(GameEndType.gameOver);
      return;
    }
    if (_roundIndex + 1 >= rounds.length) {
      _finish(GameEndType.clear);
      return;
    }
    _roundIndex++;
    _beginRound();
  }

  void _finishFromTimeout() {
    if (_phase == BeatTheDealerPhase.playerTurn ||
        _phase == BeatTheDealerPhase.dealerTurn) {
      final settlement = BeatTheDealerRules.settle(
        coins: _coins,
        bet: _bet,
        playerHand: playerHand,
        dealerHand: dealerHand,
        roundIndex: _roundIndex,
      );
      _coins = settlement.coins;
      _lastSettlement = settlement;
    }
    _finish(GameEndType.timeUp);
  }

  void _finish(GameEndType endType) {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = BeatTheDealerPhase.finished;
    _publishHud();
    pauseEngine();
    onFinished(
      GameResult(
        score: _coins,
        starsCollected: 0,
        collisions: 0,
        duration: Duration(
          milliseconds: max(1, (_playingElapsed * 1000).round()),
        ),
        endType: endType,
      ),
    );
  }

  void _publishHud() {
    final countdown = max(
      0,
      (_seconds(countdownDuration) - _countdownElapsed).ceil(),
    );
    hud.value = MiniGameHudState(
      phase: switch (_phase) {
        BeatTheDealerPhase.countdown => MiniGamePhase.countdown,
        BeatTheDealerPhase.finished => MiniGamePhase.finished,
        _ => MiniGamePhase.playing,
      },
      score: _coins,
      elapsedSeconds: _playingElapsed.floor(),
      remainingSeconds: max(
        0,
        gameDuration.inSeconds - _playingElapsed.floor(),
      ),
      countdownNumber: countdown,
    );
  }

  static double _seconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;

  @override
  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = BeatTheDealerPhase.finished;
    _publishHud();
    pauseEngine();
  }

  @override
  void disposeController() => hud.dispose();
}

class _BeatTheDealerTable extends PositionComponent {
  _BeatTheDealerTable({
    required this.game,
    required this.dealerIdleAtlas,
    required this.dealerDealAtlas,
    required this.dealerWinAtlas,
    required this.dealerLoseAtlas,
    required this.cardFront,
    required this.cardBack,
    required this.coin,
    required this.suitAtlas,
    required this.smallSuitAtlas,
    required this.rankAtlas,
    required this.royalAtlas,
    required this.chipFxAtlas,
  }) : super(size: BeatTheDealerGame.logicalSize, priority: 0);

  static final minusButton = Rect.fromLTWH(28, 488, 72, 64);
  static final plusButton = Rect.fromLTWH(260, 488, 72, 64);
  static final confirmButton = Rect.fromLTWH(48, 562, 264, 58);
  static final hitButton = Rect.fromLTWH(20, 552, 152, 64);
  static final standButton = Rect.fromLTWH(188, 552, 152, 64);
  static const cardSize = Size(72, 100);
  static const hudAmountFontSize = 18.0;
  static const hudAmountColor = Color(0xFFFFE16A);
  static const hudContentOffsetY = 2.0;

  final BeatTheDealerGame game;
  final ui.Image dealerIdleAtlas;
  final ui.Image dealerDealAtlas;
  final ui.Image dealerWinAtlas;
  final ui.Image dealerLoseAtlas;
  final Sprite cardFront;
  final Sprite cardBack;
  final Sprite coin;
  final ui.Image suitAtlas;
  final ui.Image smallSuitAtlas;
  final ui.Image rankAtlas;
  final ui.Image royalAtlas;
  final ui.Image chipFxAtlas;
  final Paint _pixelPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _renderDealerCharacter(canvas);

    // Keep the two HUD pills on one baseline with equal vertical breathing room.
    const coinPanel = Rect.fromLTWH(56, 25, 86, 40);
    _panel(canvas, coinPanel);
    _coinAmount(
      canvas,
      rect: coinPanel.translate(0, hudContentOffsetY),
      amount: game.coins,
      fontSize: hudAmountFontSize,
      coinSize: 22,
      gap: 6,
    );
    // Match the coin amount's type scale and color, with room for `10/10 판`.
    const roundPanel = Rect.fromLTWH(254, 25, 88, 40);
    _panel(canvas, roundPanel);
    final roundLabelColor = game.roundIndex + 1 == 3
        ? const Color(0xFFFFFFFF)
        : hudAmountColor;
    _centerText(
      canvas,
      '${game.roundIndex + 1}/${BeatTheDealerRules.roundCount} 판',
      roundPanel.translate(0, hudContentOffsetY),
      size: hudAmountFontSize,
      color: roundLabelColor,
    );

    _renderDealerCards(canvas);
    _renderPlayerCards(canvas);
    _renderStatus(canvas);
    _renderControls(canvas);
  }

  void _renderDealerCharacter(Canvas canvas) {
    final settlement = game._lastSettlement;
    final isDealing = game._visualElapsed < game._dealAnimationUntil;
    final isResolving =
        game.gamePhase == BeatTheDealerPhase.resolving &&
        settlement?.payout != 0;
    final dealerState = isDealing
        ? (dealerDealAtlas, 6, 3, 0.09)
        : isResolving
        ? settlement!.payout < 0
              ? (dealerWinAtlas, 4, 2, 0.14)
              : (dealerLoseAtlas, 4, 2, 0.14)
        : (dealerIdleAtlas, 4, 2, 0.22);
    _renderAtlasFrame(
      canvas,
      dealerState.$1,
      frameCount: dealerState.$2,
      columns: dealerState.$3,
      frameSize: 64,
      secondsPerFrame: dealerState.$4,
      elapsed: isDealing
          ? game._visualElapsed - game._dealAnimationStartedAt
          : isResolving
          ? game._visualElapsed - game._resultAnimationStartedAt
          : game._visualElapsed,
      destination: const Rect.fromLTWH(116, 8, 128, 128),
    );
  }

  void _renderAtlasFrame(
    Canvas canvas,
    ui.Image atlas, {
    required int frameCount,
    required int columns,
    required double frameSize,
    required double secondsPerFrame,
    required double elapsed,
    required Rect destination,
  }) {
    final frame = (elapsed / secondsPerFrame).floor() % frameCount;
    final source = Rect.fromLTWH(
      (frame % columns) * frameSize,
      (frame ~/ columns) * frameSize,
      frameSize,
      frameSize,
    );
    canvas.drawImageRect(atlas, source, destination, _pixelPaint);
  }

  void _renderDealerCards(Canvas canvas) {
    final revealAll =
        game.gamePhase == BeatTheDealerPhase.dealerTurn ||
        game.gamePhase == BeatTheDealerPhase.resolving ||
        game.gamePhase == BeatTheDealerPhase.finished;
    final cards = revealAll
        ? game.visibleDealerHand
        : <BeatTheDealerCard>[game.currentRound.dealerUpCard];
    final cardBackVisible = !revealAll;
    final count = revealAll
        ? game.dealerHand.length
        : cards.length + (cardBackVisible ? 1 : 0);
    final step = revealAll
        ? _fanStep(count, maxWidth: 288, maximumStep: 64)
        : 18.0;
    final startX = (360 - (cardSize.width + step * (count - 1))) / 2;
    if (cardBackVisible) {
      cardBack.render(
        canvas,
        position: Vector2(startX + step, 126),
        size: Vector2(cardSize.width, cardSize.height),
        overridePaint: _pixelPaint,
      );
    }
    for (var index = 0; index < cards.length; index++) {
      final position = Offset(startX + step * index, 126);
      if (index == cards.length - 1 &&
          index > 0 &&
          game.gamePhase == BeatTheDealerPhase.dealerTurn) {
        _renderFlippingCard(canvas, cards[index], position);
      } else {
        _renderCard(canvas, cards[index], position);
      }
    }
    if (revealAll) {
      if (game.isDealerCardFaceVisible) {
        final value = BeatTheDealerRules.handValue(cards);
        _totalPill(
          canvas,
          text: value.isBust ? '딜러 ${value.total} · 버스트' : '딜러 ${value.total}',
          rect: const Rect.fromLTWH(116, 232, 128, 28),
        );
      } else {
        _totalPill(
          canvas,
          text: '카드 공개 중...',
          rect: const Rect.fromLTWH(116, 232, 128, 28),
        );
      }
    } else {
      _centerText(
        canvas,
        '딜러 공개 카드',
        const Rect.fromLTWH(112, 232, 136, 26),
        size: 13,
        color: const Color(0xFFD8C4E8),
      );
    }
  }

  void _renderFlippingCard(
    Canvas canvas,
    BeatTheDealerCard card,
    Offset position,
  ) {
    final progress = (1 - game._phaseRemaining / game._dealerRevealDuration)
        .clamp(0.0, 1.0);
    final scaleX = max(0.05, (cos(progress * pi)).abs());
    final showingFront = progress >= 0.5;
    canvas.save();
    canvas.translate(position.dx + cardSize.width / 2, position.dy);
    canvas.scale(scaleX, 1);
    canvas.translate(-cardSize.width / 2, 0);
    if (showingFront) {
      _renderCard(canvas, card, Offset.zero);
    } else {
      cardBack.render(
        canvas,
        position: Vector2.zero(),
        size: Vector2(cardSize.width, cardSize.height),
        overridePaint: _pixelPaint,
      );
    }
    canvas.restore();
  }

  void _renderPlayerCards(Canvas canvas) {
    final cards = game.playerHand;
    final showingGiftBeforeBet =
        game.gamePhase == BeatTheDealerPhase.betting &&
        game.currentRound.hasAceGift;
    if (cards.isEmpty && !showingGiftBeforeBet) return;
    final step = _fanStep(cards.length, maxWidth: 320);
    final startX = (360 - (cardSize.width + step * (cards.length - 1))) / 2;
    final giftElapsed = game._visualElapsed - game._aceGiftAnimationStartedAt;
    final flyingGift = game.isAceGiftEffectActive && giftElapsed < 0.55;
    for (var index = 0; index < cards.length; index++) {
      if (index == 1 && flyingGift) continue;
      _renderCard(canvas, cards[index], Offset(startX + step * index, 270));
    }
    if (game.isAceGiftEffectActive || showingGiftBeforeBet) {
      final glow = (1 - giftElapsed / 1.5).clamp(0.0, 1.0);
      final landing = cards.isEmpty
          ? Offset((360 - cardSize.width) / 2, 270)
          : Offset(startX + step, 270);
      final progress = (giftElapsed / 0.55).clamp(0.0, 1.0);
      final eased = 1 - pow(1 - progress, 3).toDouble();
      final position = flyingGift
          ? Offset.lerp(const Offset(144, 144), landing, eased)!
          : landing;
      final giftCard = Rect.fromLTWH(
        position.dx,
        position.dy,
        cardSize.width,
        cardSize.height,
      );
      if (cards.isEmpty || flyingGift) {
        final giftedAce = game.currentRound.playerHandAfter(
          BeatTheDealerRules.initialCardCount,
        )[1];
        _renderCard(canvas, giftedAce, position);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          giftCard.inflate(4 + 5 * glow),
          const Radius.circular(8),
        ),
        Paint()
          ..color = const Color(0xFFFFE16A).withValues(alpha: 0.75 * glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      for (final offset in const [
        Offset(-12, 4),
        Offset(84, 18),
        Offset(-6, 80),
        Offset(80, 92),
      ]) {
        canvas.drawCircle(
          giftCard.topLeft + offset,
          2 + 3 * glow,
          Paint()..color = const Color(0xFFFFE16A).withValues(alpha: glow),
        );
      }
    }
    if (cards.isEmpty) return;
    final value = BeatTheDealerRules.handValue(cards);
    final suffix = value.isBlackjack
        ? ' · 블랙잭!'
        : value.isBust
        ? ' · 버스트'
        : value.isSoft
        ? ' · A 포함'
        : '';
    _totalPill(
      canvas,
      text: '내 합계 ${value.total}$suffix',
      rect: const Rect.fromLTWH(100, 376, 160, 30),
    );
  }

  double _fanStep(
    int count, {
    required double maxWidth,
    double maximumStep = 48,
  }) {
    if (count <= 1) return 0;
    return min(maximumStep, (maxWidth - cardSize.width) / (count - 1));
  }

  void _renderCard(Canvas canvas, BeatTheDealerCard card, Offset position) {
    cardFront.render(
      canvas,
      position: Vector2(position.dx, position.dy),
      size: Vector2(cardSize.width, cardSize.height),
      overridePaint: _pixelPaint,
    );
    _renderCorner(canvas, card, position);
    canvas.save();
    canvas.translate(
      position.dx + cardSize.width,
      position.dy + cardSize.height,
    );
    canvas.rotate(pi);
    _renderCorner(canvas, card, Offset.zero);
    canvas.restore();
    _renderCardCenter(canvas, card, position);
  }

  void _renderCorner(Canvas canvas, BeatTheDealerCard card, Offset position) {
    canvas.drawImageRect(
      rankAtlas,
      Rect.fromLTWH(card.rank.index * 18, card.isRed ? 18 : 0, 18, 18),
      Rect.fromLTWH(position.dx + 7, position.dy + 5, 18, 18),
      _pixelPaint,
    );
    final isNumberCard = card.rank.index < BeatTheDealerRank.jack.index;
    if (isNumberCard) {
      _renderSmallSuit(
        canvas,
        card.suit,
        Offset(position.dx + 8, position.dy + 21),
      );
    } else {
      _renderSuit(
        canvas,
        card.suit,
        Offset(position.dx + 7, position.dy + 21),
        const Size(12, 12),
      );
    }
  }

  void _renderCardCenter(
    Canvas canvas,
    BeatTheDealerCard card,
    Offset position,
  ) {
    if (card.rank.index >= BeatTheDealerRank.jack.index) {
      final source = Rect.fromLTWH(
        (card.rank.index - BeatTheDealerRank.jack.index) * 48,
        card.isRed ? 60 : 0,
        48,
        60,
      );
      canvas.drawImageRect(
        royalAtlas,
        source,
        Rect.fromLTWH(position.dx + 12, position.dy + 20, 48, 60),
        _pixelPaint,
      );
      return;
    }
    if (card.rank == BeatTheDealerRank.ace) {
      _renderSuit(
        canvas,
        card.suit,
        Offset(position.dx + 24, position.dy + 38),
        const Size(24, 24),
      );
      return;
    }
    final pipCount = card.hardValue;
    final positions = _pipPositions(pipCount);
    for (var index = 0; index < positions.length; index++) {
      final pip = positions[index];
      final pipPosition = Offset(
        position.dx + pip.dx - 6,
        position.dy + pip.dy - 6,
      );
      _renderSuitRotated(canvas, card.suit, pipPosition, inverted: pip.dy > 50);
    }
  }

  List<Offset> _pipPositions(int count) => switch (count) {
    2 => const [Offset(36, 27), Offset(36, 73)],
    3 => const [Offset(36, 27), Offset(36, 50), Offset(36, 73)],
    4 => const [Offset(24, 29), Offset(48, 29), Offset(24, 71), Offset(48, 71)],
    5 => const [
      Offset(24, 29),
      Offset(48, 29),
      Offset(36, 50),
      Offset(24, 71),
      Offset(48, 71),
    ],
    6 => const [
      Offset(24, 27),
      Offset(48, 27),
      Offset(24, 50),
      Offset(48, 50),
      Offset(24, 73),
      Offset(48, 73),
    ],
    7 => const [
      Offset(24, 25),
      Offset(48, 25),
      Offset(36, 37),
      Offset(24, 50),
      Offset(48, 50),
      Offset(24, 75),
      Offset(48, 75),
    ],
    8 => const [
      Offset(24, 25),
      Offset(48, 25),
      Offset(36, 37),
      Offset(24, 50),
      Offset(48, 50),
      Offset(36, 63),
      Offset(24, 75),
      Offset(48, 75),
    ],
    9 => const [
      Offset(24, 24),
      Offset(48, 24),
      Offset(24, 41),
      Offset(48, 41),
      Offset(36, 50),
      Offset(24, 59),
      Offset(48, 59),
      Offset(24, 76),
      Offset(48, 76),
    ],
    _ => const [
      Offset(24, 23),
      Offset(48, 23),
      Offset(36, 34),
      Offset(24, 41),
      Offset(48, 41),
      Offset(24, 59),
      Offset(48, 59),
      Offset(36, 66),
      Offset(24, 77),
      Offset(48, 77),
    ],
  };

  void _renderSuitRotated(
    Canvas canvas,
    BeatTheDealerSuit suit,
    Offset position, {
    required bool inverted,
  }) {
    if (!inverted) {
      _renderSuit(canvas, suit, position, const Size(12, 12));
      return;
    }
    canvas.save();
    canvas.translate(position.dx + 6, position.dy + 6);
    canvas.rotate(pi);
    _renderSuit(canvas, suit, const Offset(-6, -6), const Size(12, 12));
    canvas.restore();
  }

  void _renderSuit(
    Canvas canvas,
    BeatTheDealerSuit suit,
    Offset position,
    Size size,
  ) {
    canvas.drawImageRect(
      suitAtlas,
      Rect.fromLTWH(suit.index * 12, 0, 12, 12),
      position & size,
      _pixelPaint,
    );
  }

  void _renderSmallSuit(
    Canvas canvas,
    BeatTheDealerSuit suit,
    Offset position,
  ) {
    canvas.drawImageRect(
      smallSuitAtlas,
      Rect.fromLTWH(suit.index * 10, 0, 10, 10),
      position & const Size(10, 10),
      _pixelPaint,
    );
  }

  void _renderStatus(Canvas canvas) {
    final settlement = game._lastSettlement;
    final label =
        game.activeBetLimitMessage ??
        (game.isAceGiftEffectActive ? '7판 선물! A 카드 등장!' : null) ??
        switch (game.gamePhase) {
          BeatTheDealerPhase.countdown => '잠시 후 시작!',
          BeatTheDealerPhase.dealerPreview => '이 카드를 보고 배팅!',
          BeatTheDealerPhase.betting =>
            game.isFinalRound
                ? '마지막 판 · 최대 100코인!'
                : game.currentRound.hasAceGift
                ? '7판 특별 선물 · A 카드 확정!'
                : '얼마를 걸까?',
          BeatTheDealerPhase.playerTurn => '한 장 더 받을까?',
          BeatTheDealerPhase.dealerTurn => '딜러가 카드를 공개합니다',
          BeatTheDealerPhase.resolving => switch (settlement?.outcome) {
            BeatTheDealerOutcome.blackjack => '블랙잭!  +${settlement?.payout}',
            BeatTheDealerOutcome.win => '승리!  +${settlement?.payout}',
            BeatTheDealerOutcome.push => '무승부!  그대로',
            BeatTheDealerOutcome.lose => '패배!  ${settlement?.payout}',
            null => '',
          },
          BeatTheDealerPhase.finished => '게임 끝!',
        };
    _centerText(
      canvas,
      label,
      const Rect.fromLTWH(56, 414, 248, 34),
      size: 17,
      color: const Color(0xFFFFE16A),
    );
    if (game.gamePhase
        case BeatTheDealerPhase.betting || BeatTheDealerPhase.playerTurn) {
      _renderPhaseTimer(canvas);
    }
  }

  void _renderPhaseTimer(Canvas canvas) {
    final total = game.gamePhase == BeatTheDealerPhase.betting
        ? BeatTheDealerRules.bettingDuration
        : BeatTheDealerRules.decisionDuration;
    final fraction = (game._phaseRemaining / total.inMilliseconds * 1000).clamp(
      0.0,
      1.0,
    );
    final color = fraction <= 0.25
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFFFD447);
    const track = Rect.fromLTWH(60, 456, 240, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(5)),
      Paint()..color = const Color(0xCC20172F),
    );
    final fill = Rect.fromLTWH(
      track.left + 2,
      track.top + 2,
      (track.width - 4) * fraction,
      track.height - 4,
    );
    if (fill.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, const Radius.circular(3)),
        Paint()..color = color,
      );
    }
    canvas.drawCircle(
      const Offset(45, 461),
      8,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = false,
    );
    canvas.drawLine(
      const Offset(45, 461),
      const Offset(45, 456),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..isAntiAlias = false,
    );
    canvas.drawLine(
      const Offset(45, 461),
      const Offset(49, 463),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..isAntiAlias = false,
    );
  }

  void _renderControls(Canvas canvas) {
    if (game.gamePhase == BeatTheDealerPhase.betting) {
      _button(canvas, minusButton, '-${BeatTheDealerRules.betStep}');
      _button(canvas, plusButton, '+${BeatTheDealerRules.betStep}');
      const betPanel = Rect.fromLTWH(108, 488, 144, 64);
      _betPanel(canvas, betPanel);
      _centerText(
        canvas,
        'BET',
        const Rect.fromLTWH(120, 496, 120, 14),
        size: 11,
        color: const Color(0xFFD8C4E8),
      );
      _coinAmount(
        canvas,
        rect: const Rect.fromLTWH(120, 516, 120, 28),
        amount: game.bet,
        fontSize: 26,
        coinSize: 24,
        gap: 8,
      );
      _goldButton(canvas, confirmButton, '${game.bet} 코인 걸기');
      _renderChipFx(canvas);
    } else if (game.gamePhase == BeatTheDealerPhase.playerTurn) {
      _button(canvas, hitButton, '한 장 더');
      _button(canvas, standButton, '멈추기');
    }
  }

  void _renderChipFx(Canvas canvas) {
    final elapsed = game._visualElapsed - game._chipFxStartedAt;
    if (elapsed < 0 || elapsed >= 0.52) return;
    final frame = min(3, (elapsed / 0.13).floor());
    canvas.drawImageRect(
      chipFxAtlas,
      Rect.fromLTWH((frame % 2) * 24, (frame ~/ 2) * 24, 24, 24),
      const Rect.fromLTWH(156, 470, 48, 48),
      _pixelPaint,
    );
  }

  void _totalPill(Canvas canvas, {required String text, required Rect rect}) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color(0xDC21182F),
    );
    _centerText(canvas, text, rect, size: 13, color: const Color(0xFFFFFFFF));
  }

  void _panel(Canvas canvas, Rect rect) {
    final path = _chamferedPath(rect, 6);
    canvas.drawPath(path, Paint()..color = const Color(0xE6231839));
    canvas.drawPath(
      _chamferedPath(rect.translate(0, 3), 6),
      Paint()
        ..color = const Color(0x66201431)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    final border = Paint()
      ..color = const Color(0xFF9D78C8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = false;
    canvas.drawPath(_chamferedPath(rect.deflate(1), 5), border);
    canvas.drawLine(
      Offset(rect.left + 8, rect.top + 4),
      Offset(rect.right - 8, rect.top + 4),
      Paint()..color = const Color(0x667EDEF2),
    );
  }

  void _button(Canvas canvas, Rect rect, String label) {
    final path = _chamferedPath(rect, 8);
    canvas.drawPath(path, Paint()..color = const Color(0xFF543672));
    canvas.drawPath(
      _chamferedPath(
        Rect.fromLTRB(rect.left, rect.bottom - 9, rect.right, rect.bottom),
        3,
      ),
      Paint()..color = const Color(0xFF2B1C41),
    );
    final border = Paint()
      ..color = const Color(0xFFD4B7F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = false;
    canvas.drawPath(_chamferedPath(rect.deflate(1), 7), border);
    canvas.drawLine(
      Offset(rect.left + 12, rect.top + 5),
      Offset(rect.right - 12, rect.top + 5),
      Paint()..color = const Color(0x887EDEF2),
    );
    _centerText(canvas, label, rect.translate(0, -2), size: 17);
  }

  void _betPanel(Canvas canvas, Rect rect) {
    canvas.drawPath(
      _chamferedPath(rect.translate(0, 4), 10),
      Paint()..color = const Color(0xAA120C20),
    );
    canvas.drawPath(
      _chamferedPath(rect, 10),
      Paint()..color = const Color(0xF02A183B),
    );
    canvas.drawPath(
      _chamferedPath(rect.deflate(1), 9),
      Paint()
        ..color = const Color(0xFFFFD447)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = false,
    );
    canvas.drawLine(
      Offset(rect.left + 18, rect.top + 5),
      Offset(rect.right - 18, rect.top + 5),
      Paint()
        ..color = const Color(0xFFFFF0A0)
        ..strokeWidth = 2
        ..isAntiAlias = false,
    );
  }

  void _coinAmount(
    Canvas canvas, {
    required Rect rect,
    required int amount,
    required double fontSize,
    required double coinSize,
    required double gap,
  }) {
    final amountPainter = _makeTextPainter(
      '$amount',
      size: fontSize,
      color: hudAmountColor,
    );
    final contentWidth = coinSize + gap + amountPainter.width;
    final contentLeft = rect.center.dx - contentWidth / 2;
    final coinTop = rect.center.dy - coinSize / 2;
    coin.render(
      canvas,
      position: Vector2(contentLeft, coinTop),
      size: Vector2.all(coinSize),
      overridePaint: _pixelPaint,
    );
    amountPainter.paint(
      canvas,
      Offset(
        contentLeft + coinSize + gap,
        rect.center.dy - amountPainter.height / 2,
      ),
    );
  }

  void _goldButton(Canvas canvas, Rect rect, String label) {
    final path = _chamferedPath(rect, 9);
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFD447));
    canvas.drawPath(
      _chamferedPath(
        Rect.fromLTRB(rect.left, rect.bottom - 9, rect.right, rect.bottom),
        3,
      ),
      Paint()..color = const Color(0xFFB56B12),
    );
    canvas.drawPath(
      _chamferedPath(rect.deflate(1), 8),
      Paint()
        ..color = const Color(0xFFFFF0A0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = false,
    );
    _centerText(
      canvas,
      label,
      rect.translate(0, -2),
      size: 18,
      color: const Color(0xFF21142F),
    );
  }

  Path _chamferedPath(Rect rect, double cut) => Path()
    ..moveTo(rect.left + cut, rect.top)
    ..lineTo(rect.right - cut, rect.top)
    ..lineTo(rect.right, rect.top + cut)
    ..lineTo(rect.right, rect.bottom - cut)
    ..lineTo(rect.right - cut, rect.bottom)
    ..lineTo(rect.left + cut, rect.bottom)
    ..lineTo(rect.left, rect.bottom - cut)
    ..lineTo(rect.left, rect.top + cut)
    ..close();

  void _centerText(
    Canvas canvas,
    String value,
    Rect rect, {
    required double size,
    Color color = const Color(0xFFFFFFFF),
  }) {
    final painter = _makeTextPainter(value, size: size, color: color);
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  TextPainter _makeTextPainter(
    String value, {
    required double size,
    required Color color,
    TextAlign align = TextAlign.left,
    double? width,
  }) {
    return TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Galmuri',
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width ?? double.infinity);
  }
}

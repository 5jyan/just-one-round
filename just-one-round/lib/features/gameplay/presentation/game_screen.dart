import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/core/reviews/app_review_service.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/presentation/game_end_transition.dart';
import 'package:just_one_round/features/games/apple_game_v2/apple_game_v2.dart';
import 'package:just_one_round/features/games/apple_game_v2/domain/apple_game_v2_rules.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/domain/mini_game_seed.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/games/lily_frog/presentation/lily_frog_combo_gauge.dart';
import 'package:just_one_round/features/games/net_boat/domain/net_boat_rules.dart';
import 'package:just_one_round/features/games/mole_reaction/domain/mole_reaction_rules.dart';
import 'package:just_one_round/features/games/ramen_timer/domain/ramen_timer_rules.dart';
import 'package:just_one_round/features/games/ramen_timer/ramen_timer_game.dart';
import 'package:just_one_round/features/games/western_duel/western_duel_game.dart';
import 'package:just_one_round/features/games/western_duel/domain/western_duel_opponent.dart';
import 'package:just_one_round/features/games/western_duel/domain/western_duel_rules.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_opponent.dart';
import 'package:just_one_round/features/games/wind_darts/wind_darts_game.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_input_surface.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/profile/presentation/nickname_dialog.dart';
import 'package:just_one_round/features/ranking/presentation/nearby_ranking.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';

final RegExp _generatedAnonymousNickname = RegExp(r'^신원미상#[0-9]+$');

bool _needsNicknameSetup(String? nickname) {
  final normalized = nickname?.trim() ?? '';
  return normalized.isEmpty || _generatedAnonymousNickname.hasMatch(normalized);
}

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({
    this.attempt,
    this.gameDuration,
    this.countdownDuration = const Duration(seconds: 3),
    super.key,
  });

  final Duration? gameDuration;
  final Duration countdownDuration;
  final PlayAttempt? attempt;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  late final MiniGameDefinition _definition;
  late final MiniGameController _game;
  late final DailyGameRepository _repository;
  late final RewardedAdService _rewardedAdService;
  GameResult? _result;
  GameResult? _pendingResult;
  DailyRankResult? _rankResult;
  Object? _submitError;
  var _isSubmitting = false;
  var _wasInterrupted = false;
  var _hasEnded = false;
  var _isSavingNickname = false;
  var _nicknamePromptShown = false;
  var _nicknamePromptCheckStarted = false;
  var _showExitWarning = false;
  late bool _showStartGuide;
  var _isStartGuideReady = false;
  var _isGameLoaded = false;
  var _isConfirmingStart = false;
  var _playStarted = false;
  PlayAttempt? _resolvedAttempt;
  WindDartsOpponent? _windDartsOpponent;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(dailyGameRepositoryProvider);
    _rewardedAdService = ref.read(rewardedAdServiceProvider);
    WidgetsBinding.instance.addObserver(this);
    _definition = GameRegistry.forId(widget.attempt?.gameId ?? 'dung_dodge_v2');
    final attempt = widget.attempt;
    _showStartGuide = widget.countdownDuration > Duration.zero;
    _game = _createGame();
    if (_showStartGuide) {
      final game = _game;
      if (game is WindDartsGame) game.prepareOpponentPreview();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_finishGameSetup());
    });
    if (attempt != null) unawaited(_preloadRewardedAdForNextPlay());
  }

  Future<void> _finishGameSetup() async {
    await _game.flameGame.loaded;
    if (_showStartGuide) await _game.flameGame.ready();
    if (!mounted) return;
    _isGameLoaded = true;
    if (!_hasEnded) _game.flameGame.pauseEngine();
    if ((_showStartGuide || _showExitWarning) && !_hasEnded) {
      setState(() {
        if (_showStartGuide) _isStartGuideReady = true;
      });
      return;
    }
    if (!_hasEnded && await _confirmPlayStarted()) {
      _game.flameGame.resumeEngine();
    }
  }

  MiniGameController _createGame() {
    final attempt = widget.attempt;
    final appleRulesVersion = _definition.id == 'apple_game_v2'
        ? attempt?.gameVersion ?? AppleGameV2Rules.rulesVersion
        : null;
    final challengeSeed =
        _definition.id == 'beat_the_dealer' || _definition.id == 'western_duel'
        ? MiniGameSeed.randomSeed()
        : MiniGameSeed.forAttempt(
            gameId: _definition.id,
            gameVersion: appleRulesVersion ?? attempt?.gameVersion ?? 1,
            playDate: attempt?.playDate,
            // Other games keep their shared daily/practice layouts. Blackjack
            // intentionally uses a fresh random seed for every play above.
            practiceOrdinal: attempt?.isPractice == true
                ? attempt?.practiceOrdinal ?? attempt?.ordinal ?? 1
                : null,
          );
    final gameDuration =
        widget.gameDuration ??
        _issuedAttemptDuration(widget.attempt) ??
        _definition.defaultDuration;
    if (_definition.id == 'apple_game_v2') {
      return AppleGameV2(
        gameDuration: gameDuration,
        countdownDuration: widget.countdownDuration,
        assetSet: AppleGameV2AssetSet.midnightOrchard,
        rulesVersion: appleRulesVersion!,
        random: math.Random(challengeSeed),
        onFinished: _handleFinished,
      );
    }
    return _definition.create(
      gameDuration: gameDuration,
      countdownDuration: widget.countdownDuration,
      attemptOrdinal: attempt?.ordinal ?? 1,
      challengeSeed: challengeSeed,
      onFinished: _handleFinished,
    );
  }

  Future<void> _startGame() async {
    if (_isConfirmingStart ||
        !_showStartGuide ||
        _showExitWarning ||
        _hasEnded) {
      return;
    }
    await _game.flameGame.loaded;
    if (!mounted || _hasEnded || !_showStartGuide) return;
    _isGameLoaded = true;
    if (!await _confirmPlayStarted()) return;
    if (!mounted || _hasEnded || !_showStartGuide) return;
    setState(() => _showStartGuide = false);
    _game.flameGame.resumeEngine();
  }

  Future<bool> _confirmPlayStarted() async {
    if (_playStarted) return true;
    if (_isConfirmingStart) return false;
    if (mounted) setState(() => _isConfirmingStart = true);
    try {
      final attempt = await _resolveAttemptForStart();
      if (_game is WesternDuelGame) {
        final source = _repository;
        if (attempt != null && source is! WesternDuelStartRepository) {
          throw StateError('Western duel opponent service unavailable');
        }
        final opponent = attempt == null
            ? const WesternDuelOpponent(
                nickname: '맥크리',
                reactionMilliseconds: 440,
                isBot: true,
              )
            : await (source as WesternDuelStartRepository)
                  .confirmWesternDuelStarted(attempt);
        _game.setOpponent(opponent);
      } else if (_game is WindDartsGame) {
        final source = _repository;
        final opponent = attempt == null
            ? const WindDartsOpponent(
                nickname: '서부의 단골',
                shotScores: [7, 19, 10, 20, 6, 9, 22],
                isBot: true,
              )
            : source is WindDartsStartRepository
            ? await (source as WindDartsStartRepository)
                  .confirmWindDartsStarted(attempt)
            : throw StateError('Wind darts opponent service unavailable');
        _windDartsOpponent = opponent;
        _game.setOpponent(opponent);
      } else if (attempt != null) {
        await _repository.confirmPlayStarted(attempt);
      }
      _resolvedAttempt = attempt;
      _playStarted = true;
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: WordSafeText('시작을 확인하지 못했어요. 다시 눌러 주세요.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isConfirmingStart = false);
    }
  }

  Future<PlayAttempt?> _resolveAttemptForStart() async {
    if (_resolvedAttempt != null) return _resolvedAttempt;
    final attempt = widget.attempt;
    if (attempt == null) return null;
    final resolver = attempt.resolveForSubmission;
    if (resolver == null) return attempt;
    final resolved = await resolver();
    if (resolved == null) throw const DeferredAttemptResolutionException();
    return resolved;
  }

  Future<void> _preloadRewardedAdForNextPlay() async {
    try {
      // Warm the next rewarded ad while the player is spending this attempt.
      // The ad receives its SSV session only when it is shown after the game.
      await _rewardedAdService.preload();
    } catch (error, stackTrace) {
      debugPrint('[AdWarmup] Preload from gameplay failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Duration? _issuedAttemptDuration(PlayAttempt? attempt) {
    final seconds = attempt?.gameDurationSeconds;
    return seconds == null || seconds <= 0 ? null : Duration(seconds: seconds);
  }

  bool get _isRamenResultReveal {
    final game = _game;
    return _definition.id == 'ramen_timer' &&
        game is RamenTimerGame &&
        game.gamePhase == RamenTimerPhase.resultReveal;
  }

  void _handleFinished(GameResult result) {
    if (!mounted || _hasEnded) return;
    setState(() {
      _pendingResult = result;
      _hasEnded = true;
      _showExitWarning = false;
    });
    final isMoleTimeout =
        _definition.id == 'mole_reaction' &&
        result.endType == GameEndType.timeUp;
    final isWesternInvalid =
        _definition.id == 'western_duel' && result.score == 0;
    if (isMoleTimeout || isWesternInvalid) {
      // A timeout is intentionally no-rank for the reaction game. Consume
      // the issued attempt without sending the sentinel score to the shared
      // ranking RPC.
      if (_playStarted && widget.attempt != null) {
        unawaited(_expireActiveAttempt());
      }
    } else if (widget.attempt?.isPractice != true) {
      unawaited(_submitResult(result));
    }
  }

  void _revealResult() {
    final result = _pendingResult;
    if (!mounted || result == null) return;
    setState(() {
      _result = result;
      _pendingResult = null;
    });
    _maybePromptForNickname();
  }

  void _maybePromptForNickname() {
    final rank = _rankResult;
    if (_result == null ||
        rank == null ||
        widget.attempt?.grantType != 'daily' ||
        !_needsNicknameSetup(rank.nickname) ||
        _nicknamePromptCheckStarted ||
        _nicknamePromptShown) {
      return;
    }
    _nicknamePromptCheckStarted = true;
    unawaited(_claimAndShowFirstNicknamePrompt());
  }

  Future<void> _claimAndShowFirstNicknamePrompt() async {
    try {
      final repository = _repository;
      if (repository is! FirstChallengeNicknamePromptRepository) return;
      final shouldShow =
          await (repository as FirstChallengeNicknamePromptRepository)
              .claimFirstChallengeNicknamePrompt();
      if (!mounted || !shouldShow) return;
      _nicknamePromptShown = true;
    } catch (error, stackTrace) {
      debugPrint('[NicknamePrompt] Failed to claim prompt: $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_chooseNickname());
    });
  }

  Future<void> _chooseNickname() async {
    final nickname = await showNicknameDialog(context);
    if (nickname == null || !mounted) return;
    setState(() => _isSavingNickname = true);
    try {
      await _repository.setNickname(nickname);
      final rank = await _repository.fetchDailyRank(
        playDate: widget.attempt?.playDate,
      );
      if (!mounted) return;
      setState(() => _rankResult = rank);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: WordSafeText('닉네임을 저장하지 못했어요: $error')));
    } finally {
      if (mounted) setState(() => _isSavingNickname = false);
    }
  }

  Future<void> _submitResult(GameResult result) async {
    final attempt = await _resolveAttemptForSubmission();
    if (attempt == null || attempt.isPractice) return;
    if (!mounted) return;
    setState(() => _isSubmitting = true);
    try {
      final rank = await _repository.submitScore(attempt.id, result);
      if (!mounted) return;
      setState(() => _rankResult = rank);
      _maybePromptForNickname();
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitError = error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<PlayAttempt?> _resolveAttemptForSubmission() async {
    final attempt = _resolvedAttempt ?? widget.attempt;
    if (attempt == null) return null;
    final resolver = attempt.resolveForSubmission;
    if (resolver == null) return attempt;
    final resolved = await resolver();
    if (resolved != null) return resolved;
    if (mounted) {
      setState(() => _submitError = const DeferredAttemptResolutionException());
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_hasEnded || _showStartGuide) return;
    if (shouldInterruptGame(state)) {
      if (_game is WesternDuelGame) {
        if (_game.reactionMilliseconds != null) {
          _game.interrupt();
        } else {
          unawaited(_leaveGame());
        }
        return;
      }
      _pauseForExitWarning();
    }
  }

  void _pauseForExitWarning() {
    if (_hasEnded || _showExitWarning) return;
    if (_game is WesternDuelGame) {
      if (_game.reactionMilliseconds != null) {
        _game.interrupt();
      } else {
        unawaited(_leaveGame());
      }
      return;
    }
    if (_isGameLoaded) _game.flameGame.pauseEngine();
    if (mounted) setState(() => _showExitWarning = true);
  }

  void _continueGame() {
    if (_hasEnded || !_showExitWarning) return;
    setState(() => _showExitWarning = false);
    if (_isGameLoaded && !_showStartGuide) {
      _game.flameGame.resumeEngine();
    }
  }

  Future<void> _interruptAttempt() async {
    if (_hasEnded || _wasInterrupted) return;
    final preserveRamenResult = _isRamenResultReveal;
    if (preserveRamenResult) {
      if (_isGameLoaded) _game.interrupt();
      if (_pendingResult != null || _result != null) return;
    }
    _wasInterrupted = true;
    _hasEnded = true;
    if (_isGameLoaded) _game.interrupt();
    if (mounted) setState(() {});
    final attempt = widget.attempt;
    if (_playStarted && attempt != null && !attempt.isPractice) {
      await _expireActiveAttempt();
    }
  }

  Future<void> _leaveGame() async {
    final preserveRamenResult = _isRamenResultReveal;
    await _interruptAttempt();
    if (!mounted) return;
    if (preserveRamenResult && (_pendingResult != null || _result != null)) {
      return;
    }
    _returnHome();
  }

  void _returnHome() {
    final attempt = widget.attempt;
    final isTestMode = ref.read(todayStateProvider).value?.testMode == true;
    final canRequestReview =
        _result != null &&
        _rankResult != null &&
        !isTestMode &&
        attempt != null &&
        !attempt.isPractice &&
        attempt.status != 'practice' &&
        attempt.id != 'preview-attempt' &&
        _repository is! PreviewDailyGameRepository;
    if (canRequestReview) {
      ref.read(appReviewServiceProvider).markPending();
    }
    ref.invalidate(todayStateProvider);
    context.go('/');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_hasEnded) {
      _hasEnded = true;
      if (_isGameLoaded) _game.interrupt();
      final attempt = widget.attempt;
      if (_playStarted && attempt != null && !attempt.isPractice) {
        unawaited(_expireActiveAttempt());
      }
    }
    _game.disposeController();
    super.dispose();
  }

  Future<void> _expireActiveAttempt() async {
    final attempt = _resolvedAttempt ?? widget.attempt;
    if (attempt == null || attempt.isPractice) return;
    try {
      final resolver = attempt.resolveForSubmission;
      final resolved = resolver == null ? attempt : await resolver();
      if (resolved == null || resolved.isPractice) return;
      await _repository.expireAttempt(resolved.id);
    } catch (_) {
      // Expiration is best effort. The server's stale-attempt cleanup is the
      // fallback when the app is interrupted before the claim is resolved.
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _pauseForExitWarning();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDeep,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_game case final WindDartsGame windDarts)
              WindDartsInputSurface(
                game: windDarts,
                child: GameWidget(game: _game.flameGame),
              )
            else
              GameWidget(game: _game.flameGame),
            if (_definition.id == 'number_rush' &&
                !_wasInterrupted &&
                _pendingResult == null &&
                _result == null)
              _NumberRushExitButton(onExit: _pauseForExitWarning),
            if (_definition.id == 'beat_the_dealer' &&
                !_wasInterrupted &&
                _pendingResult == null &&
                _result == null)
              _BeatTheDealerExitButton(onExit: _pauseForExitWarning),
            SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _GameHud(game: _game, definition: _definition),
                  if (_definition.id == 'ramen_timer' &&
                      !_wasInterrupted &&
                      _pendingResult == null &&
                      _result == null)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 18,
                      child: _RamenTimerActionButton(game: _game),
                    ),
                  if (_definition.id != 'number_rush' &&
                      _definition.id != 'beat_the_dealer')
                    Positioned(
                      left: 8,
                      top: 13,
                      child: _GameExitButton(onExit: _pauseForExitWarning),
                    ),
                ],
              ),
            ),
            if (_showStartGuide && !_showExitWarning && _isStartGuideReady)
              _GameStartGuide(
                instruction: _definition.startInstruction,
                isPractice:
                    (widget.attempt?.isPractice ?? false) ||
                    widget.attempt?.status == 'practice',
                onStart: _startGame,
              ),
            if (_showStartGuide && !_showExitWarning && !_isStartGuideReady)
              const ColoredBox(
                key: Key('game-start-guide-loading'),
                color: AppColors.backgroundDeep,
              ),
            if (_pendingResult != null || _result != null)
              GameEndTransition(
                key: const Key('game-end-scene'),
                endType: (_pendingResult ?? _result)!.endType,
                onCompleted: _revealResult,
                resultPanel: switch (_result) {
                  final result? => _ResultPanel(
                    result: result,
                    definition: _definition,
                    westernOpponent: _game is WesternDuelGame
                        ? _game.opponent
                        : null,
                    westernFailure: _game is WesternDuelGame
                        ? _game.failureMessage
                        : null,
                    windDartsOpponent: _windDartsOpponent,
                    isPractice: widget.attempt?.isPractice ?? false,
                    rankResult: _rankResult,
                    isSubmitting: _isSubmitting,
                    submitError: _submitError,
                    isSavingNickname: _isSavingNickname,
                    onChooseNickname: _chooseNickname,
                    onRetrySubmit: () => _submitResult(result),
                    onHome: _returnHome,
                  ),
                  null => null,
                },
              ),
            if (_showExitWarning)
              _ExitWarningOverlay(
                onExit: _leaveGame,
                onContinue: _continueGame,
              ),
          ],
        ),
      ),
    );
  }
}

class _GameStartGuide extends StatelessWidget {
  const _GameStartGuide({
    required this.instruction,
    required this.isPractice,
    required this.onStart,
  });

  final String instruction;
  final bool isPractice;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('game-start-guide'),
      color: AppColors.backgroundDeep.withValues(alpha: 0.9),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.primary, width: 4),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.primaryShadow,
                      offset: Offset(0, 9),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const WordSafeText(
                      '게임 방법',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Galmuri',
                        color: AppColors.text,
                        fontSize: 30,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundDeep,
                        border: Border.all(
                          color: AppColors.surfaceLight,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Semantics(
                        key: const Key('game-start-instruction'),
                        label: instruction,
                        child: ExcludeSemantics(
                          child: WordSafeText(
                            instruction,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Galmuri',
                              color: AppColors.text,
                              fontSize: 21,
                              height: 1.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: PixelButton(
                        key: const Key('game-start-guide-button'),
                        label: isPractice ? '연습 시작하기' : '도전 시작하기',
                        onPressed: onStart,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BeatTheDealerExitButton extends StatelessWidget {
  const _BeatTheDealerExitButton({required this.onExit});

  static const _logicalSize = Size(360, 640);
  static const _touchRect = Rect.fromLTWH(4, 21, 48, 48);

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / _logicalSize.width,
          constraints.maxHeight / _logicalSize.height,
        );
        final viewportLeft =
            (constraints.maxWidth - _logicalSize.width * scale) / 2;
        final viewportTop =
            (constraints.maxHeight - _logicalSize.height * scale) / 2;

        return Stack(
          children: [
            Positioned(
              left: viewportLeft + _touchRect.left * scale,
              top: viewportTop + _touchRect.top * scale,
              width: _touchRect.width * scale,
              height: _touchRect.height * scale,
              child: Tooltip(
                message: '게임 나가기',
                triggerMode: TooltipTriggerMode.tap,
                child: Semantics(
                  button: true,
                  label: '게임 나가기',
                  child: GestureDetector(
                    key: const Key('game-exit-button'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onExit,
                    child: Center(
                      child: CustomPaint(
                        key: const Key('game-exit-icon'),
                        size: Size.square(32 * scale),
                        painter: const _PixelExitIconPainter(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NumberRushExitButton extends StatefulWidget {
  const _NumberRushExitButton({required this.onExit});

  final VoidCallback onExit;

  @override
  State<_NumberRushExitButton> createState() => _NumberRushExitButtonState();
}

class _NumberRushExitButtonState extends State<_NumberRushExitButton> {
  static const _logicalSize = Size(360, 640);
  static const _touchRect = Rect.fromLTWH(30, 523, 62, 56);
  static const _assetSize = 56.0;

  var _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value || !mounted) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / _logicalSize.width,
          constraints.maxHeight / _logicalSize.height,
        );
        final viewportLeft =
            (constraints.maxWidth - _logicalSize.width * scale) / 2;
        final viewportTop =
            (constraints.maxHeight - _logicalSize.height * scale) / 2;

        return Stack(
          children: [
            Positioned(
              left: viewportLeft + _touchRect.left * scale,
              top: viewportTop + _touchRect.top * scale,
              width: _touchRect.width * scale,
              height: _touchRect.height * scale,
              child: Tooltip(
                message: '게임 나가기',
                triggerMode: TooltipTriggerMode.tap,
                child: Semantics(
                  button: true,
                  label: '게임 나가기',
                  child: Listener(
                    onPointerDown: (_) => _setPressed(true),
                    onPointerUp: (_) => _setPressed(false),
                    onPointerCancel: (_) => _setPressed(false),
                    child: GestureDetector(
                      key: const Key('game-exit-button'),
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onExit,
                      child: Center(
                        child: Image.asset(
                          _isPressed
                              ? 'assets/images/number_rush/exit_button_pressed.png'
                              : 'assets/images/number_rush/exit_button_idle.png',
                          key: const Key('number-rush-exit-image'),
                          width: _assetSize * scale,
                          height: _assetSize * scale,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GameExitButton extends StatelessWidget {
  const _GameExitButton({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '게임 나가기',
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        button: true,
        label: '게임 나가기',
        child: GestureDetector(
          key: const Key('game-exit-button'),
          behavior: HitTestBehavior.opaque,
          onTap: onExit,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: CustomPaint(
                key: Key('game-exit-icon'),
                size: Size.square(32),
                painter: _PixelExitIconPainter(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelExitIconPainter extends CustomPainter {
  const _PixelExitIconPainter();

  static const _sourceSize = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final door = Paint()
      ..color = Colors.white
      ..isAntiAlias = false;
    final arrow = Paint()
      ..color = Colors.white
      ..isAntiAlias = false;

    const doorParts = [
      Rect.fromLTWH(8, 2, 7, 2),
      Rect.fromLTWH(13, 2, 2, 12),
      Rect.fromLTWH(8, 12, 7, 2),
      Rect.fromLTWH(8, 2, 2, 3),
      Rect.fromLTWH(8, 11, 2, 3),
    ];
    final arrowPath = Path()
      ..moveTo(1, 7)
      ..lineTo(2, 7)
      ..lineTo(2, 6)
      ..lineTo(3, 6)
      ..lineTo(3, 5)
      ..lineTo(4, 5)
      ..lineTo(4, 4)
      ..lineTo(6, 4)
      ..lineTo(6, 6)
      ..lineTo(5, 6)
      ..lineTo(5, 7)
      ..lineTo(12, 7)
      ..lineTo(12, 10)
      ..lineTo(5, 10)
      ..lineTo(5, 11)
      ..lineTo(6, 11)
      ..lineTo(6, 13)
      ..lineTo(4, 13)
      ..lineTo(4, 12)
      ..lineTo(3, 12)
      ..lineTo(3, 11)
      ..lineTo(2, 11)
      ..lineTo(2, 10)
      ..lineTo(1, 10)
      ..close();

    final scale = size.shortestSide / _sourceSize;
    final offset = Offset(
      (size.width - (_sourceSize * scale)) / 2,
      (size.height - (_sourceSize * scale)) / 2,
    );
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);

    for (final part in doorParts) {
      canvas.drawRect(part, door);
    }
    canvas
      ..drawPath(arrowPath, arrow)
      ..restore();
  }

  @override
  bool shouldRepaint(_PixelExitIconPainter oldDelegate) => false;
}

class _GameHud extends StatelessWidget {
  const _GameHud({required this.game, required this.definition});

  final MiniGameController game;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MiniGameHudState>(
      valueListenable: game.hud,
      builder: (context, state, child) {
        if (definition.id == 'temple_run') {
          return _TempleRunHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.survivalTime) {
          return _SurvivalTimeHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.appleGame) {
          return _AppleGameHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.numberRush) {
          return _NumberRushHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.mamaDuckTrail) {
          return _MamaDuckTrailHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.beatTheDealer) {
          return _BeatTheDealerHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.tenPitchSlugger) {
          return _TenPitchSluggerHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.ramenTimer) {
          return _RamenTimerHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.bathhouseSort) {
          return _BathhouseSortHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.netBoat) {
          return _NetBoatHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.moleReaction) {
          return _MoleReactionHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.westernDuel) {
          return const IgnorePointer(child: SizedBox.expand());
        }
        if (definition.hudStyle == MiniGameHudStyle.custom) {
          return const IgnorePointer(child: SizedBox.expand());
        }
        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 64,
                right: 16,
                top: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (definition.id == 'lily_frog') ...[
                      SizedBox(
                        width: 88,
                        child: _HudValue(
                          label: 'SCORE',
                          value: definition.formatHudScore(state.score),
                          scaleValueDown: true,
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: Column(
                          children: [
                            _HudValue(
                              label: 'COMBO',
                              value: '${state.distance}x',
                              valueKey: const Key('lily-frog-combo-value'),
                              alignCenter: true,
                              scaleValueDown: true,
                            ),
                            if (state.comboRemainingPercent
                                case final int percent)
                              LilyFrogComboGauge(
                                key: const Key('lily-frog-combo-gauge'),
                                remainingPercent: percent,
                                combo: state.distance,
                              ),
                          ],
                        ),
                      ),
                    ] else
                      _HudValue(
                        label: 'SURVIVE',
                        value: definition.formatScore(state.score),
                      ),
                    _HudValue(
                      label: 'TIME',
                      value: '${state.remainingSeconds ?? state.elapsedSeconds}'
                          .padLeft(2, '0'),
                      alignEnd: true,
                      isDanger:
                          state.remainingSeconds != null &&
                          state.remainingSeconds! <= 10,
                    ),
                  ],
                ),
              ),
              if (state.phase == MiniGamePhase.countdown)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WordSafeText(
                        state.countdownNumber > 0
                            ? '${state.countdownNumber}'
                            : 'GO!',
                        style: const TextStyle(
                          fontFamily: 'Galmuri',
                          color: AppColors.primary,
                          fontSize: 68,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                              color: AppColors.primaryShadow,
                              offset: Offset(5, 5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      WordSafeText(
                        definition.countdownInstruction,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              if (state.phase == MiniGamePhase.playing &&
                  definition.id != 'midnight_snake')
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18,
                  child: WordSafeText(
                    definition.playingInstruction,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TempleRunHud extends StatelessWidget {
  const _TempleRunHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    final message = state.message;
    final showTempleRunPrompt = templeRunHudShowsPrompt(state);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 16,
            top: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xC9172329),
                border: Border.all(color: const Color(0x66FFF4D6)),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _HudValue(
                      label: definition.scoreLabel,
                      value: definition.formatHudScore(state.score),
                    ),
                    _HudValue(
                      label: 'TIME',
                      value: '${state.remainingSeconds ?? state.elapsedSeconds}'
                          .padLeft(2, '0'),
                      alignEnd: true,
                      isDanger:
                          state.remainingSeconds != null &&
                          state.remainingSeconds! <= 10,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (state.phase == MiniGamePhase.countdown)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WordSafeText(
                    state.countdownNumber > 0
                        ? '${state.countdownNumber}'
                        : 'GO!',
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.primary,
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: AppColors.primaryShadow,
                          offset: Offset(5, 5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xCC172329),
                      border: Border.all(color: const Color(0x66FFF4D6)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: WordSafeText(
                        definition.countdownInstruction,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (showTempleRunPrompt)
            Positioned(
              key: const Key('temple-run-hud-message'),
              left: 24,
              right: 24,
              top: 98,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xEC172329),
                  border: Border.all(color: AppColors.primary, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  child: WordSafeText(
                    message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontFamily: 'Galmuri',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          if (state.phase == MiniGamePhase.playing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: WordSafeText(
                definition.playingInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xD9FFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(color: Color(0xCC000000), offset: Offset(1, 1)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

@visibleForTesting
bool templeRunHudShowsPrompt(MiniGameHudState state) {
  final message = state.message;
  return state.phase == MiniGamePhase.playing &&
      message != null &&
      (message.contains('꺾기') ||
          message.contains('회전 예약') ||
          message.contains('점프 대기') ||
          message.contains('슬라이드 대기'));
}

class _NetBoatHud extends StatelessWidget {
  const _NetBoatHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    final netLength = state.distance.clamp(
      0,
      NetBoatRules.netMaximumLength.round(),
    );
    final ratio = NetBoatRules.netUsageRatio(netLength.toDouble());
    final warning = NetBoatRules.isNetWarning(netLength.toDouble());
    final showFeedback =
        state.phase == MiniGamePhase.playing &&
        state.message != null &&
        !state.message!.startsWith('잡은 물고기');
    final gaugeColor = warning
        ? const Color(0xFFFFB83D)
        : const Color(0xFF61DDD3);
    final gaugeBorderColor = warning
        ? const Color(0xFFFFE08A)
        : const Color(0xCCFFF0BE);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 16,
            top: 12,
            child: Row(
              children: [
                SizedBox(
                  width: 74,
                  child: _HudValue(
                    label: 'SCORE',
                    value: definition.formatHudScore(state.score),
                    scaleValueDown: true,
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WordSafeText(
                        warning ? 'NET · 위험' : 'NET',
                        style: TextStyle(
                          fontFamily: 'Galmuri',
                          color: gaugeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      WordSafeText(
                        '$netLength / ${NetBoatRules.netMaximumLength.round()}',
                        key: const Key('net-boat-length-value'),
                        style: TextStyle(
                          fontFamily: 'Galmuri',
                          color: gaugeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (warning)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 3),
                          child: WordSafeText(
                            '끊김 위험',
                            key: Key('net-boat-warning-state'),
                            style: TextStyle(
                              fontFamily: 'Galmuri',
                              color: Color(0xFFFFC15A),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      Container(
                        key: const Key('net-boat-length-gauge'),
                        width: 86,
                        height: warning ? 8 : 6,
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: const Color(0xB0143440),
                          border: Border.all(
                            color: gaugeBorderColor,
                            width: warning ? 2 : 1,
                          ),
                          boxShadow: warning
                              ? const [
                                  BoxShadow(
                                    color: Color(0x4DFFB83D),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: ratio,
                          heightFactor: 1,
                          child: ColoredBox(color: gaugeColor),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: _HudValue(
                    label: 'TIME',
                    value: '${state.remainingSeconds ?? state.elapsedSeconds}'
                        .padLeft(2, '0'),
                    alignEnd: true,
                    isDanger:
                        state.remainingSeconds != null &&
                        state.remainingSeconds! <= 10,
                    scaleValueDown: true,
                  ),
                ),
              ],
            ),
          ),
          if (showFeedback)
            Positioned(
              left: 64,
              right: 16,
              top: 68,
              child: Center(
                child: Container(
                  key: const Key('net-boat-hud-message'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xD0143440),
                    border: Border.all(color: gaugeColor, width: 1.5),
                  ),
                  child: WordSafeText(
                    state.message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: Color(0xFFFFF0BE),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          if (state.phase == MiniGamePhase.countdown)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WordSafeText(
                    state.countdownNumber > 0
                        ? '${state.countdownNumber}'
                        : 'GO!',
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.primary,
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: AppColors.primaryShadow,
                          offset: Offset(5, 5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  WordSafeText(
                    definition.countdownInstruction,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          if (state.phase == MiniGamePhase.playing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: WordSafeText(
                definition.playingInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoleReactionHud extends StatelessWidget {
  const _MoleReactionHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    final resolved = state.distance
        .clamp(0, MoleReactionRules.totalEvents)
        .toInt();
    final total = definition.formatHudScore(state.score);
    final message = state.message;
    final isPrompt =
        message == MoleReactionRules.preparationPrompt ||
        message == MoleReactionRules.realPrompt;
    final progress = switch (resolved) {
      0 => '준비 0/1',
      1 => '진짜 0/1',
      _ => '진짜 1/1',
    };
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 12,
            top: 10,
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _HudValue(
                    label: '누적 반응시간',
                    value: total,
                    valueKey: const Key('mole-reaction-total'),
                    scaleValueDown: true,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _HudValue(
                    label: '진행',
                    value: progress,
                    valueKey: const Key('mole-reaction-progress'),
                    alignCenter: true,
                    scaleValueDown: true,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _HudValue(
                    label: '경과',
                    value: '${state.elapsedSeconds}s',
                    valueKey: const Key('mole-reaction-elapsed'),
                    alignEnd: true,
                    scaleValueDown: true,
                  ),
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.playing && isPrompt)
            Positioned(
              left: 10,
              right: 10,
              top: 108,
              child: Center(child: _MoleReactionPromptTitle(message: message!)),
            ),
          if (state.phase == MiniGamePhase.playing &&
              message != null &&
              !isPrompt)
            Positioned(
              left: 48,
              right: 12,
              top: 66,
              child: Center(
                child: _MoleReactionFeedbackBanner(message: message),
              ),
            ),
          if (state.phase == MiniGamePhase.countdown)
            ColoredBox(
              color: const Color(0x550E160D),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 190,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WordSafeText(
                          state.countdownNumber > 0
                              ? '${state.countdownNumber}'
                              : '집중!',
                          style: const TextStyle(
                            fontFamily: 'Galmuri',
                            color: Color(0xFFFFE18A),
                            fontSize: 64,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(
                                color: Color(0xFF5B3217),
                                offset: Offset(5, 5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        WordSafeText(
                          definition.countdownInstruction,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (state.phase == MiniGamePhase.playing && message == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: WordSafeText(
                definition.playingInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFE8E0C8),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Color(0x99000000), blurRadius: 3)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A large, unobstructed round prompt that shares the pixel title treatment
/// used by the end-of-game `CLEAR!` card. It lives above the board while the
/// next mole is hidden, so the player gets the context without a small HUD
/// panel covering the playfield.
class _MoleReactionPromptTitle extends StatelessWidget {
  const _MoleReactionPromptTitle({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontFamily: 'Galmuri',
      fontSize: 27,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      height: 1,
    );

    return RepaintBoundary(
      key: const Key('mole-reaction-prompt-title'),
      child: Stack(
        alignment: Alignment.center,
        children: [
          WordSafeText(
            message,
            textAlign: TextAlign.center,
            style: baseStyle.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 5
                ..strokeJoin = StrokeJoin.round
                ..color = const Color(0xFF2A1938),
            ),
          ),
          WordSafeText(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Galmuri',
              color: Color(0xFFFFE7A3),
              fontSize: 27,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              height: 1,
              shadows: [Shadow(color: Color(0xFFA63F48), offset: Offset(3, 3))],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoleReactionFeedbackBanner extends StatelessWidget {
  const _MoleReactionFeedbackBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final feedback = _MoleReactionFeedbackData.fromMessage(message);
    if (feedback == null) {
      return Container(
        key: const Key('mole-reaction-hud-message'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xD03B2418),
          border: Border.all(color: const Color(0xFFEFC878), width: 1.5),
        ),
        child: WordSafeText(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Galmuri',
            color: Color(0xFFFFF2CF),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey(message),
      tween: Tween(begin: 0.78, end: 1),
      duration: Duration(
        milliseconds: feedback.tier == MoleReactionSpeedTier.perfect
            ? 520
            : 400,
      ),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        key: const Key('mole-reaction-hud-message'),
        padding: const EdgeInsets.fromLTRB(11, 5, 11, 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [feedback.panelTop, feedback.panelBottom],
          ),
          border: Border.all(color: feedback.accent, width: 2),
          boxShadow: [
            BoxShadow(
              color: feedback.accent.withValues(alpha: 0.42),
              blurRadius: feedback.isPerfect ? 14 : 8,
              spreadRadius: feedback.isPerfect ? 2 : 0,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 1,
              top: -5,
              child: WordSafeText(
                feedback.isPerfect ? '✦' : '·',
                style: TextStyle(
                  color: feedback.accent.withValues(alpha: 0.9),
                  fontSize: feedback.isPerfect ? 18 : 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Positioned(
              right: 1,
              bottom: -6,
              child: WordSafeText(
                feedback.isPerfect ? '✦' : '·',
                style: TextStyle(
                  color: feedback.accent.withValues(alpha: 0.8),
                  fontSize: feedback.isPerfect ? 16 : 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WordSafeText(
                      feedback.title,
                      style: TextStyle(
                        fontFamily: 'Galmuri',
                        color: feedback.accent,
                        fontSize: feedback.isPerfect ? 13 : 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (feedback.golden) ...[
                      const SizedBox(width: 6),
                      const WordSafeText(
                        '×2',
                        style: TextStyle(
                          fontFamily: 'Galmuri',
                          color: Color(0xFFFFF4B2),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    WordSafeText(
                      MoleReactionRules.formatTotalMs(feedback.milliseconds),
                      style: const TextStyle(
                        fontFamily: 'Galmuri',
                        color: Color(0xFFFFF7DD),
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        height: 0.95,
                      ),
                    ),
                    if (feedback.weightedMilliseconds != null) ...[
                      const SizedBox(width: 7),
                      WordSafeText(
                        '→ ${MoleReactionRules.formatTotalMs(feedback.weightedMilliseconds!)}',
                        style: const TextStyle(
                          fontFamily: 'Galmuri',
                          color: Color(0xFFFFE18A),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoleReactionFeedbackData {
  const _MoleReactionFeedbackData({
    required this.milliseconds,
    required this.weightedMilliseconds,
    required this.golden,
    required this.tier,
  });

  final int milliseconds;
  final int? weightedMilliseconds;
  final bool golden;
  final MoleReactionSpeedTier tier;

  bool get isPerfect => tier == MoleReactionSpeedTier.perfect;

  String get title => switch (tier) {
    MoleReactionSpeedTier.perfect => golden ? 'GOLDEN PERFECT!' : 'PERFECT!',
    MoleReactionSpeedTier.lightning => 'LIGHTNING!',
    MoleReactionSpeedTier.great => 'GREAT REACTION!',
    MoleReactionSpeedTier.steady => 'NICE & STEADY!',
    MoleReactionSpeedTier.late => 'KEEP FOCUS!',
  };

  Color get accent => golden
      ? const Color(0xFFFFD45B)
      : switch (tier) {
          MoleReactionSpeedTier.perfect => const Color(0xFFFFF0A6),
          MoleReactionSpeedTier.lightning => const Color(0xFF7CF4DE),
          MoleReactionSpeedTier.great => const Color(0xFF9DD7FF),
          MoleReactionSpeedTier.steady => const Color(0xFFD8C1FF),
          MoleReactionSpeedTier.late => const Color(0xFFFFB36B),
        };

  Color get panelTop => golden
      ? const Color(0xE65B3C15)
      : switch (tier) {
          MoleReactionSpeedTier.perfect => const Color(0xE64B3820),
          MoleReactionSpeedTier.lightning => const Color(0xE6244C4C),
          MoleReactionSpeedTier.great => const Color(0xE62F4662),
          MoleReactionSpeedTier.steady => const Color(0xE6423159),
          MoleReactionSpeedTier.late => const Color(0xE64B3020),
        };

  Color get panelBottom => golden
      ? const Color(0xE6382113)
      : switch (tier) {
          MoleReactionSpeedTier.perfect => const Color(0xE62D1D17),
          MoleReactionSpeedTier.lightning => const Color(0xE61E353D),
          MoleReactionSpeedTier.great => const Color(0xE6222C43),
          MoleReactionSpeedTier.steady => const Color(0xE62D223F),
          MoleReactionSpeedTier.late => const Color(0xE632211A),
        };

  static _MoleReactionFeedbackData? fromMessage(String message) {
    final isHit = message.startsWith('반응') || message.startsWith('황금!');
    if (!isHit) return null;
    final matches = RegExp(r'([\d,]+)ms').allMatches(message).toList();
    if (matches.isEmpty) return null;
    int parse(Match match) => int.parse(match.group(1)!.replaceAll(',', ''));
    final milliseconds = parse(matches.first);
    final weighted = matches.length > 1 ? parse(matches[1]) : null;
    return _MoleReactionFeedbackData(
      milliseconds: milliseconds,
      weightedMilliseconds: weighted,
      golden: message.startsWith('황금!'),
      tier: MoleReactionRules.speedTierForMilliseconds(milliseconds),
    );
  }
}

class _BathhouseSortHud extends StatelessWidget {
  const _BathhouseSortHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 12,
            top: 10,
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: _HudValue(
                    label: 'SCORE',
                    value: definition.formatHudScore(state.score),
                    valueKey: const Key('bathhouse-score-value'),
                    scaleValueDown: true,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Transform.translate(
                    offset: const Offset(10, 0),
                    child: Center(
                      child: _HudValue(
                        label: 'COMBO',
                        value: '${state.distance}',
                        valueKey: const Key('bathhouse-combo-value'),
                        alignCenter: true,
                        scaleValueDown: true,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _HudValue(
                    label: 'TIME',
                    value: '${state.remainingSeconds ?? state.elapsedSeconds}'
                        .padLeft(2, '0'),
                    valueKey: const Key('bathhouse-time-value'),
                    alignEnd: true,
                    isDanger:
                        state.remainingSeconds != null &&
                        state.remainingSeconds! <= 10,
                    scaleValueDown: true,
                  ),
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.playing && state.message != null)
            Positioned(
              left: 64,
              right: 16,
              top: 68,
              child: Center(
                child: Container(
                  key: const Key('bathhouse-hud-message'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xD03B2418),
                    border: Border.all(
                      color: const Color(0xFFEFC878),
                      width: 2,
                    ),
                  ),
                  child: WordSafeText(
                    state.message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: Color(0xFFFFF2CF),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          if (state.phase == MiniGamePhase.countdown)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WordSafeText(
                    state.countdownNumber > 0
                        ? '${state.countdownNumber}'
                        : 'GO!',
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.primary,
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: AppColors.primaryShadow,
                          offset: Offset(5, 5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  WordSafeText(
                    definition.countdownInstruction,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RamenTimerActionButton extends StatelessWidget {
  const _RamenTimerActionButton({required this.game});

  final MiniGameController game;

  @override
  Widget build(BuildContext context) {
    final actionGame = game is PrimaryActionMiniGameController
        ? game as PrimaryActionMiniGameController
        : null;
    return ValueListenableBuilder<MiniGameHudState>(
      valueListenable: game.hud,
      builder: (context, state, child) => PixelButton(
        key: const Key('ramen-timer-action-button'),
        label: state.primaryActionLabel ?? '찍기!',
        activateOnTapDown: true,
        onPressed: state.primaryActionEnabled && actionGame != null
            ? actionGame.triggerPrimaryAction
            : null,
      ),
    );
  }
}

class _RamenTimerHud extends StatelessWidget {
  const _RamenTimerHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    final nextTarget = switch (state.distance) {
      0 => RamenTimerRules.culinaryActionLabelForTapCount(0),
      1 => RamenTimerRules.culinaryActionLabelForTapCount(1),
      2 => RamenTimerRules.culinaryActionLabelForTapCount(2),
      _ => '조리 완료',
    };
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 16,
            top: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _HudValue(
                  label: '다음 조리',
                  value: nextTarget,
                  valueKey: const Key('ramen-timer-next-target'),
                  scaleValueDown: true,
                ),
                _HudValue(
                  label: '조리 단계',
                  value: '${state.distance.clamp(0, 3)} / 3',
                  valueKey: const Key('ramen-timer-progress'),
                  alignEnd: true,
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.playing && state.message != null)
            Positioned(
              left: 58,
              right: 18,
              top: 74,
              child: Center(
                child: Container(
                  key: const Key('ramen-timer-hud-message'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xD0122638),
                    border: Border.all(
                      color: const Color(0xFF49677A),
                      width: 2,
                    ),
                  ),
                  child: WordSafeText(
                    state.message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFE18A),
                      fontFamily: 'Galmuri',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          if (state.phase == MiniGamePhase.countdown)
            ColoredBox(
              color: const Color(0x72061120),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WordSafeText(
                      state.countdownNumber > 0
                          ? '${state.countdownNumber}'
                          : 'START!',
                      style: const TextStyle(
                        fontFamily: 'Galmuri',
                        color: Color(0xFFFFD866),
                        fontSize: 64,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            color: Color(0xFF925144),
                            offset: Offset(5, 5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    WordSafeText(
                      definition.countdownInstruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFE9F0EC),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TenPitchSluggerHud extends StatelessWidget {
  const _TenPitchSluggerHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 16,
            top: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _HudValue(
                  label: 'MAX DISTANCE',
                  value: definition.formatHudScore(state.score),
                  valueKey: const Key('ten-pitch-hud-score'),
                ),
                _HudValue(
                  label: 'PITCH',
                  value: '${state.distance.clamp(1, 10)} / 10',
                  valueKey: const Key('ten-pitch-hud-count'),
                  alignEnd: true,
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.playing && state.message != null)
            Positioned(
              left: 62,
              right: 18,
              top: 76,
              child: Center(
                child: Container(
                  key: const Key('ten-pitch-hud-message'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  color: const Color(0xC911152A),
                  child: WordSafeText(
                    state.message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFE28A),
                      fontFamily: 'Galmuri',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          if (state.phase == MiniGamePhase.countdown)
            ColoredBox(
              color: const Color(0x7A0D1227),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WordSafeText(
                      state.countdownNumber > 0
                          ? '${state.countdownNumber}'
                          : 'PLAY BALL!',
                      style: const TextStyle(
                        fontFamily: 'Galmuri',
                        color: Color(0xFFFFD866),
                        fontSize: 62,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            color: Color(0xFF9C4338),
                            offset: Offset(5, 5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    WordSafeText(
                      definition.countdownInstruction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (state.phase == MiniGamePhase.playing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: WordSafeText(
                definition.playingInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFE9E0C5),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Color(0xFF11152A), blurRadius: 3)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BeatTheDealerHud extends StatelessWidget {
  const _BeatTheDealerHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    if (state.phase != MiniGamePhase.countdown) {
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WordSafeText(
              state.countdownNumber > 0 ? '${state.countdownNumber}' : 'GO!',
              style: const TextStyle(
                fontFamily: 'Galmuri',
                color: AppColors.primary,
                fontSize: 68,
                fontWeight: FontWeight.w700,
                shadows: [
                  Shadow(color: AppColors.primaryShadow, offset: Offset(5, 5)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            WordSafeText(
              definition.countdownInstruction,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MamaDuckTrailHud extends StatelessWidget {
  const _MamaDuckTrailHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 12,
            top: 10,
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: _HudValue(
                    label: 'SURVIVE',
                    value: definition.formatHudScore(state.score),
                    valueKey: const Key('mama-hud-score'),
                    scaleValueDown: true,
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const WordSafeText(
                        'LIVES',
                        key: Key('mama-hud-lives-label'),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: 96,
                        height: 48,
                        child: Stack(
                          children: [
                            for (var index = 0; index < 3; index++)
                              Positioned(
                                left: index * 24,
                                child: Opacity(
                                  key: Key('mama-duck-life-$index'),
                                  opacity: index < state.distance ? 1 : 0.18,
                                  child: Image.asset(
                                    'assets/images/mama_duck_trail/'
                                    'duckling_life_face.png',
                                    width: 48,
                                    height: 48,
                                    filterQuality: FilterQuality.none,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: _HudValue(
                    label: 'TIME',
                    value: '${state.remainingSeconds ?? state.elapsedSeconds}'
                        .padLeft(2, '0'),
                    valueKey: const Key('mama-hud-time'),
                    alignEnd: true,
                    isDanger:
                        state.remainingSeconds != null &&
                        state.remainingSeconds! <= 10,
                  ),
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.countdown)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WordSafeText(
                    state.countdownNumber > 0
                        ? '${state.countdownNumber}'
                        : 'GO!',
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.primary,
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: AppColors.primaryShadow,
                          offset: Offset(5, 5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  WordSafeText(
                    definition.countdownInstruction,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          if (state.phase == MiniGamePhase.playing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: WordSafeText(
                definition.playingInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberRushHud extends StatelessWidget {
  const _NumberRushHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    if (state.phase != MiniGamePhase.countdown) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ColoredBox(
        color: const Color(0xB8030713),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WordSafeText(
                state.countdownNumber > 0 ? '${state.countdownNumber}' : 'GO!',
                style: const TextStyle(
                  fontFamily: 'Galmuri',
                  color: Color(0xFF39F3FF),
                  fontSize: 68,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(color: Color(0xFFFF3EBC), offset: Offset(5, 5)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              WordSafeText(
                definition.countdownInstruction,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleGameHud extends StatelessWidget {
  const _AppleGameHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 16,
            top: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _HudValue(
                  label: definition.scoreLabel,
                  value: definition.formatScore(state.score),
                  valueKey: const Key('apple-hud-score'),
                ),
                _HudValue(
                  label: 'TIME',
                  value: '${state.remainingSeconds ?? state.elapsedSeconds}'
                      .padLeft(2, '0'),
                  alignEnd: true,
                  isDanger:
                      state.remainingSeconds != null &&
                      state.remainingSeconds! <= 10,
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.countdown)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WordSafeText(
                    state.countdownNumber > 0
                        ? '${state.countdownNumber}'
                        : 'GO!',
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: Color(0xFFFFD24A),
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Color(0xFF591F2C), offset: Offset(5, 5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SurvivalTimeHud extends StatelessWidget {
  const _SurvivalTimeHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 12,
            child: Column(
              children: [
                const WordSafeText(
                  'TIME',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                WordSafeText(
                  definition.formatHudScore(state.score),
                  key: const Key('survival-time'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Galmuri',
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: Color(0x99000000), offset: Offset(3, 3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.countdown)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WordSafeText(
                    state.countdownNumber > 0
                        ? '${state.countdownNumber}'
                        : 'GO!',
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: Color(0xFF4CF4E8),
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Color(0xFF0B6371), offset: Offset(5, 5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  WordSafeText(
                    definition.countdownInstruction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          if (state.phase == MiniGamePhase.playing && state.elapsedSeconds < 5)
            Positioned(
              left: 0,
              right: 0,
              bottom: 26,
              child: WordSafeText(
                definition.playingInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HudValue extends StatelessWidget {
  const _HudValue({
    required this.label,
    required this.value,
    this.valueKey,
    this.alignEnd = false,
    this.alignCenter = false,
    this.isDanger = false,
    this.scaleValueDown = false,
  });

  final String label;
  final String value;
  final Key? valueKey;
  final bool alignEnd;
  final bool alignCenter;
  final bool isDanger;
  final bool scaleValueDown;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignCenter
          ? CrossAxisAlignment.center
          : alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        WordSafeText(
          label,
          style: const TextStyle(
            fontFamily: 'Galmuri',
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        if (scaleValueDown)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignCenter
                ? Alignment.center
                : alignEnd
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: _valueText(),
          )
        else
          _valueText(),
      ],
    );
  }

  Text _valueText() {
    return WordSafeText(
      value,
      key: valueKey,
      singleLine: true,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontFamily: 'Galmuri',
        color: isDanger ? AppColors.danger : AppColors.text,
        fontSize: 25,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.result,
    required this.definition,
    this.westernOpponent,
    this.westernFailure,
    this.windDartsOpponent,
    required this.isPractice,
    required this.rankResult,
    required this.isSubmitting,
    required this.submitError,
    required this.isSavingNickname,
    required this.onChooseNickname,
    required this.onRetrySubmit,
    required this.onHome,
  });

  final GameResult result;
  final MiniGameDefinition definition;
  final WesternDuelOpponent? westernOpponent;
  final String? westernFailure;
  final WindDartsOpponent? windDartsOpponent;
  final bool isPractice;
  final DailyRankResult? rankResult;
  final bool isSubmitting;
  final Object? submitError;
  final bool isSavingNickname;
  final VoidCallback onChooseNickname;
  final VoidCallback onRetrySubmit;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return PixelPanel(
      key: const Key('result-panel'),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const WordSafeText(
            '한 판 종료!',
            style: TextStyle(
              fontFamily: 'Galmuri',
              color: AppColors.primary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: WordSafeText(
                definition.formatScore(result.score),
                key: const Key('final-score'),
                singleLine: true,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          WordSafeText(
            definition.scoreLabel,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          if (definition.id == 'western_duel' && westernOpponent != null) ...[
            const SizedBox(height: 12),
            WordSafeText(
              result.score == 0
                  ? westernFailure ?? '기록 없이 종료됐어요'
                  : '${switch (WesternDuelRules.compare(WesternDuelRules.reactionForScore(result.score), westernOpponent!.reactionMilliseconds)) {
                      WesternDuelOutcome.win => '승리',
                      WesternDuelOutcome.lose => '패배',
                      WesternDuelOutcome.draw => '무승부',
                    }} · 상대 ${westernOpponent!.nickname} ${WesternDuelRules.formatMilliseconds(westernOpponent!.reactionMilliseconds)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (result.score > 0)
              const WordSafeText(
                '승패와 관계없이 내 반응시간으로 순위를 매겨요',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
          ],
          if (definition.id == 'wind_darts' && windDartsOpponent != null) ...[
            const SizedBox(height: 12),
            WordSafeText(
              '${result.score > windDartsOpponent!.score
                  ? '승리'
                  : result.score < windDartsOpponent!.score
                  ? '패배'
                  : '무승부'} · ${windDartsOpponent!.nickname} ${windDartsOpponent!.score}점',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final mineShots = result.windDartsShotScores;
                final shotCount =
                    mineShots?.length ?? windDartsOpponent!.shotScores.length;
                return Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: List.generate(shotCount, (index) {
                    final mine = mineShots?[index] ?? 0;
                    final theirs = index < windDartsOpponent!.shotScores.length
                        ? windDartsOpponent!.shotScores[index]
                        : 0;
                    final isGolden = shotCount == 7 && index == shotCount - 1;
                    return Chip(
                      label: WordSafeText(
                        isGolden
                            ? '황금 2배  $mine : $theirs'
                            : '${index + 1}발  $mine : $theirs',
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: isGolden
                          ? const Color(0x557A5A20)
                          : mine > theirs
                          ? const Color(0x55347A49)
                          : mine < theirs
                          ? const Color(0x555C2A22)
                          : const Color(0x55352E22),
                    );
                  }),
                );
              },
            ),
          ],
          const SizedBox(height: 24),
          if (isPractice)
            const WordSafeText(
              '연습 모드 · 이 점수는 랭킹에 반영되지 않아요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (isSubmitting)
            const WordSafeText('오늘 순위를 계산하고 있어요...')
          else if (rankResult case final rank?)
            Column(
              children: [
                WordSafeText(
                  '${rank.rank}등 / ${rank.participants}명'
                  '${rank.participants >= 10 ? ' · 상위 ${rank.topPercent}%' : ''}',
                  key: const Key('daily-rank'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.reward,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (rank.score != null && rank.score != result.score) ...[
                  const SizedBox(height: 8),
                  WordSafeText(
                    '개인 최고 기록 ${definition.formatScore(rank.score!)}으로 랭킹을 유지했어요',
                    key: const Key('best-score-preserved-message'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (_needsNicknameSetup(rank.nickname))
                  SizedBox(
                    width: double.infinity,
                    child: PixelButton(
                      label: isSavingNickname ? '저장 중...' : '닉네임 정하고 랭킹 보기',
                      icon: Icons.edit_outlined,
                      onPressed: isSavingNickname ? null : onChooseNickname,
                    ),
                  )
                else
                  NearbyRanking(
                    result: rank,
                    formatScore: definition.formatScore,
                  ),
              ],
            )
          else if (submitError != null)
            Column(
              children: [
                WordSafeText(
                  submitError is DeferredAttemptResolutionException
                      ? '광고 확인이 늦어 랭킹에 반영하지 못했어요. 잠시 후 다시 시도해 주세요.'
                      : '점수를 기기에 보관했어요. 서버가 복구되면 자동 전송됩니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
                const SizedBox(height: 12),
                PixelButton(
                  label: '지금 다시 전송',
                  icon: Icons.refresh,
                  onPressed: onRetrySubmit,
                ),
              ],
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: PixelButton(
              label: '홈으로',
              icon: Icons.home_outlined,
              onPressed: onHome,
            ),
          ),
        ],
      ),
    );
  }
}

class DeferredAttemptResolutionException implements Exception {
  const DeferredAttemptResolutionException();
}

class _ExitWarningOverlay extends StatelessWidget {
  const _ExitWarningOverlay({required this.onExit, required this.onContinue});

  final VoidCallback onExit;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('game-exit-warning-backdrop'),
      color: AppColors.backgroundDeep,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: PixelPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.phone_paused_outlined,
                    color: AppColors.primary,
                    size: 42,
                  ),
                  const SizedBox(height: 18),
                  const WordSafeText(
                    '게임이 중단되었어요',
                    key: Key('game-exit-warning-title'),
                    style: TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.text,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const WordSafeText(
                    '지금 나가면 이번 기회가 소진돼요.\n계속 게임하거나 정말 나갈 수 있어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PixelButton(
                      key: const Key('continue-game-button'),
                      label: '계속 게임하기',
                      icon: Icons.play_arrow_rounded,
                      onPressed: onContinue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: PixelButton(
                      key: const Key('confirm-game-exit-button'),
                      label: '진짜 나가기',
                      icon: Icons.home_outlined,
                      onPressed: onExit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool shouldInterruptGame(AppLifecycleState state) {
  return state != AppLifecycleState.resumed;
}

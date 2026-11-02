import 'dart:async';
import 'dart:math' show max, min, pi, sin;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/core/auth/kakao_auth_service.dart';
import 'package:just_one_round/core/notifications/push_notification_service.dart';
import 'package:just_one_round/core/reviews/app_review_service.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/duels/presentation/duel_lobby_screen.dart';
import 'package:just_one_round/features/games/bathhouse_sort/presentation/bathhouse_sort_preview.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/lily_frog/presentation/lily_frog_home_preview.dart';
import 'package:just_one_round/features/games/net_boat/presentation/net_boat_preview.dart';
import 'package:just_one_round/features/games/mole_reaction/presentation/mole_reaction_preview.dart';
import 'package:just_one_round/features/games/western_duel/presentation/western_duel_preview.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_preview.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_preview.dart';
import 'package:just_one_round/features/games/midnight_snake/presentation/midnight_snake_path.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_registry.dart';
import 'package:just_one_round/features/games/ramen_timer/presentation/ramen_timer_preview.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_preview.dart';
import 'package:just_one_round/features/economy/domain/economy_transaction.dart';
import 'package:just_one_round/features/economy/domain/daily_reward_rules.dart';
import 'package:just_one_round/features/legal/legal_config.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_session.dart';
import 'package:just_one_round/features/profile/presentation/nickname_dialog.dart';
import 'package:just_one_round/features/profile/domain/nickname_color.dart';
import 'package:just_one_round/features/profile/presentation/profile_sheet.dart';
import 'package:just_one_round/features/referral/domain/referral.dart';
import 'package:just_one_round/features/shop/presentation/shop_sheet.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/daily_reset.dart';
import 'package:just_one_round/features/today/domain/daily_nonplayer.dart';
import 'package:just_one_round/features/today/domain/level_up_reward.dart';
import 'package:just_one_round/features/today/domain/previous_daily_result.dart';
import 'package:just_one_round/features/today/domain/tester_activation_result.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/mama_duck_trail_home_preview.dart';
import 'package:just_one_round/features/today/presentation/level_up_reward_dialog.dart';
import 'package:just_one_round/shared/widgets/coin_mark.dart';
import 'package:just_one_round/shared/widgets/pixel_action_dialog.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _previewDailyGameChangedDialog = bool.fromEnvironment(
  'PREVIEW_DAILY_GAME_CHANGED_DIALOG',
);

bool _readAnonymousAccountStatus() {
  try {
    return Supabase.instance.client.auth.currentUser?.isAnonymous ?? true;
  } on Object {
    // Widget tests and preview repositories may not initialize Supabase.
    return true;
  }
}

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

enum _PlayStartMode { challenge, practice }

enum _ChallengeStartPath { free, rewardedAd, challengeTicket }

class _TodayScreenState extends ConsumerState<TodayScreen>
    with WidgetsBindingObserver {
  static const _rewardVerificationRetryCount = 8;
  var _isClaiming = false;
  var _isSavingProfile = false;
  var _isRunningDeveloperAction = false;
  var _isLinkingKakao = false;
  var _isOpeningShop = false;
  late final RewardedAdService _rewardedAdService;
  late RewardedAdStatus _rewardedAdStatus;
  var _accountDeleted = false;
  var _isCheckingDailyReset = false;
  var _isDailyResetDialogVisible = false;
  var _isCheckingPreviousResult = false;
  var _isCheckingLevelUpReward = false;
  var _showTomorrow = false;
  var _isPreviousResultDialogVisible = false;
  var _isLevelUpRewardDialogVisible = false;
  var _testerVersionTapCount = 0;
  String? _pendingFreePracticeRequestId;
  final _pendingShopPurchaseRequestIds = <String, String>{};
  String? _playActionNotice;
  int? _practiceTicketDisplayOverride;
  int? _practiceTicketAnimationTarget;
  int? _challengeTicketDisplayOverride;
  int? _challengeTicketAnimationTarget;
  var _practiceTicketAnimationDelta = 0;
  var _practiceTicketAnimationRevision = 0;
  var _ticketAnimationGeneration = 0;
  var _clearTicketAnimationOnNextState = false;
  _CoinRewardEffectData? _coinRewardEffect;
  Timer? _dailyResetTimer;
  Timer? _playActionNoticeTimer;
  Timer? _previousResultTimer;
  Timer? _levelUpRewardTimer;
  Timer? _testerVersionTapTimer;
  Timer? _coinRewardEffectTimer;
  Timer? _ticketAnimationTimer;
  Completer<void>? _ticketAnimationWaiter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rewardedAdService = ref.read(rewardedAdServiceProvider);
    _rewardedAdStatus = _rewardedAdService.status.value;
    _rewardedAdService.status.addListener(_handleRewardedAdStatus);
    ref.listenManual(
      todayStateProvider,
      (_, next) => next.whenData(_handleTodayState),
      fireImmediately: true,
    );
    if (_previewDailyGameChangedDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showDailyGameChangedDialog());
      });
    }
  }

  @override
  void dispose() {
    _dailyResetTimer?.cancel();
    _playActionNoticeTimer?.cancel();
    _previousResultTimer?.cancel();
    _levelUpRewardTimer?.cancel();
    _testerVersionTapTimer?.cancel();
    _coinRewardEffectTimer?.cancel();
    _cancelTicketAnimationWaiter();
    _ticketAnimationGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _rewardedAdService.status.removeListener(_handleRewardedAdStatus);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
    }
  }

  void _handleTodayState(TodayState state) {
    if (_clearTicketAnimationOnNextState &&
        (_practiceTicketDisplayOverride != null ||
            _challengeTicketDisplayOverride != null)) {
      _clearTicketAnimationOnNextState = false;
      final generation = _ticketAnimationGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _ticketAnimationGeneration) return;
        _cancelTicketAnimation(generation);
      });
    }
    if (_practiceTicketDisplayOverride != null &&
        state.practiceTicketsRemaining == _practiceTicketAnimationTarget) {
      final generation = _ticketAnimationGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _ticketAnimationGeneration ||
            state.practiceTicketsRemaining != _practiceTicketAnimationTarget) {
          return;
        }
        setState(() {
          _practiceTicketDisplayOverride = null;
          _practiceTicketAnimationTarget = null;
        });
      });
    }
    if (_challengeTicketDisplayOverride != null &&
        state.storeChallengeTickets == _challengeTicketAnimationTarget) {
      final generation = _ticketAnimationGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _ticketAnimationGeneration ||
            state.storeChallengeTickets != _challengeTicketAnimationTarget) {
          return;
        }
        setState(() {
          _challengeTicketDisplayOverride = null;
          _challengeTicketAnimationTarget = null;
        });
      });
    }
    _scheduleDailyResetCheck();
    _scheduleLevelUpRewardCheck(state);
    if (state.requiresUpdate) {
      _previousResultTimer?.cancel();
      return;
    }
    _schedulePreviousResultCheck();
    if (!state.testMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_checkForPreviousDailyResult());
      });
    }
  }

  Future<void> _handleAppResumed() async {
    if (!mounted) return;
    final changed = await _checkForDailyGameChange();
    if (!changed &&
        ref.read(todayStateProvider).value?.requiresUpdate != true) {
      await _checkForPreviousDailyResult();
      await _checkForLevelUpReward();
    }
  }

  void _scheduleDailyResetCheck() {
    _dailyResetTimer?.cancel();
    final delay =
        durationUntilNextDailyReset(DateTime.now()) +
        const Duration(seconds: 1);
    _dailyResetTimer = Timer(delay, () {
      unawaited(_checkForDailyGameChange());
    });
  }

  void _schedulePreviousResultCheck() {
    _previousResultTimer?.cancel();
    final delay =
        durationUntilNextPreviousResultAvailability(DateTime.now()) +
        const Duration(seconds: 1);
    _previousResultTimer = Timer(delay, () {
      unawaited(_checkForPreviousDailyResult());
    });
  }

  void _scheduleLevelUpRewardCheck(
    TodayState state, {
    Duration delay = Duration.zero,
  }) {
    _levelUpRewardTimer?.cancel();
    if (state.requiresUpdate ||
        state.levelRewardedThrough <= state.levelCelebrationSeenThrough) {
      return;
    }
    _levelUpRewardTimer = Timer(delay, () {
      unawaited(_checkForLevelUpReward());
    });
  }

  bool get _canShowLevelUpReward {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        !_accountDeleted &&
        ModalRoute.of(context)?.isCurrent == true &&
        LevelUpCelebrationGate.readyOf(context) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        !_isCheckingPreviousResult &&
        !_isLevelUpRewardDialogVisible &&
        !_isDailyResetDialogVisible &&
        !_isPreviousResultDialogVisible &&
        !_isClaiming &&
        !_isSavingProfile &&
        !_isRunningDeveloperAction &&
        !_isLinkingKakao &&
        !_isOpeningShop;
  }

  Future<void> _checkForLevelUpReward() async {
    if (!mounted || _isCheckingLevelUpReward || _isLevelUpRewardDialogVisible) {
      return;
    }
    final state = ref.read(todayStateProvider).value;
    if (state == null ||
        state.requiresUpdate ||
        state.levelRewardedThrough <= state.levelCelebrationSeenThrough) {
      return;
    }
    if (!_canShowLevelUpReward) {
      // Retry visibility locally; never poll the server while another screen is open.
      _scheduleLevelUpRewardCheck(state, delay: const Duration(seconds: 1));
      return;
    }
    final accountId = _appReviewAccountId();
    _isCheckingLevelUpReward = true;
    try {
      final reward = await ref
          .read(levelUpRewardRepositoryProvider)
          .fetchPendingLevelUpReward()
          .timeout(const Duration(seconds: 12));
      if (!mounted || reward == null || _appReviewAccountId() != accountId) {
        return;
      }
      final currentState = ref.read(todayStateProvider).value;
      if (currentState == null ||
          currentState.requiresUpdate ||
          currentState.levelRewardedThrough <=
              currentState.levelCelebrationSeenThrough) {
        return;
      }
      if (!_canShowLevelUpReward) {
        _scheduleLevelUpRewardCheck(
          currentState,
          delay: const Duration(seconds: 1),
        );
        return;
      }
      if (accountId != null && accountId != reward.userId) return;
      await _showLevelUpRewardDialog(reward);
    } catch (error, stackTrace) {
      debugPrint('[LevelUpReward] Pending reward lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isCheckingLevelUpReward = false;
    }
  }

  Future<void> _showLevelUpRewardDialog(LevelUpReward reward) async {
    if (!mounted || _isLevelUpRewardDialogVisible) return;
    _isLevelUpRewardDialogVisible = true;
    try {
      await showLevelUpRewardDialog(
        context,
        reward: reward,
        onConfirm: () async {
          final currentUserId = _appReviewAccountId();
          if (currentUserId != null && currentUserId != reward.userId) {
            throw StateError('account changed before acknowledging reward');
          }
          await ref
              .read(levelUpRewardRepositoryProvider)
              .acknowledgeLevelUpReward(
                throughLevel: reward.toLevel,
                expectedUserId: reward.userId,
              )
              .timeout(const Duration(seconds: 12));
          if (mounted) ref.invalidate(todayStateProvider);
        },
      );
    } finally {
      _isLevelUpRewardDialogVisible = false;
      if (mounted) {
        final state = ref.read(todayStateProvider).value;
        if (state != null) _scheduleLevelUpRewardCheck(state);
      }
    }
  }

  Future<void> _checkForPreviousDailyResult() async {
    if (_isCheckingPreviousResult ||
        _isCheckingLevelUpReward ||
        _isLevelUpRewardDialogVisible ||
        _isDailyResetDialogVisible ||
        _isPreviousResultDialogVisible ||
        !mounted) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      _previousResultTimer?.cancel();
      _previousResultTimer = Timer(const Duration(seconds: 30), () {
        unawaited(_checkForPreviousDailyResult());
      });
      return;
    }
    final state = ref.read(todayStateProvider).value;
    if (state == null || state.testMode || state.requiresUpdate) return;

    _isCheckingPreviousResult = true;
    try {
      final result = await ref
          .read(dailyGameRepositoryProvider)
          .fetchUnseenPreviousDailyResult()
          .timeout(const Duration(seconds: 12));
      if (!mounted || result == null) {
        _schedulePreviousResultCheck();
        return;
      }
      if (ref.read(todayStateProvider).value?.requiresUpdate == true) {
        return;
      }
      await _showPreviousDailyResultDialog(result);
    } catch (_) {
      _schedulePreviousResultCheck();
    } finally {
      _isCheckingPreviousResult = false;
      unawaited(_consumePendingAppReview());
    }
  }

  Future<void> _consumePendingAppReview() async {
    if (!mounted) return;
    final accountId = _appReviewAccountId();
    await ref
        .read(appReviewServiceProvider)
        .consumePending(
          fetchHistory: () =>
              ref.read(dailyGameRepositoryProvider).fetchHistory(),
          canRequest: () => _canRequestAppReview(accountId),
        );
  }

  bool _canRequestAppReview(String? expectedAccountId) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return false;
    }
    if (_isCheckingPreviousResult ||
        _isCheckingLevelUpReward ||
        _isCheckingDailyReset ||
        _isDailyResetDialogVisible ||
        _isPreviousResultDialogVisible ||
        _isLevelUpRewardDialogVisible ||
        _isClaiming ||
        _isSavingProfile ||
        _isRunningDeveloperAction ||
        _isLinkingKakao ||
        _isOpeningShop ||
        _accountDeleted) {
      return false;
    }
    if (_appReviewAccountId() != expectedAccountId) return false;
    final state = ref.read(todayStateProvider).value;
    return state != null && !state.requiresUpdate && !state.testMode;
  }

  String? _appReviewAccountId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } on Object {
      return null;
    }
  }

  Future<void> _showPreviousDailyResultDialog(
    PreviousDailyResult result,
  ) async {
    if (!mounted || _isPreviousResultDialogVisible) return;
    _isPreviousResultDialogVisible = true;
    try {
      final outcome = await showDialog<_PreviousResultDialogOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PreviousDailyResultDialog(
          result: result,
          onClaim: () => ref
              .read(dailyGameRepositoryProvider)
              .acknowledgePreviousDailyResult(result.playDate, result.gameId),
          onShowRanking: () => _showRankingForDate(
            initialResult: DailyRankResult(
              score: result.score,
              rank: result.rank,
              participants: result.participants,
              topPercent: result.topPercent,
              nickname: null,
              nearby: const [],
            ),
            gameId: result.gameId,
            gameName: result.displayName,
            playDate: result.playDate,
            title: '어제의 랭킹',
          ),
        ),
      );
      if (outcome == null) return;
      ref.invalidate(todayStateProvider);
      _showCoinRewardEffect(outcome.reward);
    } finally {
      _isPreviousResultDialogVisible = false;
      _schedulePreviousResultCheck();
      final state = ref.read(todayStateProvider).value;
      if (state != null) _scheduleLevelUpRewardCheck(state);
    }
  }

  void _showCoinRewardEffect(RewardGrant reward) {
    if (!mounted || reward.coinsGranted <= 0) return;
    final targetCoins = reward.economy.coins;
    final fromCoins = max(0, targetCoins - reward.coinsGranted);
    _coinRewardEffectTimer?.cancel();
    setState(() {
      _coinRewardEffect = _CoinRewardEffectData(
        fromCoins: fromCoins,
        targetCoins: targetCoins,
        delta: reward.coinsGranted,
      );
    });
    _coinRewardEffectTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _coinRewardEffect = null);
    });
  }

  Future<bool> _checkForDailyGameChange({TodayState? displayedState}) async {
    if (_isCheckingDailyReset || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final currentState = displayedState ?? ref.read(todayStateProvider).value;
    if (currentState == null) return false;

    _isCheckingDailyReset = true;
    try {
      final latestState = await ref
          .read(dailyGameRepositoryProvider)
          .fetchToday()
          .timeout(const Duration(seconds: 12));
      if (!mounted) return false;
      if (latestState.requiresUpdate || currentState.requiresUpdate) {
        ref.invalidate(todayStateProvider);
        return true;
      }
      if (isSamePlayDate(currentState.playDate, latestState.playDate)) {
        _scheduleDailyResetCheck();
        return false;
      }
      await _showDailyGameChangedDialog();
      return true;
    } catch (_) {
      _scheduleDailyResetCheck();
      return false;
    } finally {
      _isCheckingDailyReset = false;
    }
  }

  Future<void> _showDailyGameChangedDialog() async {
    if (!mounted || _isDailyResetDialogVisible) return;
    _isDailyResetDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _DailyGameChangedDialog(),
      );
    } finally {
      _isDailyResetDialogVisible = false;
      if (mounted) {
        ref.invalidate(todayStateProvider);
      }
    }
  }

  void _handleRewardedAdStatus() {
    if (!mounted) return;
    setState(() => _rewardedAdStatus = _rewardedAdService.status.value);
  }

  void _handleSettingsTap(TodayState state) {
    if (_isSavingProfile || _isRunningDeveloperAction || _isLinkingKakao) {
      return;
    }
    _openSettings(state);
  }

  Future<void> _openShop(TodayState state) async {
    if (_isOpeningShop || _isClaiming) return;
    setState(() => _isOpeningShop = true);
    try {
      final shopResult = await showShopSheet(
        context,
        economy: state.economy,
        practiceTickets: state.storePracticeTickets,
        challengeTickets: state.storeChallengeTickets,
        nicknameChangeTickets: state.storeNicknameChangeTickets,
        onPurchase: (itemId) async {
          final requestId = _pendingShopPurchaseRequestIds.putIfAbsent(
            itemId,
            createPlayRequestId,
          );
          final repository = ref.read(dailyGameRepositoryProvider);
          final purchase = await _withTransientNetworkRetry(
            () => repository.purchaseShopItem(
              itemId: itemId,
              requestId: requestId,
            ),
          );
          _pendingShopPurchaseRequestIds.remove(itemId);
          if (mounted) ref.invalidate(todayStateProvider);
          return purchase;
        },
      );
      // A purchase can be followed by a back swipe or a barrier dismissal,
      // both of which used to return null and leave the home inventory stale.
      // Refresh after every sheet close so a completed purchase is reflected
      // even when the route cannot return its local result.
      if (!mounted) return;
      ref.invalidate(todayStateProvider);
      if (shopResult?.editNickname != true) return;

      // The purchase response is the freshest ticket count available while
      // the provider refresh is in flight. Prefer the refreshed state for the
      // editor and retain the response count as a safe fallback.
      TodayState? latestState;
      try {
        latestState = await ref.refresh(todayStateProvider.future);
      } catch (_) {
        latestState = ref.read(todayStateProvider).value;
      }
      if (!mounted) return;
      final editorState = latestState ?? state;
      // The purchase response is the minimum fresh inventory for this flow.
      // A provider refresh can still race with its own invalidation and return
      // the pre-purchase snapshot, so retain the response count as a floor.
      // The server remains authoritative when the editor saves.
      final editorTicketCount = max(
        max(
          latestState?.storeNicknameChangeTickets ?? 0,
          shopResult?.nicknameChangeTickets ?? 0,
        ),
        editorState.storeNicknameChangeTickets,
      );
      // The editor can still encounter a server-side inventory race. Allow
      // its ticket-required fallback to open the shop again immediately.
      setState(() => _isOpeningShop = false);
      await _editNickname(
        editorState.nickname,
        nicknameChangeTickets: editorTicketCount,
        sourceState: editorState,
      );
    } finally {
      if (mounted) setState(() => _isOpeningShop = false);
    }
  }

  Future<void> _openSettings(TodayState state) async {
    final appBuildInfo = ref.read(appBuildInfoProvider);
    final pushAuthorizationStatus = await getPushAuthorizationStatus();
    var showAdPrivacy = false;
    try {
      showAdPrivacy = await _rewardedAdService.isPrivacyOptionsRequired();
    } catch (_) {
      // Settings must remain usable when the ad consent SDK is unavailable.
    }
    if (!mounted) return;
    final action = await showDialog<_SettingsAction>(
      context: context,
      builder: (context) {
        final dialogWidth = (MediaQuery.sizeOf(context).width - 48)
            .clamp(280.0, 320.0)
            .toDouble();
        return SimpleDialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          title: const WordSafeText('설정'),
          children: [
            SizedBox(
              width: dialogWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SimpleDialogOption(
                    key: const Key('profile-menu'),
                    onPressed: () =>
                        Navigator.of(context).pop(_SettingsAction.profile),
                    child: ListTile(
                      leading: const Icon(
                        Icons.person_outline,
                        color: AppColors.text,
                      ),
                      title: const WordSafeText('프로필'),
                    ),
                  ),
                  SimpleDialogOption(
                    key: const Key('social-push-menu'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_SettingsAction.socialNotifications),
                    child: ListTile(
                      leading: Icon(
                        state.socialNotificationsEnabled
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        color: AppColors.text,
                      ),
                      title: const WordSafeText('소셜 푸시 알림', singleLine: true),
                      trailing: Switch.adaptive(
                        value: state.socialNotificationsEnabled,
                        onChanged: (_) => Navigator.of(
                          context,
                        ).pop(_SettingsAction.socialNotifications),
                      ),
                    ),
                  ),
                  if (pushAuthorizationStatus.needsSystemSettings)
                    SimpleDialogOption(
                      key: const Key('push-device-settings-menu'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_SettingsAction.pushDeviceSettings),
                      child: const ListTile(
                        leading: Icon(
                          Icons.settings_outlined,
                          color: AppColors.text,
                        ),
                        title: WordSafeText('기기 알림 설정'),
                        subtitle: WordSafeText('기기 설정에서 알림이 차단되어 있어요'),
                      ),
                    ),
                  SimpleDialogOption(
                    key: const Key('support-menu'),
                    onPressed: () =>
                        Navigator.of(context).pop(_SettingsAction.support),
                    child: const ListTile(
                      leading: Icon(
                        Icons.mail_outline_rounded,
                        color: AppColors.text,
                      ),
                      title: WordSafeText('문의하기'),
                    ),
                  ),
                  SimpleDialogOption(
                    key: const Key('legal-menu'),
                    onPressed: () =>
                        Navigator.of(context).pop(_SettingsAction.legal),
                    child: const ListTile(
                      leading: Icon(
                        Icons.policy_outlined,
                        color: AppColors.text,
                      ),
                      title: WordSafeText('정책 및 약관'),
                    ),
                  ),
                  if (showAdPrivacy)
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.of(context).pop(_SettingsAction.adPrivacy),
                      child: const ListTile(
                        leading: Icon(
                          Icons.ads_click_outlined,
                          color: AppColors.text,
                        ),
                        title: WordSafeText('광고 개인정보 선택'),
                      ),
                    ),
                  SimpleDialogOption(
                    onPressed: () =>
                        Navigator.of(context).pop(_SettingsAction.delete),
                    child: const ListTile(
                      leading: Icon(
                        Icons.delete_forever_outlined,
                        color: Colors.redAccent,
                      ),
                      title: WordSafeText(
                        '계정 및 데이터 삭제',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ),
                  if (state.testMode)
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.of(context).pop(_SettingsAction.developer),
                      child: const ListTile(
                        key: Key('developer-mode-menu'),
                        leading: Icon(
                          Icons.developer_mode,
                          color: AppColors.reward,
                        ),
                        title: WordSafeText('개발자 모드'),
                        subtitle: WordSafeText('게임 변경 및 횟수 초기화'),
                      ),
                    ),
                  GestureDetector(
                    key: const Key('app-version-tap-target'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _handleTesterVersionTap(
                      context,
                      isTestMode: state.testMode,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                      child: WordSafeText(
                        '앱 버전 ${appBuildInfo.version} (${appBuildInfo.buildNumber})',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case _SettingsAction.profile:
        await _openProfile(state);
      case _SettingsAction.legal:
        await _openLegalDocuments();
      case _SettingsAction.support:
        await _openSupportInquiry(appBuildInfo);
      case _SettingsAction.socialNotifications:
        await _setSocialNotificationsEnabled(!state.socialNotificationsEnabled);
      case _SettingsAction.pushDeviceSettings:
        await _openPushDeviceSettings();
      case _SettingsAction.adPrivacy:
        await _showAdPrivacyOptions();
      case _SettingsAction.delete:
        await _deleteAccount();
      case _SettingsAction.developer:
        await _openDeveloperTools(state);
      case _SettingsAction.testerActivation:
        await _showTesterActivationDialog();
      case _SettingsAction.testerDeactivation:
        await _deactivateTestMode();
      case null:
        return;
    }
  }

  Future<void> _setSocialNotificationsEnabled(bool enabled) async {
    PushAuthorizationStatus? pushAuthorizationStatus;
    if (enabled) {
      pushAuthorizationStatus = await requestPushPermissionAndRegister(
        ref.read(socialRepositoryProvider),
      );
    }
    try {
      await ref
          .read(socialRepositoryProvider)
          .setSocialNotificationsEnabled(enabled);
      ref.invalidate(todayStateProvider);
      if (!enabled) {
        _showMessage('소셜 푸시 알림을 껐어요.');
      } else if (pushAuthorizationStatus?.needsSystemSettings == true) {
        _showMessage('앱 설정은 켰지만 기기 알림이 꺼져 있어요. 기기 설정에서 허용해 주세요.');
      } else if (pushAuthorizationStatus ==
          PushAuthorizationStatus.unavailable) {
        _showMessage('앱 설정은 켰지만 기기 알림 상태를 확인하지 못했어요.');
      } else {
        _showMessage('소셜 푸시 알림을 켰어요.');
      }
    } catch (_) {
      _showMessage('알림 설정을 변경하지 못했어요.');
    }
  }

  Future<void> _openPushDeviceSettings() async {
    final opened = await openPushNotificationSettings();
    if (!opened) _showMessage('기기 알림 설정을 열지 못했어요. 시스템 설정에서 직접 확인해 주세요.');
  }

  Future<void> _openProfile(TodayState state) async {
    final kakaoAuthService = ref.read(kakaoAuthServiceProvider);
    var referralStatus = const ReferralStatus.empty();
    try {
      referralStatus = await ref
          .read(referralRepositoryProvider)
          .fetchReferralStatus()
          .timeout(const Duration(seconds: 8));
    } catch (error, stackTrace) {
      debugPrint('[Referral] Status lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) return;
    final action = await showProfileSheet(
      context,
      nickname: state.nickname,
      economy: state.economy,
      kakaoConfigured: kakaoAuthService.isConfigured,
      kakaoLinked: kakaoAuthService.isLinked,
      isAnonymousAccount: _readAnonymousAccountStatus(),
      nicknameChangeTickets: state.storeNicknameChangeTickets,
      referralStatus: referralStatus,
    );
    if (!mounted) return;
    switch (action) {
      case ProfileAction.editNickname:
        await _editNickname(
          state.nickname,
          nicknameChangeTickets: state.storeNicknameChangeTickets,
          sourceState: state,
        );
      case ProfileAction.linkKakao:
        await _linkKakaoAccount();
      case ProfileAction.inviteFriends:
        await _shareReferralInvite();
      case null:
        return;
    }
  }

  Future<void> _shareReferralInvite() async {
    try {
      final invite = await ref
          .read(referralRepositoryProvider)
          .getOrCreateReferralInvite()
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: '딱한판만 같이 해요! 친구가 첫 연습 또는 도전을 시작하면 제가 도전권을 받아요.\n${invite.url}',
          subject: '딱한판만 초대',
          sharePositionOrigin: renderBox == null
              ? null
              : renderBox.localToGlobal(Offset.zero) & renderBox.size,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('[Referral] Share failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _showMessage('초대 링크를 만들지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _linkKakaoAccount() async {
    final service = ref.read(kakaoAuthServiceProvider);
    if (!service.isConfigured) {
      _showMessage('카카오 로그인을 사용할 수 없어요. 앱 키 설정이 필요합니다.');
      return;
    }

    setState(() => _isLinkingKakao = true);
    try {
      final result = await service.linkAccount();
      if (!mounted) return;
      if (result == KakaoAccountLinkResult.signedIntoExistingAccount) {
        // The identity-conflict path changes the Supabase session to the
        // existing Kakao account. Refresh synchronously so the home screen
        // shows that account's economy instead of briefly rendering the old
        // anonymous account's cached state.
        ref.invalidate(previousGameWinnerProvider);
        try {
          await ref.refresh(todayStateProvider.future).then<void>((_) {});
        } catch (_) {
          // The account switch succeeded even if the immediate refresh is
          // offline. Keep the provider invalidated for the next retry.
          ref.invalidate(todayStateProvider);
        }
      } else {
        ref.invalidate(todayStateProvider);
      }
      _showMessage(switch (result) {
        KakaoAccountLinkResult.linked => '카카오 계정이 연결됐어요. 다음에도 기록을 이어갈 수 있어요.',
        KakaoAccountLinkResult.alreadyLinked => '카카오 계정이 이미 연결되어 있어요.',
        KakaoAccountLinkResult.signedIntoExistingAccount =>
          '이미 연결된 카카오 계정으로 전환했어요. 그 계정의 경험치와 코인을 불러왔어요.',
      });
    } on KakaoLoginException catch (error) {
      if (!mounted || error.cancelled) return;
      _showMessage(error.message);
    } on AuthException catch (error) {
      if (!mounted) return;
      if (error.message.toLowerCase().contains('manual linking')) {
        _showMessage('Supabase에서 계정 연결 기능을 먼저 켜 주세요.');
      } else {
        _showMessage('카카오 계정을 연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('카카오 계정을 연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _isLinkingKakao = false);
    }
  }

  void _handleTesterVersionTap(
    BuildContext dialogContext, {
    required bool isTestMode,
  }) {
    _testerVersionTapTimer?.cancel();
    _testerVersionTapCount += 1;
    if (_testerVersionTapCount >= 7) {
      _testerVersionTapCount = 0;
      Navigator.of(dialogContext).pop(
        isTestMode
            ? _SettingsAction.testerDeactivation
            : _SettingsAction.testerActivation,
      );
      return;
    }
    _testerVersionTapTimer = Timer(const Duration(seconds: 4), () {
      _testerVersionTapCount = 0;
    });
  }

  Future<void> _showTesterActivationDialog() async {
    final activated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TesterPinDialog(
        onActivate: ref.read(dailyGameRepositoryProvider).activateTestMode,
      ),
    );
    if (activated != true || !mounted) return;
    ref.invalidate(todayStateProvider);
    _showMessage('테스트 모드가 활성화됐어요.');
  }

  Future<void> _deactivateTestMode() async {
    try {
      await ref.read(dailyGameRepositoryProvider).deactivateTestMode();
      if (!mounted) return;
      ref.invalidate(todayStateProvider);
      _showMessage('원래 계정 모드로 돌아왔어요.');
    } catch (_) {
      if (mounted) {
        _showMessage('테스트 모드를 해제하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    }
  }

  Future<void> _openLegalUrl(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _showMessage('문서를 열지 못했어요.');
    }
  }

  Future<void> _openLegalDocuments() async {
    final selection = await showDialog<_LegalDocument>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const WordSafeText('정책 및 약관'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_LegalDocument.privacy),
            child: const ListTile(
              leading: Icon(Icons.privacy_tip_outlined, color: AppColors.text),
              title: WordSafeText('개인정보처리방침'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_LegalDocument.terms),
            child: const ListTile(
              leading: Icon(Icons.description_outlined, color: AppColors.text),
              title: WordSafeText('서비스 이용약관'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_LegalDocument.community),
            child: const ListTile(
              leading: Icon(Icons.shield_outlined, color: AppColors.text),
              title: WordSafeText('커뮤니티 운영정책'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || selection == null) return;
    final uri = switch (selection) {
      _LegalDocument.privacy => LegalConfig.privacyUri,
      _LegalDocument.terms => LegalConfig.termsUri,
      _LegalDocument.community => LegalConfig.communityUri,
    };
    await _openLegalUrl(uri);
  }

  Future<void> _openSupportInquiry(AppBuildInfo appBuildInfo) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => _SupportInquiryDialog(
        onSubmit: (message) => ref
            .read(dailyGameRepositoryProvider)
            .submitSupportInquiry(
              message: message,
              appVersion: appBuildInfo.version,
              buildNumber: appBuildInfo.buildNumber,
            ),
      ),
    );
    if (submitted == true && mounted) {
      _showMessage('문의가 접수됐어요. 운영팀이 확인할게요.');
    }
  }

  Future<void> _showAdPrivacyOptions() async {
    final shown = await _rewardedAdService.showPrivacyOptions();
    if (mounted && !shown) {
      _showMessage('현재 지역에서는 변경할 광고 개인정보 선택이 없어요.');
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const WordSafeText('계정과 데이터를 삭제할까요?'),
        content: const WordSafeText(
          '닉네임, 모든 게임 기록과 광고 보상 기록이 영구 삭제됩니다. '
          '당일 중복 플레이를 막기 위한 익명 기기 표식만 다음 일일 초기화까지 유지됩니다. '
          '이 작업은 되돌릴 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const WordSafeText('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const WordSafeText('영구 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isRunningDeveloperAction = true);
    try {
      await ref.read(dailyGameRepositoryProvider).deleteAccount();
      if (mounted) setState(() => _accountDeleted = true);
    } catch (_) {
      if (mounted) _showMessage('계정을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _isRunningDeveloperAction = false);
    }
  }

  Future<void> _openDeveloperTools(TodayState state) async {
    setState(() => _isRunningDeveloperAction = true);
    try {
      final repository = ref.read(dailyGameRepositoryProvider);
      final games = await repository.fetchDeveloperGames();
      if (!mounted) return;
      final action = await showDialog<_DeveloperAction>(
        context: context,
        builder: (context) =>
            _DeveloperToolsDialog(games: games, currentGameId: state.game?.id),
      );
      if (action == null || !mounted) return;
      if (action.resetProgress) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const WordSafeText('오늘 기록을 초기화할까요?'),
            content: const WordSafeText('테스트 계정의 오늘 시도와 점수만 삭제됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const WordSafeText('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const WordSafeText('초기화'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await repository.resetDeveloperDailyProgress();
      } else {
        await repository.setDeveloperGame(action.gameId!);
      }
      ref.invalidate(todayStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: WordSafeText(
              action.resetProgress ? '오늘 기록을 초기화했어요.' : '테스트 게임을 변경했어요.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: WordSafeText('개발자 기능을 실행하지 못했어요: $error')),
      );
    } finally {
      if (mounted) setState(() => _isRunningDeveloperAction = false);
    }
  }

  Future<void> _start({
    required _PlayStartMode mode,
    required TodayState displayedState,
    _ChallengeStartPath? challengePath,
  }) async {
    if (_isClaiming) return;
    setState(() => _isClaiming = true);
    final ticketAnimationGeneration = _beginPlayTicketAnimation(
      mode: mode,
      displayedState: displayedState,
      challengePath: challengePath,
    );
    var keepTicketAnimation = false;
    TodayState startState = displayedState;
    try {
      final latestState = await ref
          .read(dailyGameRepositoryProvider)
          .fetchToday()
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (latestState.requiresUpdate || displayedState.requiresUpdate) {
        ref.invalidate(todayStateProvider);
        _showMessage('새 버전이 필요해요. 업데이트 화면을 불러올게요.');
        return;
      }
      final isTomorrow = displayedState.isTomorrowPreview;
      final expectedGameDate = isTomorrow
          ? latestState.playDate.add(const Duration(days: 1))
          : latestState.playDate;
      if (!isSamePlayDate(displayedState.playDate, expectedGameDate)) {
        await _showDailyGameChangedDialog();
        return;
      }
      startState = isTomorrow
          ? latestState.tomorrowPreview ?? latestState
          : latestState;
      if (mode == _PlayStartMode.practice && !startState.practicePending) {
        // A confirmed start should have removed the persisted request ID. If
        // an older client left one behind, the authoritative home state lets
        // us replace it before charging a new practice ticket. Keep the ID
        // when practice_pending is true so a lost claim response remains
        // safely retryable.
        _pendingFreePracticeRequestId = null;
      }
      if (startState.game == null ||
          !GameRegistry.supports(
            startState.game!.id,
            startState.game!.version,
          )) {
        _pendingFreePracticeRequestId = null;
        _showMessage(
          isTomorrow
              ? '내일 게임 업데이트를 준비 중이에요. 내일 다시 확인해 주세요.'
              : '게임 업데이트가 필요해요. 잠시 후 다시 시도해 주세요.',
        );
        return;
      }
      final selectedChallengePath = mode == _PlayStartMode.challenge
          ? challengePath ?? _defaultChallengeStartPath(startState)
          : null;
      final isAvailable = mode == _PlayStartMode.challenge
          ? _isChallengeStartPathAvailable(startState, selectedChallengePath!)
          : _isModeAvailable(startState, mode);
      if (!isAvailable) {
        _pendingFreePracticeRequestId = null;
        ref.invalidate(todayStateProvider);
        _showMessage('플레이 상태가 갱신됐어요. 현재 버튼에서 다시 선택해 주세요.');
        return;
      }

      final requiresAd = switch (mode) {
        _PlayStartMode.challenge =>
          selectedChallengePath == _ChallengeStartPath.rewardedAd,
        _PlayStartMode.practice => startState.requiresAdForPractice,
      };
      final repository = ref.read(dailyGameRepositoryProvider);
      if (mode == _PlayStartMode.challenge || requiresAd) {
        _pendingFreePracticeRequestId = null;
      }
      final attempt = switch (mode) {
        _PlayStartMode.challenge => switch (selectedChallengePath!) {
          _ChallengeStartPath.free => await _withTransientNetworkRetry(
            () => repository.claimDailyAttempt(startState.playDate),
          ),
          _ChallengeStartPath.rewardedAd => await _claimRewardedAttempt(
            repository,
            startState.playDate,
            startState,
          ),
          _ChallengeStartPath.challengeTicket =>
            await _withTransientNetworkRetry(
              () => repository.claimChallengeTicketAttempt(startState.playDate),
            ),
        },
        _PlayStartMode.practice =>
          requiresAd
              ? await _claimPracticeAttempt(
                  repository,
                  startState.playDate,
                  startState,
                )
              : await _claimDailyPractice(
                  repository,
                  latestState.playDate,
                  gameDate: startState.playDate,
                  reuseExistingRequest: startState.practicePending,
                ),
      };
      if (attempt == null) return;
      if (!mounted) return;
      // A successful claim is now recoverable through the persisted request
      // ID until the game confirms its start. Do not keep the same ID in this
      // screen state: GameScreen returns home with context.go('/'), which can
      // leave this state alive and otherwise replay the previous session.
      _pendingFreePracticeRequestId = null;
      keepTicketAnimation = true;
      setState(() => _isClaiming = false);
      _clearTicketAnimationOnNextState = ticketAnimationGeneration != null;
      await context.push('/play', extra: attempt);
      if (!mounted) return;
      try {
        await ref
            .refresh(todayStateProvider.future)
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        ref.invalidate(todayStateProvider);
      }
      _cancelTicketAnimation(ticketAnimationGeneration);
    } catch (error) {
      if (!mounted) return;
      if (_isAppUpdateRequiredError(error)) {
        ref.invalidate(todayStateProvider);
        _showMessage('새 버전이 필요해요. 업데이트 화면을 불러올게요.');
        return;
      }
      if (_isDailyGameChangedError(error)) {
        _pendingFreePracticeRequestId = null;
        await _showDailyGameChangedDialog();
        return;
      }
      if (_isDeviceDailyLimitError(error)) {
        ref.invalidate(todayStateProvider);
        _showMessage('오늘 이 기기의 무료 플레이는 이미 사용했어요.');
        return;
      }
      if (_isPlayStateChangedError(error)) {
        _pendingFreePracticeRequestId = null;
        ref.invalidate(todayStateProvider);
        _showMessage('플레이 상태를 새로 불러왔어요. 다시 선택해 주세요.');
        return;
      }
      if (_isTransientNetworkError(error)) {
        _showMessage('인터넷 연결이 불안정해요. 잠시 후 다시 시도해 주세요.');
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: WordSafeText('시작하지 못했어요: $error')));
    } finally {
      if (!keepTicketAnimation) {
        _cancelTicketAnimation(ticketAnimationGeneration);
      }
      if (mounted && _isClaiming) setState(() => _isClaiming = false);
    }
  }

  Future<void> _claimPracticeTicketReward(TodayState displayedState) async {
    if (_isClaiming) return;
    setState(() => _isClaiming = true);
    try {
      final repository = ref.read(dailyGameRepositoryProvider);
      final latestState = await repository.fetchToday().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      final expectedGameDate = displayedState.isTomorrowPreview
          ? latestState.playDate.add(const Duration(days: 1))
          : latestState.playDate;
      if (!isSamePlayDate(displayedState.playDate, expectedGameDate)) {
        await _showDailyGameChangedDialog();
        return;
      }
      if (!latestState.canClaimPracticeReward) {
        ref.invalidate(todayStateProvider);
        _showMessage('연습권 상태가 갱신됐어요. 다시 확인해 주세요.');
        return;
      }

      final session = await _withTransientNetworkRetry(
        () => repository.preparePracticeAd(latestState.playDate),
      );
      final recovered = await _claimVerifiedPracticeTickets(
        repository,
        session.id,
        retries: 0,
      );
      if (recovered != null) {
        await _animatePracticeTicketChange(
          from: latestState.practiceTicketsRemaining,
          to: latestState.practiceTicketsRemaining + recovered,
        );
        if (!mounted) return;
        ref.invalidate(todayStateProvider);
        _showMessage('연습권 $recovered장을 받았어요!');
        return;
      }

      final outcome = await _rewardedAdService.show(
        userId: session.userId,
        verificationSessionId: session.id,
      );
      if (!mounted) return;
      if (outcome == RewardedAdOutcome.dismissed) {
        _showMessage('광고를 끝까지 보면 연습권 2장을 받아요.');
        return;
      }
      if (outcome == RewardedAdOutcome.failed) {
        _showMessage('광고를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
        return;
      }

      if (ref.read(localTestAdVerificationProvider) &&
          repository is LocalPracticeAdVerificationRepository) {
        final localVerifier =
            repository as LocalPracticeAdVerificationRepository;
        await localVerifier.verifyLocalPracticeAd(session.id);
      }

      final granted = await _claimVerifiedPracticeTickets(
        repository,
        session.id,
        retries: 2,
      );
      if (!mounted) return;
      if (granted != null) {
        await _animatePracticeTicketChange(
          from: latestState.practiceTicketsRemaining,
          to: latestState.practiceTicketsRemaining + granted,
        );
        if (!mounted) return;
        ref.invalidate(todayStateProvider);
        _showMessage('연습권 $granted장을 받았어요!');
        return;
      }

      _showMessage('연습권을 확인하고 있어요. 확인되면 자동으로 들어와요.');
      unawaited(
        _finishPracticeTicketRewardInBackground(repository, session.id),
      );
    } catch (error) {
      if (!mounted) return;
      if (_isDailyGameChangedError(error)) {
        await _showDailyGameChangedDialog();
      } else if (_isTransientNetworkError(error)) {
        _showMessage('인터넷 연결이 불안정해요. 잠시 후 다시 시도해 주세요.');
      } else {
        _showMessage('연습권을 받지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  Future<int?> _claimVerifiedPracticeTickets(
    DailyGameRepository repository,
    String sessionId, {
    required int retries,
  }) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await _withTransientNetworkRetry(
          () => repository.claimPracticeTicketReward(sessionId),
        );
      } on PostgrestException catch (error) {
        if (!_isRewardPending(error)) rethrow;
        if (attempt == retries) return null;
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
    return null;
  }

  Future<void> _finishPracticeTicketRewardInBackground(
    DailyGameRepository repository,
    String sessionId,
  ) async {
    try {
      final granted = await _claimVerifiedPracticeTickets(
        repository,
        sessionId,
        retries: _rewardVerificationRetryCount,
      );
      if (!mounted || granted == null) return;
      final currentTickets =
          ref.read(todayStateProvider).value?.practiceTicketsRemaining ?? 0;
      await _animatePracticeTicketChange(
        from: currentTickets,
        to: currentTickets + granted,
      );
      if (!mounted) return;
      ref.invalidate(todayStateProvider);
      _showMessage('연습권 $granted장이 들어왔어요!');
    } catch (error, stackTrace) {
      debugPrint('[RewardedAd] Practice ticket verification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  int? _beginPlayTicketAnimation({
    required _PlayStartMode mode,
    required TodayState displayedState,
    _ChallengeStartPath? challengePath,
  }) {
    final availablePracticeTickets = max(
      displayedState.practiceTicketsRemaining,
      displayedState.storePracticeTickets,
    );
    if (mode == _PlayStartMode.practice &&
        !displayedState.testMode &&
        !displayedState.practicePending &&
        !displayedState.requiresAdForPractice &&
        availablePracticeTickets > 0) {
      final from = availablePracticeTickets;
      final to = max(0, from - 1);
      final generation = _setPracticeTicketAnimation(from: from, to: to);
      if (generation != null) {
        unawaited(_finishPracticeTicketAnimation(generation, to));
      }
      return generation;
    }

    final selectedPath =
        challengePath ?? _defaultChallengeStartPath(displayedState);
    if (mode == _PlayStartMode.challenge &&
        selectedPath == _ChallengeStartPath.challengeTicket &&
        displayedState.storeChallengeTickets > 0) {
      final from = displayedState.storeChallengeTickets;
      final to = max(0, from - 1);
      final generation = _setChallengeTicketAnimation(from: from, to: to);
      if (generation != null) {
        unawaited(_finishChallengeTicketAnimation(generation));
      }
      return generation;
    }
    return null;
  }

  Future<void> _animatePracticeTicketChange({
    required int from,
    required int to,
  }) async {
    final generation = _setPracticeTicketAnimation(from: from, to: to);
    if (generation == null) return;
    await _finishPracticeTicketAnimation(generation, to);
  }

  int? _setPracticeTicketAnimation({required int from, required int to}) {
    if (!mounted || from == to) return null;
    final generation = ++_ticketAnimationGeneration;
    setState(() {
      _practiceTicketDisplayOverride = from;
      _practiceTicketAnimationTarget = to;
      _practiceTicketAnimationDelta = to - from;
      _practiceTicketAnimationRevision++;
    });
    return generation;
  }

  Future<void> _finishPracticeTicketAnimation(int generation, int to) async {
    if (!await _waitForTicketAnimation(
      const Duration(milliseconds: 180),
      generation,
    )) {
      return;
    }
    setState(() => _practiceTicketDisplayOverride = to);
    if (!await _waitForTicketAnimation(
      const Duration(milliseconds: 470),
      generation,
    )) {
      return;
    }
    setState(() => _practiceTicketAnimationDelta = 0);
  }

  int? _setChallengeTicketAnimation({required int from, required int to}) {
    if (!mounted || from == to) return null;
    final generation = ++_ticketAnimationGeneration;
    setState(() {
      // This optimistic override starts the badge effect before the claim RPC
      // resolves. The server-backed state replaces it after the game returns.
      _challengeTicketDisplayOverride = to;
      _challengeTicketAnimationTarget = to;
    });
    return generation;
  }

  Future<void> _finishChallengeTicketAnimation(int generation) async {
    await _waitForTicketAnimation(
      _challengeTicketAnimationDuration,
      generation,
    );
  }

  Future<bool> _waitForTicketAnimation(
    Duration duration,
    int generation,
  ) async {
    _cancelTicketAnimationWaiter();
    final waiter = Completer<void>();
    _ticketAnimationWaiter = waiter;
    _ticketAnimationTimer = Timer(duration, () {
      if (identical(_ticketAnimationWaiter, waiter)) {
        _ticketAnimationWaiter = null;
        _ticketAnimationTimer = null;
      }
      if (!waiter.isCompleted) waiter.complete();
    });
    await waiter.future;
    return mounted && generation == _ticketAnimationGeneration;
  }

  void _cancelTicketAnimationWaiter() {
    _ticketAnimationTimer?.cancel();
    _ticketAnimationTimer = null;
    final waiter = _ticketAnimationWaiter;
    _ticketAnimationWaiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  void _cancelTicketAnimation(int? generation) {
    if (generation == null || generation != _ticketAnimationGeneration) return;
    _clearTicketAnimationOnNextState = false;
    _ticketAnimationGeneration++;
    _cancelTicketAnimationWaiter();
    if (!mounted) return;
    setState(() {
      _practiceTicketDisplayOverride = null;
      _practiceTicketAnimationTarget = null;
      _practiceTicketAnimationDelta = 0;
      _challengeTicketDisplayOverride = null;
      _challengeTicketAnimationTarget = null;
    });
  }

  Future<PlayAttempt> _claimDailyPractice(
    DailyGameRepository repository,
    DateTime expectedPlayDate, {
    DateTime? gameDate,
    bool reuseExistingRequest = true,
  }) async {
    if (repository case final DailyPracticeRepository practiceRepository) {
      final requestId = _pendingFreePracticeRequestId ??=
          await practiceRepository.getOrCreatePracticeRequestId(
            gameDate ?? expectedPlayDate,
            reuseExisting: reuseExistingRequest,
          );
      final attempt = await _withTransientNetworkRetry(
        () => practiceRepository.claimDailyPractice(
          expectedPlayDate,
          requestId: requestId,
          gameDate: gameDate,
        ),
      );
      return attempt;
    }
    throw StateError('daily practice is unavailable');
  }

  bool _isModeAvailable(TodayState state, _PlayStartMode mode) =>
      switch (mode) {
        _PlayStartMode.challenge => state.canChooseChallenge,
        _PlayStartMode.practice => state.canChoosePractice,
      };

  _ChallengeStartPath _defaultChallengeStartPath(TodayState state) {
    // Keep the rewarded-ad challenge first. Once it is consumed, the same
    // primary challenge button falls through to the player's ticket balance.
    if (state.canChooseAdChallenge) return _ChallengeStartPath.rewardedAd;
    if (state.rankedAdAttemptUsed || state.canChooseChallengeTicket) {
      return _ChallengeStartPath.challengeTicket;
    }
    return _ChallengeStartPath.free;
  }

  bool _isChallengeStartPathAvailable(
    TodayState state,
    _ChallengeStartPath path,
  ) => switch (path) {
    _ChallengeStartPath.free =>
      state.canChooseChallenge &&
          (state.challengePending ||
              (!state.canChooseAdChallenge && !state.canChooseChallengeTicket)),
    _ChallengeStartPath.rewardedAd => state.canChooseAdChallenge,
    _ChallengeStartPath.challengeTicket =>
      state.storeChallengeTickets > 0 && state.canChooseChallengeTicket,
  };

  Future<PlayAttempt?> _claimRewardedAttempt(
    DailyGameRepository repository,
    DateTime expectedPlayDate,
    TodayState displayedState,
  ) async => _claimAdGatedAttempt(
    displayedState: displayedState,
    isPractice: false,
    prepare: () => repository.prepareRewardedAd(expectedPlayDate),
    claim: repository.claimRewardedAttempt,
  );

  Future<PlayAttempt?> _claimPracticeAttempt(
    DailyGameRepository repository,
    DateTime expectedPlayDate,
    TodayState displayedState,
  ) async => _claimAdGatedAttempt(
    displayedState: displayedState,
    isPractice: true,
    prepare: () => repository.preparePracticeAd(expectedPlayDate),
    claim: repository.claimPracticeAttempt,
  );

  Future<PlayAttempt?> _claimAdGatedAttempt({
    required TodayState displayedState,
    required bool isPractice,
    required Future<RewardedAdSession> Function() prepare,
    required Future<PlayAttempt> Function(String sessionId) claim,
  }) async {
    final session = await _withTransientNetworkRetry(
      prepare,
    ).timeout(const Duration(seconds: 12));

    final recoveredAttempt = await _claimVerifiedReward(
      claim,
      session.id,
      retries: 0,
    ).timeout(const Duration(seconds: 12));
    if (recoveredAttempt != null) return recoveredAttempt;

    final outcome = await _rewardedAdService.show(
      userId: session.userId,
      verificationSessionId: session.id,
    );
    if (!mounted) return null;
    if (outcome == RewardedAdOutcome.dismissed) {
      _showMessage('광고를 끝까지 보면 한 판이 추가돼요.');
      return null;
    }
    if (outcome == RewardedAdOutcome.failed) {
      _showMessage('광고를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
      return null;
    }

    final repository = ref.read(dailyGameRepositoryProvider);
    if (!isPractice &&
        ref.read(localTestAdVerificationProvider) &&
        repository is LocalPracticeAdVerificationRepository) {
      await (repository as LocalPracticeAdVerificationRepository)
          .verifyLocalRewardedAd(session.id);
    }

    final game = displayedState.game;
    if (game == null) return null;

    final resolveForSubmission = _deferredRewardResolution(
      claim: claim,
      sessionId: session.id,
    );
    // Start SSV polling immediately, but do not make the player wait for it.
    // Practice never submits a score; the ranked path resolves this future
    // immediately before its score is sent to the server.
    unawaited(resolveForSubmission());

    return PlayAttempt(
      id: session.id,
      ordinal: displayedState.completedPlayCount + 1,
      status: isPractice ? 'practice' : 'issued',
      grantType: isPractice ? 'practice_ad' : 'rewarded_ad',
      gameId: game.id,
      gameVersion: game.version,
      gameDurationSeconds: game.durationSeconds,
      playDate: displayedState.playDate,
      practiceOrdinal: isPractice ? displayedState.practicePlayCount + 1 : null,
      resolveForSubmission: resolveForSubmission,
    );
  }

  Future<PlayAttempt?> Function() _deferredRewardResolution({
    required Future<PlayAttempt> Function(String sessionId) claim,
    required String sessionId,
  }) {
    Future<PlayAttempt?>? current;
    return () {
      return current ??= _verifyRewardInBackground(claim, sessionId).then((
        attempt,
      ) {
        if (attempt == null) current = null;
        return attempt;
      });
    };
  }

  Future<PlayAttempt?> _verifyRewardInBackground(
    Future<PlayAttempt> Function(String sessionId) claim,
    String sessionId,
  ) async {
    try {
      return await _claimVerifiedReward(
        claim,
        sessionId,
        retries: _rewardVerificationRetryCount,
      );
    } catch (error, stackTrace) {
      debugPrint('[RewardedAd] Background verification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } finally {
      if (mounted) ref.invalidate(todayStateProvider);
    }
  }

  Future<PlayAttempt?> _claimVerifiedReward(
    Future<PlayAttempt> Function(String sessionId) claim,
    String sessionId, {
    required int retries,
  }) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await _withTransientNetworkRetry(() => claim(sessionId));
      } on PostgrestException catch (error) {
        if (!_isRewardPending(error)) rethrow;
        if (attempt == retries) return null;
        await Future<void>.delayed(Duration(seconds: min(attempt + 1, 5)));
      }
    }
    return null;
  }

  bool _isRewardPending(PostgrestException error) =>
      error.message.contains('reward verification pending');

  bool _isDailyGameChangedError(Object error) =>
      error is PostgrestException &&
      (error.message.contains('daily game changed') ||
          error.message.contains('reward session not found') ||
          error.message.contains('practice session not found'));

  bool _isAppUpdateRequiredError(Object error) =>
      error is AppUpdateRequiredException ||
      (error is PostgrestException &&
          error.message.contains('app update required'));

  bool _isDeviceDailyLimitError(Object error) =>
      error is PostgrestException &&
      error.message.contains('daily attempt already claimed on this device');

  bool _isPlayStateChangedError(Object error) {
    if (error is! PostgrestException) return false;
    const messages = [
      'challenge is not available',
      'extra challenge choice required',
      'challenge ticket is not available',
      'practice is not available',
      'challenge requires rewarded ad',
      'practice requires rewarded ad',
      'daily rewarded ad already used',
      'daily coin ad already used',
      'another reward is pending',
      'first free play already claimed',
      'free practice ticket must be used first',
    ];
    return messages.any(error.message.contains);
  }

  Future<T> _withTransientNetworkRetry<T>(
    Future<T> Function() operation,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation();
      } catch (error) {
        if (attempt >= 1 || !_isTransientNetworkError(error)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
  }

  bool _isTransientNetworkError(Object error) {
    if (error is TimeoutException) return true;
    final message = error.toString().toLowerCase();
    const markers = [
      'socketexception',
      'timeoutexception',
      'failed host lookup',
      'connection reset',
      'connection refused',
      'network is unreachable',
      'no route to host',
      'connection timed out',
      'timed out',
    ];
    return markers.any(message.contains);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: WordSafeText(message)));
  }

  bool _isGeneratedNickname(String? nickname) {
    final normalized = nickname?.trim();
    return normalized != null && RegExp(r'^신원미상#[0-9]+$').hasMatch(normalized);
  }

  bool _isCustomNickname(String? nickname) {
    final normalized = nickname?.trim();
    return normalized != null &&
        normalized.isNotEmpty &&
        !_isGeneratedNickname(normalized);
  }

  bool _nicknameNeedsChangeTicket(String? currentNickname, String nickname) {
    final current = currentNickname?.trim();
    return _isCustomNickname(current) && current != nickname;
  }

  bool _isNicknameTicketError(Object error) =>
      error.toString().contains('nickname change ticket is not available');

  Future<void> _showNicknameTicketRequired({TodayState? sourceState}) async {
    if (!mounted) return;
    final openShop = await showPixelConfirmationDialog(
      context,
      title: '닉네임 변경권이 필요해요',
      message: '기존 닉네임을 바꾸려면 변경권 1장이 필요해요. 상점에서 500 C로 구매할까요?',
      confirmLabel: '상점 열기',
      cancelLabel: '닫기',
      dialogKey: const Key('nickname-change-ticket-required'),
      titleKey: const Key('nickname-change-ticket-required-title'),
      messageKey: const Key('nickname-change-ticket-required-message'),
      cancelKey: const Key('nickname-change-ticket-required-cancel'),
      confirmKey: const Key('nickname-change-ticket-required-shop'),
    );
    if (openShop != true || !mounted) return;
    final state = sourceState ?? ref.read(todayStateProvider).value;
    if (state != null) await _openShop(state);
  }

  Future<void> _editNickname(
    String? currentNickname, {
    int? nicknameChangeTickets,
    TodayState? sourceState,
  }) async {
    if (_isSavingProfile) return;
    var nickname = await showNicknameDialog(
      context,
      initialNickname: currentNickname,
    );
    while (nickname != null && mounted) {
      final normalizedNickname = nickname.trim();
      final requiresChangeTicket = _nicknameNeedsChangeTicket(
        currentNickname,
        normalizedNickname,
      );
      if (requiresChangeTicket) {
        final availableTickets =
            nicknameChangeTickets ??
            ref.read(todayStateProvider).value?.storeNicknameChangeTickets ??
            0;
        if (availableTickets <= 0) {
          await _showNicknameTicketRequired(sourceState: sourceState);
          return;
        }
        if (!mounted) return;
        final confirmed = await showPixelConfirmationDialog(
          context,
          title: '닉네임을 변경할까요?',
          message:
              '$currentNickname을 $normalizedNickname으로 바꾸고 닉네임 변경권 1장을 사용할까요?',
          confirmLabel: '변경하기',
          cancelLabel: '취소',
          dialogKey: const Key('nickname-change-confirmation'),
          titleKey: const Key('nickname-change-confirmation-title'),
          messageKey: const Key('nickname-change-confirmation-message'),
          cancelKey: const Key('nickname-change-cancel'),
          confirmKey: const Key('nickname-change-confirm'),
        );
        if (confirmed != true || !mounted) return;
      }

      setState(() => _isSavingProfile = true);
      try {
        await ref
            .read(dailyGameRepositoryProvider)
            .setNickname(normalizedNickname);
        ref.invalidate(todayStateProvider);
        if (!mounted) return;
        setState(() => _isSavingProfile = false);
        await _showProfileResultDialog(title: '저장 완료', message: '닉네임이 저장됐어요.');
        return;
      } catch (error) {
        if (!mounted) return;
        setState(() => _isSavingProfile = false);
        if (_isNicknameTicketError(error)) {
          await _showNicknameTicketRequired(sourceState: sourceState);
          return;
        }
        await _showProfileResultDialog(
          title: '저장 오류',
          message: _profileSaveErrorMessage(error),
        );
        if (!mounted) return;
        nickname = await showNicknameDialog(
          context,
          initialNickname: normalizedNickname,
        );
      }
    }
  }

  String _profileSaveErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('nickname already taken')) {
      return '이미 사용 중인 닉네임이에요. 다른 닉네임을 입력해 주세요.';
    }
    if (message.contains('nickname change ticket is not available')) {
      return '닉네임 변경권이 필요해요. 상점에서 500 C로 구매해 주세요.';
    }
    return '닉네임을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
  }

  Future<void> _showProfileResultDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: WordSafeText(title),
        content: WordSafeText(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const WordSafeText('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGuide(TodayState state) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GameGuideSheet(game: state.game),
    );
  }

  Future<void> _showRanking(TodayState state) {
    return _showRankingForDate(
      initialResult:
          state.result ??
          const DailyRankResult(
            score: null,
            rank: null,
            participants: 0,
            topPercent: null,
            nickname: null,
            nearby: [],
          ),
      gameId: state.game?.id,
      gameName: state.game?.displayName,
      playDate: state.playDate,
      title: state.isTomorrowPreview ? '내일의 랭킹' : '오늘의 랭킹',
    );
  }

  Future<void> _showRankingForDate({
    required DailyRankResult initialResult,
    required String? gameId,
    required String? gameName,
    required DateTime playDate,
    required String title,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RankingSheet(
        initialResult: initialResult,
        gameId: gameId,
        gameName: gameName,
        playDate: playDate,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accountDeleted) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: PixelPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: AppColors.primary,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const WordSafeText(
                      '계정과 데이터가 삭제됐어요.',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const WordSafeText(
                      '다시 시작하면 기존 기록과 연결되지 않는 새 익명 계정이 만들어집니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    PixelButton(
                      label: '새로 시작',
                      onPressed: () {
                        setState(() => _accountDeleted = false);
                        ref.invalidate(todayStateProvider);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final today = ref.watch(todayStateProvider);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _PixelGridBackground()),
            today.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: PixelPanel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const WordSafeText('서버에 연결하지 못했어요.'),
                        const SizedBox(height: 16),
                        PixelButton(
                          label: '다시 연결',
                          onPressed: () => ref.invalidate(todayStateProvider),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              data: (state) => state.requiresUpdate
                  ? _RequiredUpdateView(compatibility: state.compatibility)
                  : Builder(
                      builder: (context) {
                        final displayedState = _showTomorrow
                            ? state.tomorrowPreview ?? state
                            : state;
                        final displayedPracticeTickets =
                            _practiceTicketDisplayOverride ??
                            max(
                              displayedState.practiceTicketsRemaining,
                              displayedState.storePracticeTickets,
                            );
                        final displayedChallengeTickets =
                            _challengeTicketDisplayOverride ??
                            displayedState.storeChallengeTickets;
                        return Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _Header(
                                    playDate: displayedState.playDate,
                                    isTomorrow:
                                        displayedState.isTomorrowPreview,
                                    tomorrowAvailable: state.tomorrow != null,
                                    isSaving:
                                        _isSavingProfile ||
                                        _isRunningDeveloperAction ||
                                        _isLinkingKakao,
                                    onHistory: () => context.push('/history'),
                                    onShop: () => _openShop(state),
                                    onSettings: () => _handleSettingsTap(state),
                                    onTomorrow: () {
                                      if (state.tomorrow == null) return;
                                      setState(() {
                                        _showTomorrow = !_showTomorrow;
                                        _playActionNotice = null;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  _GamePreview(gameId: displayedState.game?.id),
                                  const SizedBox(height: 18),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: WordSafeText(
                                          displayedState.game?.displayName ??
                                              '게임 준비 중',
                                          key: const Key('today-game-title'),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                      ),
                                      if (!displayedState.testMode) ...[
                                        const SizedBox(width: 12),
                                        _TicketInventory(
                                          key: const Key('ticket-inventory'),
                                          practiceCount:
                                              displayedPracticeTickets,
                                          challengeCount:
                                              displayedChallengeTickets,
                                          showChallengeTicketAnimation:
                                              _challengeTicketDisplayOverride !=
                                              null,
                                          practiceDelta:
                                              _practiceTicketAnimationDelta,
                                          practiceAnimationRevision:
                                              _practiceTicketAnimationRevision,
                                        ),
                                      ],
                                      if (displayedState.testMode)
                                        const _StatusBadge(label: 'TEST MODE'),
                                    ],
                                  ),
                                  if (displayedState.result?.score
                                      case final score?) ...[
                                    const SizedBox(height: 10),
                                    WordSafeText(
                                      '내 기록 ${GameRegistry.formatScore(displayedState.game?.id, score)}'
                                      '${displayedState.result?.rank == null ? '' : ' · ${displayedState.result!.rank}등'}',
                                      style: const TextStyle(
                                        color: AppColors.reward,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _HomeActionButton(
                                          key: const Key('game-guide-button'),
                                          label: '게임 설명',
                                          icon: Icons.menu_book_outlined,
                                          onPressed: () =>
                                              _showGuide(displayedState),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _HomeActionButton(
                                          key: const Key('ranking-button'),
                                          label:
                                              displayedState.isTomorrowPreview
                                              ? '내일의 랭킹'
                                              : '오늘의 랭킹',
                                          icon: Icons.emoji_events_outlined,
                                          onPressed: () =>
                                              _showRanking(displayedState),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _HomeActionButton(
                                          key: const Key('duel-lobby-button'),
                                          label: '1:1 대결',
                                          icon: Icons.sports_esports_outlined,
                                          compact: true,
                                          onPressed: () =>
                                              Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      const DuelLobbyScreen(),
                                                ),
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  _buildPlayActions(displayedState),
                                  const SizedBox(height: 14),
                                  WordSafeText(
                                    _playActionNotice ??
                                        _statusText(displayedState),
                                    key: const Key('play-action-status'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_coinRewardEffect case final effect?)
              Positioned(
                top: 72,
                left: 18,
                right: 18,
                child: IgnorePointer(
                  child: _CoinRewardEffect(
                    key: const Key('daily-coin-reward-effect'),
                    data: effect,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayActions(TodayState state) {
    final canClaimPracticeReward = state.canClaimPracticeReward;
    final challengePath = _defaultChallengeStartPath(state);
    final canStartChallenge = _canStartPlay(
      state,
      _PlayStartMode.challenge,
      challengePath: challengePath,
    );
    final challenge = PixelButton(
      key: const Key('challenge-button'),
      label: _challengeButtonLabel(state),
      icon: Icons.sports_score_rounded,
      onPressed: canStartChallenge
          ? () => _start(
              mode: _PlayStartMode.challenge,
              displayedState: state,
              challengePath: challengePath,
            )
          : null,
      onDisabledPressed: !canStartChallenge && !_isClaiming
          ? () => _showPlayActionNotice(
              state.isTomorrowPreview
                  ? '내일의 도전은 내일부터 시작할 수 있어요.'
                  : state.canChooseChallengeTicket &&
                        !state.canChooseAdChallenge
                  ? '도전권으로 진짜 딱 한 판만 더 도전할 수 있어요.'
                  : state.canChooseAdChallenge && !_isRewardedAdSelectable
                  ? '광고를 준비해 주세요.'
                  : '오늘은 더 이상 도전할 수 없어요.',
            )
          : null,
    );
    final practice = PixelButton(
      key: const Key('practice-button'),
      label: canClaimPracticeReward ? '티켓 받기 +2' : _practiceButtonLabel(state),
      icon: canClaimPracticeReward
          ? Icons.ondemand_video_outlined
          : Icons.confirmation_number_rounded,
      onPressed: canClaimPracticeReward
          ? (!_isClaiming &&
                    _rewardedAdStatus != RewardedAdStatus.disabled &&
                    _rewardedAdStatus != RewardedAdStatus.loading
                ? () => _claimPracticeTicketReward(state)
                : null)
          : (_canStartPlay(state, _PlayStartMode.practice)
                ? () => _start(
                    mode: _PlayStartMode.practice,
                    displayedState: state,
                  )
                : null),
      onDisabledPressed: !state.canChoosePractice
          ? () => _showPlayActionNotice(
              canClaimPracticeReward
                  ? '연습권이 없어요. 광고를 보고 2장을 받을 수 있어요.'
                  : '오늘 사용할 수 있는 연습권을 모두 썼어요.',
            )
          : null,
    );

    return Row(
      children: [
        Expanded(child: practice),
        const SizedBox(width: 10),
        Expanded(child: challenge),
      ],
    );
  }

  void _showPlayActionNotice(String message) {
    _playActionNoticeTimer?.cancel();
    setState(() => _playActionNotice = message);
    _playActionNoticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _playActionNotice = null);
    });
  }

  bool _canStartPlay(
    TodayState state,
    _PlayStartMode mode, {
    _ChallengeStartPath? challengePath,
  }) {
    if (_isClaiming) return false;
    if (mode == _PlayStartMode.challenge) {
      final path = challengePath ?? _defaultChallengeStartPath(state);
      if (!_isChallengeStartPathAvailable(state, path)) return false;
      return path != _ChallengeStartPath.rewardedAd || _isRewardedAdSelectable;
    }
    if (!_isModeAvailable(state, mode)) return false;
    final requiresAd = switch (mode) {
      _PlayStartMode.challenge => state.requiresAdForChallenge,
      _PlayStartMode.practice => state.requiresAdForPractice,
    };
    if (!requiresAd) return true;
    return _rewardedAdStatus != RewardedAdStatus.disabled &&
        _rewardedAdStatus != RewardedAdStatus.loading;
  }

  bool get _isRewardedAdSelectable =>
      _rewardedAdStatus != RewardedAdStatus.disabled &&
      _rewardedAdStatus != RewardedAdStatus.loading;

  String _challengeButtonLabel(TodayState state) {
    if (_isClaiming) return '로딩중';
    if (state.isTomorrowPreview) return '내일 도전 대기';
    if (state.canChooseAdChallenge) {
      return '진짜 딱 한판만!';
    }
    if (state.rankedAdAttemptUsed || state.canChooseChallengeTicket) {
      return '도전권으로 도전!';
    }
    return '오늘의 도전!';
  }

  String _practiceButtonLabel(TodayState state) {
    if (_isClaiming) return '로딩중';
    return '연습하기';
  }

  String _statusText(TodayState state) {
    if (state.isTomorrowPreview) {
      if (state.canChoosePractice) {
        return '오늘과 공유하는 연습권 ${state.practiceTicketsRemaining}장 · 도전은 내일부터';
      }
      if (state.canClaimPracticeReward) return '연습권을 받으면 내일 게임을 연습할 수 있어요';
      return '내일의 도전은 아직 시작할 수 없어요';
    }
    if (state.testMode) return '테스트 모드 · 제한 없이 계속 플레이할 수 있어요';
    if (state.deviceDailyLimitReached) {
      return '오늘 이 기기의 무료 플레이를 이미 사용했어요';
    }
    if (state.completedPlayCount == 0) return '연습권 1장 · 오늘의 도전 1회';
    if (state.canChooseAdChallenge) {
      return '광고를 보면 진짜 딱 한 판만 더 할 수 있어요';
    }
    if (state.canChooseChallengeTicket) {
      return '광고 추가 도전 완료 · 도전권 ${state.storeChallengeTickets}장으로 계속 도전할 수 있어요';
    }
    if (state.canChooseChallenge && state.canChoosePractice) {
      return '연습권 ${state.practiceTicketsRemaining}장 · 오늘의 도전이 남아 있어요';
    }
    if (state.canChooseChallenge) {
      return state.canClaimPracticeReward
          ? '무료 연습 완료 · 연습권을 더 받거나 도전하세요'
          : '오늘의 도전이 남아 있어요';
    }
    if (state.canChoosePractice) {
      return '도전 완료 · 연습권 ${state.practiceTicketsRemaining}장';
    }
    if (state.canClaimPracticeReward) return '광고를 보면 연습권 2장을 받을 수 있어요';
    if (state.hasPlayed) return '오늘의 플레이를 모두 마쳤어요';
    if (state.dailyClaimed) return '이 기기의 오늘 플레이는 이미 완료됐어요';
    return '중단된 게임은 다시 시작할 수 없어요';
  }
}

class _RequiredUpdateView extends StatelessWidget {
  const _RequiredUpdateView({required this.compatibility});

  final ClientCompatibility compatibility;

  Future<void> _openStore(BuildContext context) async {
    final rawUrl = compatibility.storeUrl;
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: WordSafeText('스토어를 열지 못했어요. 잠시 후 다시 시도해 주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productionReleaseRequired =
        compatibility.reason == 'production_release_required';
    return Center(
      key: const Key('required-update-screen'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: PixelPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_alt_rounded,
                  color: AppColors.primary,
                  size: 56,
                ),
                const SizedBox(height: 18),
                WordSafeText(
                  productionReleaseRequired
                      ? '정식 버전으로 업데이트해 주세요'
                      : '게임이 업데이트 되었어요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                WordSafeText(
                  productionReleaseRequired
                      ? '알파 테스트 대신 Google Play의 정식 버전을 이용해 주세요.'
                      : '원활한 게임 플레이를 위해\n앱을 업데이트 해주세요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
                PixelButton(
                  key: const Key('required-update-button'),
                  label: productionReleaseRequired ? '정식 버전 받기' : '스토어에서 업데이트',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => _openStore(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyGameChangedDialog extends StatelessWidget {
  const _DailyGameChangedDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('daily-game-changed-dialog'),
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.primary, width: 3),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: AppColors.primaryShadow, offset: Offset(0, 7)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WordSafeText(
                '오늘의 게임이 바뀌었어요',
                key: Key('daily-game-changed-title'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 22,
                  height: 1.3,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
                decoration: BoxDecoration(
                  color: AppColors.backgroundDeep,
                  border: Border.all(color: AppColors.surfaceLight),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const WordSafeText(
                  '날짜가 바뀌어 새로운 게임을 불러올게요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: PixelButton(
                  key: const Key('load-new-daily-game-button'),
                  label: '새 게임 보기',
                  icon: Icons.refresh_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinRewardEffectData {
  const _CoinRewardEffectData({
    required this.fromCoins,
    required this.targetCoins,
    required this.delta,
  });

  final int fromCoins;
  final int targetCoins;
  final int delta;
}

class _CoinRewardEffect extends StatefulWidget {
  const _CoinRewardEffect({required this.data, super.key});

  final _CoinRewardEffectData data;

  @override
  State<_CoinRewardEffect> createState() => _CoinRewardEffectState();
}

class _CoinRewardEffectState extends State<_CoinRewardEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final progress = Curves.easeOutCubic.transform(_controller.value);
      final visibleCoins =
          widget.data.fromCoins +
          ((widget.data.targetCoins - widget.data.fromCoins) * progress)
              .round();
      final opacity = (1 - Curves.easeIn.transform(_controller.value * 0.7))
          .clamp(0.0, 1.0)
          .toDouble();
      const particleOffsets = [
        Offset(-24, -5),
        Offset(24, -5),
        Offset(-20, 8),
        Offset(20, 8),
      ];

      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Opacity(
            opacity: opacity,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.primaryShadow,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 30,
                        height: 24,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            for (
                              var index = 0;
                              index < particleOffsets.length;
                              index++
                            )
                              Transform.translate(
                                offset: Offset(
                                  particleOffsets[index].dx * progress,
                                  particleOffsets[index].dy * progress,
                                ),
                                child: Opacity(
                                  opacity: (1 - progress)
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                                  child: Icon(
                                    index.isEven
                                        ? Icons.auto_awesome
                                        : Icons.circle,
                                    color: index.isEven
                                        ? AppColors.primary
                                        : AppColors.reward,
                                    size: index.isEven ? 10 : 5,
                                  ),
                                ),
                              ),
                            Transform.scale(
                              scale: 1 + (0.1 * (1 - progress)),
                              child: const CoinMark(
                                color: AppColors.primary,
                                inkColor: AppColors.surface,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Expanded(
                        child: WordSafeText(
                          '내 지갑에 코인 추가',
                          singleLine: true,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      WordSafeText(
                        '+${widget.data.delta} C',
                        key: const Key('daily-coin-reward-gain'),
                        singleLine: true,
                        style: const TextStyle(
                          color: AppColors.reward,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: WordSafeText(
                          '$visibleCoins C',
                          key: const Key('daily-coin-reward-balance'),
                          textAlign: TextAlign.center,
                          singleLine: true,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontFamily: 'Galmuri',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.textMuted,
                        size: 16,
                      ),
                      Expanded(
                        child: WordSafeText(
                          '${widget.data.targetCoins} C',
                          key: const Key('daily-coin-reward-target'),
                          textAlign: TextAlign.center,
                          singleLine: true,
                          style: const TextStyle(
                            color: AppColors.reward,
                            fontFamily: 'Galmuri',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PreviousResultDialogOutcome {
  const _PreviousResultDialogOutcome({required this.reward});

  final RewardGrant reward;
}

class _PreviousDailyResultDialog extends StatefulWidget {
  const _PreviousDailyResultDialog({
    required this.result,
    required this.onClaim,
    required this.onShowRanking,
  });

  final PreviousDailyResult result;
  final Future<RewardGrant> Function() onClaim;
  final Future<void> Function() onShowRanking;

  @override
  State<_PreviousDailyResultDialog> createState() =>
      _PreviousDailyResultDialogState();
}

class _PreviousDailyResultDialogState extends State<_PreviousDailyResultDialog>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _rewardController;
  RewardGrant? _reward;
  String? _errorMessage;
  var _isClaiming = false;
  var _isShowingRanking = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _rewardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    unawaited(_entryController.forward());
  }

  @override
  void dispose() {
    _entryController.dispose();
    _rewardController.dispose();
    super.dispose();
  }

  Future<void> _claimAndClose() async {
    if (_isClaiming || _reward != null) return;
    setState(() {
      _errorMessage = null;
      _isClaiming = true;
    });
    try {
      final reward = await widget.onClaim();
      if (!mounted) return;
      setState(() {
        _reward = reward;
        _isClaiming = false;
      });
      await _rewardController.forward(from: 0);
      if (!mounted) return;
      Navigator.of(context).pop(_PreviousResultDialogOutcome(reward: reward));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isClaiming = false;
        _errorMessage = '보상을 받지 못했어요. 잠시 후 다시 눌러 주세요.';
      });
    }
  }

  Future<void> _openRanking() async {
    if (_isClaiming || _isShowingRanking || _reward != null) return;
    setState(() {
      _errorMessage = null;
      _isShowingRanking = true;
    });
    try {
      await widget.onShowRanking();
    } finally {
      if (mounted) setState(() => _isShowingRanking = false);
    }
  }

  Future<void> _showRewardRules() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DailyRewardRulesDialog(result: widget.result),
    );
  }

  Widget _enterAnimation({required Widget child}) => AnimatedBuilder(
    animation: _entryController,
    builder: (context, child) {
      final progress = Curves.easeOutCubic.transform(_entryController.value);
      return Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - progress)),
          child: child,
        ),
      );
    },
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final reward = _reward;
    final canInteract = !_isClaiming && !_isShowingRanking && reward == null;
    return Dialog(
      key: const Key('previous-daily-result-dialog'),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.primary, width: 2),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: AppColors.primaryShadow, offset: Offset(0, 6)),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _enterAnimation(
                  child: const WordSafeText(
                    '어제의 최종 결과',
                    singleLine: true,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _enterAnimation(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WordSafeText(
                        result.displayName,
                        singleLine: true,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      WordSafeText(
                        GameRegistry.formatScore(result.gameId, result.score),
                        key: const Key('previous-result-score'),
                        singleLine: true,
                        style: const TextStyle(
                          fontFamily: 'Galmuri',
                          color: AppColors.reward,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      WordSafeText(
                        '실제 기록 ${result.participants}개 중 '
                        '${result.rank}위 · 상위 ${result.topPercent}%',
                        key: const Key('previous-result-rank'),
                        singleLine: true,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        key: const Key('previous-result-reward'),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                        decoration: BoxDecoration(
                          color: AppColors.reward.withValues(alpha: 0.12),
                          border: Border.all(
                            color: AppColors.reward.withValues(alpha: 0.6),
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: animation,
                                  child: child,
                                ),
                              ),
                          child: reward == null
                              ? _RewardPreview(
                                  key: const ValueKey(
                                    'previous-reward-preview',
                                  ),
                                  result: result,
                                  animation: _entryController,
                                  onHelp: canInteract
                                      ? () => unawaited(_showRewardRules())
                                      : null,
                                )
                              : _RewardReceived(
                                  key: const ValueKey(
                                    'previous-reward-received',
                                  ),
                                  reward: reward,
                                  animation: _rewardController,
                                  onHelp: canInteract
                                      ? () => unawaited(_showRewardRules())
                                      : null,
                                ),
                        ),
                      ),
                      if (_errorMessage case final error?) ...[
                        const SizedBox(height: 10),
                        WordSafeText(
                          error,
                          singleLine: true,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('previous-result-ranking'),
                      onPressed: canInteract
                          ? () => unawaited(_openRanking())
                          : null,
                      child: const WordSafeText('랭킹 보기', singleLine: true),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('acknowledge-previous-result'),
                      onPressed: canInteract
                          ? () => unawaited(_claimAndClose())
                          : null,
                      child: WordSafeText(
                        _isClaiming
                            ? '보상 받는 중…'
                            : _isShowingRanking
                            ? '랭킹 보는 중…'
                            : '확인',
                        singleLine: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyRewardRulesDialog extends StatelessWidget {
  const _DailyRewardRulesDialog({required this.result});

  final PreviousDailyResult result;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('daily-reward-rules-dialog'),
    backgroundColor: AppColors.surface,
    title: Row(
      children: [
        const Icon(Icons.help_outline_rounded, color: AppColors.reward),
        const SizedBox(width: 8),
        const Expanded(
          child: WordSafeText(
            '매일 보상 기준',
            singleLine: true,
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        IconButton(
          key: const Key('daily-reward-rules-close'),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '닫기',
          icon: const Icon(Icons.close, color: AppColors.text),
        ),
      ],
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.reward.withValues(alpha: 0.1),
              border: Border.all(
                color: AppColors.reward.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: WordSafeText(
                    '이번 기록',
                    singleLine: true,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                WordSafeText(
                  '${result.rank}위 · 상위 ${result.topPercent}%',
                  singleLine: true,
                  style: const TextStyle(
                    color: AppColors.reward,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const WordSafeText(
            '매일 기본 보상에 랭킹 보너스가 더해져요.',
            singleLine: true,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const _RewardRuleRow(label: '매일 기본', rankingBonus: 0, isBase: true),
          const SizedBox(height: 4),
          const WordSafeText(
            '랭킹 보너스',
            singleLine: true,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          _RewardRuleRow(
            label: '1위',
            rankingBonus: DailyRewardRules.firstPlaceRankingBonusCoins,
          ),
          _RewardRuleRow(
            label: '상위 10%',
            rankingBonus: DailyRewardRules.topTenPercentRankingBonusCoins,
          ),
          _RewardRuleRow(
            label: '상위 30%',
            rankingBonus: DailyRewardRules.topThirtyPercentRankingBonusCoins,
          ),
          _RewardRuleRow(
            label: '상위 50%',
            rankingBonus: DailyRewardRules.topHalfRankingBonusCoins,
          ),
          _RewardRuleRow(
            label: '상위 70%',
            rankingBonus: DailyRewardRules.topSeventyPercentRankingBonusCoins,
          ),
          _RewardRuleRow(
            label: '그 외 참여',
            rankingBonus: DailyRewardRules.otherRankingBonusCoins,
          ),
          const SizedBox(height: 10),
          const WordSafeText(
            '기본 보상과 랭킹 보너스는 코인·EXP에 같은 수치로 적용돼요.',
            singleLine: true,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        key: const Key('daily-reward-rules-confirm'),
        onPressed: () => Navigator.of(context).pop(),
        child: const WordSafeText('확인', singleLine: true),
      ),
    ],
  );
}

class _RewardRuleRow extends StatelessWidget {
  const _RewardRuleRow({
    required this.label,
    required this.rankingBonus,
    this.isBase = false,
  });

  final String label;
  final int rankingBonus;
  final bool isBase;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: AppColors.backgroundDeep,
      child: Row(
        children: [
          Expanded(
            child: WordSafeText(
              label,
              singleLine: true,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              WordSafeText(
                isBase
                    ? '+${DailyRewardRules.dailyBaseCoins} C · '
                          '+${DailyRewardRules.dailyBaseCoins} EXP'
                    : rankingBonus == 0
                    ? '없음'
                    : '+$rankingBonus 보너스',
                singleLine: true,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!isBase)
                WordSafeText(
                  '총 +${DailyRewardRules.dailyBaseCoins + rankingBonus} C · '
                  '+${DailyRewardRules.dailyBaseCoins + rankingBonus} EXP',
                  singleLine: true,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _RewardPreview extends StatelessWidget {
  const _RewardPreview({
    required this.result,
    required this.animation,
    required this.onHelp,
    super.key,
  });

  final PreviousDailyResult result;
  final Animation<double> animation;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final progress = const Interval(
        0.28,
        1,
        curve: Curves.easeOutCubic,
      ).transform(animation.value);
      final finalCoins = result.effectiveRewardCoins;
      final baseCoins = finalCoins > 0 ? DailyRewardRules.dailyBaseCoins : 0;
      final rankingBonus = max(0, finalCoins - baseCoins);
      final coins = baseCoins + (rankingBonus * progress).round();
      return Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WordSafeText(
                '매일 기본 + 랭킹 보너스',
                singleLine: true,
                style: TextStyle(
                  color: AppColors.reward,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              IconButton(
                key: const Key('previous-result-reward-help'),
                onPressed: onHelp,
                tooltip: '보상 기준 보기',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(
                  Icons.help_outline_rounded,
                  color: AppColors.reward,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          WordSafeText(
            '기본 +$baseCoins C · 랭킹 보너스 +$rankingBonus C',
            singleLine: true,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _RewardValue(
                  icon: Icons.monetization_on_outlined,
                  value: '+$coins',
                  label: 'COINS',
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: AppColors.reward.withValues(alpha: 0.35),
              ),
              Expanded(
                child: _RewardValue(
                  icon: Icons.auto_awesome_outlined,
                  value: '+$coins',
                  label: 'EXP',
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const WordSafeText(
            '확인을 누르면 바로 받고, 놓쳐도 다음날 자동 지급돼요',
            singleLine: true,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    },
  );
}

class _RewardReceived extends StatelessWidget {
  const _RewardReceived({
    required this.reward,
    required this.animation,
    required this.onHelp,
    super.key,
  });

  final RewardGrant reward;
  final Animation<double> animation;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final progress = Curves.easeOutCubic.transform(animation.value);
      final coins = (reward.coinsGranted * progress).round();
      final experience = (reward.experienceGranted * progress).round();
      final scale = 0.88 + (0.12 * Curves.easeOutBack.transform(progress));
      return Transform.scale(
        scale: scale,
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const WordSafeText(
                  '보상 획득!',
                  singleLine: true,
                  style: TextStyle(
                    color: AppColors.reward,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                IconButton(
                  key: const Key('previous-result-reward-help'),
                  onPressed: onHelp,
                  tooltip: '보상 기준 보기',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: const Icon(
                    Icons.help_outline_rounded,
                    color: AppColors.reward,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const WordSafeText(
              '순위에 따라 코인과 EXP가 달라져요',
              singleLine: true,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _RewardValue(
                    icon: Icons.monetization_on_outlined,
                    value: '+$coins',
                    label: 'COINS',
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: AppColors.reward.withValues(alpha: 0.35),
                ),
                Expanded(
                  child: _RewardValue(
                    icon: Icons.auto_awesome_outlined,
                    value: '+$experience',
                    label: 'EXP',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            const WordSafeText(
              '기본 보상과 랭킹 보너스가 지갑에 추가됐어요',
              singleLine: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    },
  );
}

enum _SettingsAction {
  profile,
  socialNotifications,
  pushDeviceSettings,
  legal,
  support,
  adPrivacy,
  delete,
  developer,
  testerActivation,
  testerDeactivation,
}

enum _LegalDocument { privacy, terms, community }

class _SupportInquiryDialog extends StatefulWidget {
  const _SupportInquiryDialog({required this.onSubmit});

  final Future<String> Function(String message) onSubmit;

  @override
  State<_SupportInquiryDialog> createState() => _SupportInquiryDialogState();
}

class _SupportInquiryDialogState extends State<_SupportInquiryDialog> {
  final _controller = TextEditingController();
  var _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (_submitting || message.length < 5) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await widget.onSubmit(message);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = '문의를 접수하지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.surface,
    title: const WordSafeText('문의하기'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WordSafeText('불편한 점이나 궁금한 내용을 남겨 주세요.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('support-inquiry-field'),
            controller: _controller,
            autofocus: true,
            minLines: 5,
            maxLines: 8,
            maxLength: 1000,
            enabled: !_submitting,
            onChanged: (_) => setState(() => _errorMessage = null),
            decoration: InputDecoration(
              hintText: '문의 내용을 5자 이상 입력해 주세요.',
              errorText: _errorMessage,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
        child: const WordSafeText('취소'),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) => FilledButton(
          key: const Key('submit-support-inquiry'),
          onPressed: !_submitting && value.text.trim().length >= 5
              ? _submit
              : null,
          child: WordSafeText(_submitting ? '접수 중...' : '접수하기'),
        ),
      ),
    ],
  );
}

class _DeveloperAction {
  const _DeveloperAction.changeGame(this.gameId) : resetProgress = false;
  const _DeveloperAction.reset() : gameId = null, resetProgress = true;

  final String? gameId;
  final bool resetProgress;
}

class _TesterPinDialog extends StatefulWidget {
  const _TesterPinDialog({required this.onActivate});

  final Future<TesterActivationResult> Function(String pin) onActivate;

  @override
  State<_TesterPinDialog> createState() => _TesterPinDialogState();
}

class _TesterPinDialogState extends State<_TesterPinDialog> {
  final _controller = TextEditingController();
  var _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || _controller.text.length != 6) return;
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await widget.onActivate(_controller.text);
      if (!mounted) return;
      switch (result.status) {
        case TesterActivationStatus.activated:
          Navigator.of(context).pop(true);
        case TesterActivationStatus.invalid:
          _controller.clear();
          setState(() {
            final remaining = result.attemptsRemaining;
            _errorText = remaining == null
                ? 'PIN이 올바르지 않아요.'
                : 'PIN이 올바르지 않아요. $remaining회 남았어요.';
          });
        case TesterActivationStatus.locked:
          final seconds = result.retryAfterSeconds ?? 900;
          final minutes = (seconds / 60).ceil();
          setState(() {
            _errorText = '입력 횟수를 초과했어요. 약 $minutes분 후 다시 시도해 주세요.';
          });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = '인증하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const WordSafeText('테스터 인증'),
      content: TextField(
        key: const Key('tester-pin-field'),
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: InputDecoration(
          labelText: '6자리 PIN',
          errorText: _errorText,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const WordSafeText('취소'),
        ),
        FilledButton(
          key: const Key('activate-tester-mode'),
          onPressed: _isSubmitting ? null : _submit,
          child: WordSafeText(_isSubmitting ? '확인 중...' : '확인'),
        ),
      ],
    );
  }
}

class _DeveloperToolsDialog extends StatefulWidget {
  const _DeveloperToolsDialog({
    required this.games,
    required this.currentGameId,
  });

  final List<DeveloperGame> games;
  final String? currentGameId;

  @override
  State<_DeveloperToolsDialog> createState() => _DeveloperToolsDialogState();
}

class _DeveloperToolsDialogState extends State<_DeveloperToolsDialog> {
  late String? _selectedGameId =
      widget.games.any((game) => game.id == widget.currentGameId)
      ? widget.currentGameId
      : widget.games.firstOrNull?.id;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const WordSafeText('개발자 모드'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('developer-game-dropdown'),
            initialValue: _selectedGameId,
            decoration: const InputDecoration(
              labelText: '테스트할 게임',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final game in widget.games)
                DropdownMenuItem(
                  value: game.id,
                  child: WordSafeText('${game.displayName} v${game.version}'),
                ),
            ],
            onChanged: (value) => setState(() => _selectedGameId = value),
          ),
          const SizedBox(height: 12),
          const WordSafeText(
            '게임 변경은 현재 테스트 계정에만 적용됩니다.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('reset-daily-progress'),
          onPressed: () =>
              Navigator.of(context).pop(const _DeveloperAction.reset()),
          child: const WordSafeText('게임 횟수 초기화'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const WordSafeText('닫기'),
        ),
        FilledButton(
          key: const Key('apply-developer-game'),
          onPressed: _selectedGameId == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_DeveloperAction.changeGame(_selectedGameId)),
          child: const WordSafeText('게임 적용'),
        ),
      ],
    );
  }
}

class _RankingSheet extends ConsumerWidget {
  const _RankingSheet({
    required this.initialResult,
    required this.gameId,
    required this.gameName,
    required this.playDate,
    required this.title,
  });

  final DailyRankResult initialResult;
  final String? gameId;
  final String? gameName;
  final DateTime playDate;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref
        .watch(dailyRankProvider(playDate))
        .when(
          data: (latest) => latest,
          error: (_, _) => initialResult,
          loading: () => initialResult,
        );
    final previousResult = gameId == null
        ? null
        : ref
              .watch(
                previousGameWinnerProvider((
                  gameId: gameId!,
                  beforeDate: playDate,
                )),
              )
              .when(
                data: (winner) => winner,
                error: (_, _) => null,
                loading: () => null,
              );
    final hasPreviousWinner =
        previousResult?.leaders.any((entry) => entry.rank == 1) ?? false;
    final rankingEntries = [...result.leaders]
      ..sort((a, b) => a.rank.compareTo(b.rank));
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader(
            eyebrow: 'DAILY LEADERBOARD',
            title: title,
            onClose: () => Navigator.of(context).pop(),
            closeKey: const Key('ranking-sheet-close'),
          ),
          if (hasPreviousWinner &&
              gameId != null &&
              gameName != null &&
              previousResult != null) ...[
            const SizedBox(height: 16),
            _RankingSectionTitle(
              eyebrow: 'PREVIOUS WINNER',
              title: '지난 $gameName 1등',
            ),
            const SizedBox(height: 10),
            _PreviousWinnerCard(gameId: gameId!, result: previousResult),
          ],
          const SizedBox(height: 16),
          const _RankingSectionTitle(eyebrow: 'TOP SCORES', title: '전체 랭킹'),
          const SizedBox(height: 10),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  key: const Key('overall-leaderboard'),
                  scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
                  padding: const EdgeInsets.only(bottom: 72),
                  children: [
                    if (rankingEntries.isEmpty)
                      const SizedBox(
                        height: 130,
                        child: Center(
                          child: WordSafeText(
                            '아직 등록된 기록이 없어요.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      )
                    else
                      for (
                        var index = 0;
                        index < rankingEntries.length;
                        index++
                      ) ...[
                        _LeaderboardRow(
                          entry: rankingEntries[index],
                          gameId: gameId,
                          onAction: () => _showRankActions(
                            context,
                            ref,
                            rankingEntries[index],
                            canBoast:
                                result.score != null && result.rank != null,
                          ),
                        ),
                        if (index < rankingEntries.length - 1)
                          const SizedBox(height: 6),
                      ],
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      key: const Key('daily-nonplayers-button'),
                      onPressed: gameId == null
                          ? null
                          : () => _showNonplayers(
                              context,
                              playDate: playDate,
                              gameId: gameId!,
                              canBoast:
                                  result.score != null && result.rank != null,
                            ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        foregroundColor: AppColors.text,
                        disabledForegroundColor: AppColors.textMuted,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(
                          fontFamily: 'Galmuri',
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      icon: const Icon(Icons.people_outline, size: 20),
                      label: const WordSafeText('아직 플레이하지 않은 유저 보기'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showNonplayers(
    BuildContext context, {
    required DateTime playDate,
    required String gameId,
    required bool canBoast,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DailyNonplayersSheet(
        playDate: playDate,
        gameId: gameId,
        canBoast: canBoast,
      ),
    );
  }

  Future<void> _showRankActions(
    BuildContext context,
    WidgetRef ref,
    NearbyRank entry, {
    required bool canBoast,
  }) async {
    final targetUserId = entry.userId;
    if (targetUserId == null) return;
    await _showRankActionsForTarget(
      context,
      ref,
      targetUserId: targetUserId,
      nickname: entry.nickname,
      canBoast: canBoast,
    );
  }
}

Future<void> _showRankActionsForTarget(
  BuildContext context,
  WidgetRef ref, {
  required String targetUserId,
  required String nickname,
  required bool canBoast,
  bool allowDuel = true,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RankActionSheet(
      userId: targetUserId,
      nickname: nickname,
      canBoast: canBoast,
      allowDuel: allowDuel,
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'duel') {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DuelLobbyScreen(
          initialOpponentUserId: targetUserId,
          initialOpponentNickname: nickname,
        ),
      ),
    );
    return;
  }
  await _handleRankActionForTarget(
    context,
    ref,
    targetUserId: targetUserId,
    nickname: nickname,
    action: action,
  );
}

Future<void> _handleRankActionForTarget(
  BuildContext context,
  WidgetRef ref, {
  required String targetUserId,
  required String nickname,
  required String action,
}) async {
  var chosenAction = action;
  if (action == 'gift') {
    final state = ref.read(todayStateProvider).value;
    final item = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _RankGiftSheet(
        nickname: nickname,
        practiceTickets: state?.storePracticeTickets ?? 0,
        challengeTickets: state?.storeChallengeTickets ?? 0,
        nicknameChangeTickets: state?.storeNicknameChangeTickets ?? 0,
      ),
    );
    if (item == null || !context.mounted) return;
    chosenAction = item;
  }
  final actionLabel = switch (action) {
    'poke' => '찌르기',
    'boast' => '자랑하기',
    _ => '선물하기',
  };
  try {
    final SocialRepository repository = ref.read(socialRepositoryProvider);
    if (action == 'gift') {
      await repository.giftShopItem(
        targetUserId: targetUserId,
        itemId: chosenAction,
      );
      ref.invalidate(todayStateProvider);
    } else {
      await repository.sendSocialAction(
        targetUserId: targetUserId,
        action: action,
      );
    }
    if (!context.mounted) return;
    final successMessage = switch (action) {
      'poke' => '$nickname님을 찔렀어요.',
      'boast' => '$nickname님에게 내 순위를 자랑했어요.',
      _ =>
        '$nickname님에게 ${switch (chosenAction) {
          'practice_ticket' => '연습권',
          'challenge_ticket' => '도전권',
          'nickname_change_ticket' => '닉네임 변경권',
          _ => '아이템',
        }} 1장을 선물했어요.',
    };
    await showPixelCompletionDialog(
      context,
      title: '$actionLabel 완료',
      message: successMessage,
      dialogKey: Key('social-$action-completed'),
      titleKey: Key('social-$action-completed-title'),
      messageKey: Key('social-$action-completed-message'),
      confirmKey: Key('social-$action-completed-confirm'),
    );
  } catch (error) {
    if (!context.mounted) return;
    final text = error is PostgrestException ? error.message : error.toString();
    final message = text.contains('daily poke')
        ? '오늘 찌르기는 3번까지 보낼 수 있어요.'
        : text.contains('daily boast')
        ? '오늘 자랑하기는 3번까지 보낼 수 있어요.'
        : text.contains('daily social')
        ? '오늘 보낼 수 있는 알림을 다 사용했어요.'
        : text.contains('cooldown')
        ? '자랑하기는 6시간 후에 다시 보낼 수 있어요.'
        : text.contains('rank is not available')
        ? '오늘의 도전 기록이 있어야 자랑할 수 있어요.'
        : '요청을 처리하지 못했어요.';
    await showPixelCompletionDialog(
      context,
      title: '$actionLabel 안내',
      message: message,
      dialogKey: Key('social-$action-error'),
      titleKey: Key('social-$action-error-title'),
      messageKey: Key('social-$action-error-message'),
      confirmKey: Key('social-$action-error-confirm'),
    );
  }
}

class _DailyNonplayersSheet extends ConsumerStatefulWidget {
  const _DailyNonplayersSheet({
    required this.playDate,
    required this.gameId,
    required this.canBoast,
  });

  final DateTime playDate;
  final String gameId;
  final bool canBoast;

  @override
  ConsumerState<_DailyNonplayersSheet> createState() =>
      _DailyNonplayersSheetState();
}

class _DailyNonplayersSheetState extends ConsumerState<_DailyNonplayersSheet> {
  final _players = <DailyNonplayer>[];
  var _initialLoading = true;
  var _initialRequestStarted = false;
  var _loadingMore = false;
  String? _nextCursor;
  Object? _initialError;
  Object? _loadMoreError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadInitial());
    });
  }

  Future<void> _loadInitial() async {
    if (_initialRequestStarted && _initialLoading) return;
    setState(() {
      _initialRequestStarted = true;
      _initialLoading = true;
      _initialError = null;
      _loadMoreError = null;
      _players.clear();
      _nextCursor = null;
    });
    try {
      final page = await ref
          .read(dailyNonplayersRepositoryProvider)
          .fetchDailyNonplayers(
            playDate: widget.playDate,
            gameId: widget.gameId,
          );
      if (!mounted) return;
      setState(() {
        _appendVisiblePlayers(page.players);
        _nextCursor = page.nextCursor;
        _initialLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _initialError = error;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore || _initialLoading) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await ref
          .read(dailyNonplayersRepositoryProvider)
          .fetchDailyNonplayers(
            playDate: widget.playDate,
            gameId: widget.gameId,
            afterUserId: cursor,
          );
      if (!mounted) return;
      setState(() {
        _appendVisiblePlayers(page.players);
        _nextCursor = page.nextCursor == cursor ? null : page.nextCursor;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = error;
      });
    }
  }

  void _appendVisiblePlayers(Iterable<DailyNonplayer> players) {
    final knownIds = _players.map((player) => player.userId).toSet();
    for (final player in players) {
      final nickname = player.nickname.trim();
      if (nickname.isEmpty || _isGeneratedNickname(nickname)) continue;
      if (!knownIds.add(player.userId)) continue;
      _players.add(player);
    }
  }

  bool _isGeneratedNickname(String nickname) =>
      RegExp(r'^신원미상#[0-9]+$').hasMatch(nickname);

  @override
  Widget build(BuildContext context) => _SheetFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader(
          eyebrow: 'PLAYERS TO MEET',
          title: '아직 플레이하지 않은 유저',
          onClose: () => Navigator.of(context).pop(),
          closeKey: const Key('daily-nonplayers-close'),
        ),
        const SizedBox(height: 8),
        const WordSafeText(
          '이 게임을 아직 시작하지 않은 유저예요.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildContent()),
      ],
    ),
  );

  Widget _buildContent() {
    if (_initialLoading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('daily-nonplayers-loading')),
      );
    }
    if (_initialError != null && _players.isEmpty) {
      return _NonplayersMessage(
        key: const Key('daily-nonplayers-error'),
        message: '유저 목록을 불러오지 못했어요.',
        actionLabel: '다시 시도',
        onPressed: _loadInitial,
      );
    }
    if (_players.isEmpty && _nextCursor == null) {
      return const _NonplayersMessage(
        key: Key('daily-nonplayers-empty'),
        message: '아직 플레이하지 않은 유저가 없어요.',
      );
    }

    final footerCount = _nextCursor == null ? 0 : 1;
    return ListView.separated(
      key: const Key('daily-nonplayers-list'),
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _players.length + footerCount,
      separatorBuilder: (_, index) => index < _players.length - 1
          ? const SizedBox(height: 6)
          : const SizedBox.shrink(),
      itemBuilder: (context, index) {
        if (index < _players.length) {
          final player = _players[index];
          return _DailyNonplayerRow(
            player: player,
            onAction: () => unawaited(
              _showRankActionsForTarget(
                context,
                ref,
                targetUserId: player.userId,
                nickname: player.nickname.trim(),
                canBoast: widget.canBoast,
                allowDuel: false,
              ),
            ),
          );
        }
        return _buildFooter();
      },
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: CircularProgressIndicator(
            key: Key('daily-nonplayers-more-loading'),
          ),
        ),
      );
    }
    if (_loadMoreError != null) {
      return OutlinedButton(
        key: const Key('daily-nonplayers-more-retry'),
        onPressed: _loadMore,
        child: const WordSafeText('목록 더 불러오기 다시 시도'),
      );
    }
    return OutlinedButton(
      key: const Key('daily-nonplayers-more-button'),
      onPressed: _loadMore,
      child: const WordSafeText('더 보기'),
    );
  }
}

class _NonplayersMessage extends StatelessWidget {
  const _NonplayersMessage({
    required this.message,
    this.actionLabel,
    this.onPressed,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WordSafeText(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (actionLabel != null && onPressed != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('daily-nonplayers-retry'),
            onPressed: onPressed,
            child: WordSafeText(actionLabel!),
          ),
        ],
      ],
    ),
  );
}

class _DailyNonplayerRow extends StatelessWidget {
  const _DailyNonplayerRow({required this.player, required this.onAction});

  final DailyNonplayer player;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('daily-nonplayer-${player.userId}'),
    constraints: const BoxConstraints(minHeight: 68),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.backgroundDeep,
      border: Border.all(color: AppColors.surfaceLight),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 44,
          child: WordSafeText(
            'LV.${player.level}',
            singleLine: true,
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontFamily: 'Galmuri',
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: WordSafeText(
            player.nickname.trim(),
            style: TextStyle(
              color: NicknameColors.forLevel(player.level),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          key: Key('daily-nonplayer-more-${player.userId}'),
          tooltip: '상호작용',
          onPressed: onAction,
          icon: const Icon(Icons.more_horiz, color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class _PreviousWinnerCard extends StatelessWidget {
  const _PreviousWinnerCard({required this.gameId, required this.result});

  final String gameId;
  final DailyRankResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('previous-winner-card'),
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.backgroundDeep,
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: _previousWinnerContent(result),
    );
  }

  Widget _previousWinnerContent(DailyRankResult rankResult) {
    NearbyRank? winner;
    for (final entry in rankResult.leaders) {
      if (entry.rank == 1) {
        winner = entry;
        break;
      }
    }
    if (winner == null) {
      return const WordSafeText(
        '지난 1등 기록이 없어요.',
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Row(
      children: [
        const SizedBox(
          width: 42,
          child: Icon(
            Icons.emoji_events_outlined,
            key: Key('previous-winner-trophy'),
            color: AppColors.primary,
            size: 22,
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: WordSafeText(
                  'LV.${winner.level}',
                  singleLine: true,
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontFamily: 'Galmuri',
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: WordSafeText(
                  winner.nickname,
                  style: TextStyle(
                    color: NicknameColors.forLevel(winner.level),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        WordSafeText(
          GameRegistry.formatScore(gameId, winner.score),
          style: const TextStyle(
            fontFamily: 'Galmuri',
            color: AppColors.reward,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RankingSectionTitle extends StatelessWidget {
  const _RankingSectionTitle({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: WordSafeText(
          title,
          style: const TextStyle(
            fontFamily: 'Galmuri',
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      WordSafeText(
        eyebrow,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    ],
  );
}

class _RankActionSheet extends StatelessWidget {
  const _RankActionSheet({
    required this.userId,
    required this.nickname,
    required this.canBoast,
    required this.allowDuel,
  });

  final String userId;
  final String nickname;
  final bool canBoast;
  final bool allowDuel;

  @override
  Widget build(BuildContext context) => _RankSheetSurface(
    key: Key('rank-actions-$userId'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader(
          eyebrow: 'RANKING PLAYER',
          title: nickname,
          onClose: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 8),
        const WordSafeText(
          '오늘의 랭킹에서 가볍게 인사를 보내요.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (allowDuel) ...[
          _RankActionTile(
            key: const Key('rank-action-duel'),
            icon: Icons.sports_esports_outlined,
            title: '1:1 대결 신청',
            subtitle: '게임과 코인을 골라 대결해요',
            onTap: () => Navigator.of(context).pop('duel'),
          ),
          const SizedBox(height: 7),
        ],
        _RankActionTile(
          key: const Key('rank-action-poke'),
          icon: Icons.touch_app_outlined,
          title: '찌르기',
          subtitle: '가볍게 존재감을 알려요',
          onTap: () => Navigator.of(context).pop('poke'),
        ),
        const SizedBox(height: 7),
        _RankActionTile(
          key: const Key('rank-action-boast'),
          icon: Icons.campaign_outlined,
          title: '자랑하기',
          subtitle: canBoast ? '내 오늘 기록을 알려요' : '오늘 기록을 남긴 뒤 사용할 수 있어요',
          enabled: canBoast,
          onTap: canBoast ? () => Navigator.of(context).pop('boast') : null,
        ),
        const SizedBox(height: 7),
        _RankActionTile(
          key: const Key('rank-action-gift'),
          icon: Icons.card_giftcard_outlined,
          title: '선물하기',
          subtitle: '보유한 아이템을 하나 보내요',
          onTap: () => Navigator.of(context).pop('gift'),
        ),
      ],
    ),
  );
}

class _RankGiftSheet extends StatelessWidget {
  const _RankGiftSheet({
    required this.nickname,
    required this.practiceTickets,
    required this.challengeTickets,
    required this.nicknameChangeTickets,
  });

  final String nickname;
  final int practiceTickets;
  final int challengeTickets;
  final int nicknameChangeTickets;

  @override
  Widget build(BuildContext context) => _RankSheetSurface(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader(
          eyebrow: 'SEND A GIFT',
          title: '$nickname님에게 선물',
          onClose: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 12),
        _RankActionTile(
          icon: Icons.confirmation_number_outlined,
          title: '연습권 1장',
          subtitle: '보유 $practiceTickets장',
          enabled: practiceTickets > 0,
          onTap: () => Navigator.of(context).pop('practice_ticket'),
        ),
        const SizedBox(height: 7),
        _RankActionTile(
          icon: Icons.sports_score_outlined,
          title: '도전권 1장',
          subtitle: '보유 $challengeTickets장',
          enabled: challengeTickets > 0,
          onTap: () => Navigator.of(context).pop('challenge_ticket'),
        ),
        const SizedBox(height: 7),
        _RankActionTile(
          icon: Icons.edit_outlined,
          title: '닉네임 변경권 1장',
          subtitle: '보유 $nicknameChangeTickets장',
          enabled: nicknameChangeTickets > 0,
          onTap: () => Navigator.of(context).pop('nickname_change_ticket'),
        ),
      ],
    ),
  );
}

class _RankSheetSurface extends StatelessWidget {
  const _RankSheetSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.border, width: 2)),
    ),
    child: SafeArea(top: false, child: child),
  );
}

class _RankActionTile extends StatelessWidget {
  const _RankActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.text : AppColors.textMuted;
    return Material(
      color: AppColors.backgroundDeep,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.surfaceLight),
          ),
          child: Row(
            children: [
              Icon(icon, color: enabled ? AppColors.primary : color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WordSafeText(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    WordSafeText(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: enabled ? AppColors.textMuted : AppColors.surfaceLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.entry,
    required this.gameId,
    this.onAction,
  });

  final NearbyRank entry;
  final String? gameId;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final accent = switch (entry.rank) {
      1 => AppColors.primary,
      2 => AppColors.border,
      3 => AppColors.primaryShadow,
      _ => AppColors.textMuted,
    };
    return Container(
      key: entry.isMe ? const Key('my-leaderboard-rank') : null,
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: entry.isMe
            ? AppColors.primary.withValues(alpha: 0.16)
            : AppColors.backgroundDeep,
        border: Border.all(
          color: entry.isMe ? AppColors.primary : AppColors.surfaceLight,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: WordSafeText(
              '${entry.rank}',
              style: TextStyle(
                fontFamily: 'Galmuri',
                color: accent,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  key: Key('leaderboard-level-${entry.rank}'),
                  width: 34,
                  child: WordSafeText(
                    'LV.${entry.level}',
                    singleLine: true,
                    maxLines: 1,
                    style: TextStyle(
                      color: entry.isMe
                          ? AppColors.primary
                          : AppColors.textMuted,
                      fontFamily: 'Galmuri',
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: WordSafeText(
                    entry.nickname,
                    style: TextStyle(
                      color: NicknameColors.forLevel(entry.level),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          WordSafeText(
            GameRegistry.formatScore(gameId, entry.score),
            style: const TextStyle(
              fontFamily: 'Galmuri',
              color: AppColors.reward,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(
            width: 48,
            child: entry.isMe
                ? Center(
                    child: Container(
                      key: const Key('my-rank-badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      color: AppColors.primary,
                      child: const WordSafeText(
                        '나',
                        style: TextStyle(
                          color: AppColors.backgroundDeep,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                : !entry.isNpc && entry.userId != null
                ? IconButton(
                    key: Key('rank-more-${entry.userId}'),
                    tooltip: '상호작용',
                    onPressed: onAction,
                    icon: const Icon(
                      Icons.more_horiz,
                      color: AppColors.textMuted,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _GameGuideSheet extends StatefulWidget {
  const _GameGuideSheet({required this.game});

  final TodayGame? game;

  @override
  State<_GameGuideSheet> createState() => _GameGuideSheetState();
}

class _GameGuideSheetState extends State<_GameGuideSheet> {
  late final PageController _pageController;
  var _pageIndex = 0;

  List<GameGuidePageDefinition> get _pages =>
      GamePresentationRegistry.forId(widget.game?.id).guidePages;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_pageIndex == _pages.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader(
            eyebrow: 'HOW TO PLAY · ${_pageIndex + 1}/${pages.length}',
            title: '게임 설명',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PageView.builder(
              key: const Key('game-guide-pages'),
              controller: _pageController,
              itemCount: pages.length,
              onPageChanged: (value) => setState(() => _pageIndex = value),
              itemBuilder: (context, index) =>
                  _GuidePage(index: index, page: pages[index]),
            ),
          ),
          const SizedBox(height: 12),
          if (pages.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < pages.length; index++)
                  AnimatedContainer(
                    key: Key('guide-page-dot-$index'),
                    duration: const Duration(milliseconds: 180),
                    width: index == _pageIndex ? 22 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    color: index == _pageIndex
                        ? AppColors.primary
                        : AppColors.surfaceLight,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    key: const Key('guide-previous-button'),
                    onPressed: _pageIndex == 0
                        ? null
                        : () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                          ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: AppColors.text,
                      disabledForegroundColor: AppColors.textMuted,
                      side: BorderSide(
                        color: _pageIndex == 0
                            ? AppColors.surfaceLight
                            : AppColors.border,
                        width: 2,
                      ),
                      shape: const RoundedRectangleBorder(),
                      textStyle: const TextStyle(
                        fontFamily: 'Galmuri',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const WordSafeText('이전'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PixelButton(
                  key: const Key('guide-next-button'),
                  label: _pageIndex == pages.length - 1 ? '설명 끝' : '다음',
                  icon: _pageIndex == pages.length - 1
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({required this.index, required this.page});

  final int index;
  final GameGuidePageDefinition page;

  bool get _usesPortraitGameplay => switch (page.visual) {
    GameGuideVisualKind.bathhouseControls ||
    GameGuideVisualKind.bathhouseQueue ||
    GameGuideVisualKind.bathhouseUnlock ||
    GameGuideVisualKind.bathhouseScoring ||
    GameGuideVisualKind.lilyOrbit ||
    GameGuideVisualKind.lilyTangent ||
    GameGuideVisualKind.lilySpeed ||
    GameGuideVisualKind.lilyScoring ||
    GameGuideVisualKind.lilyBonus ||
    GameGuideVisualKind.lilyFailure => true,
    GameGuideVisualKind.netBoatTurn ||
    GameGuideVisualKind.netBoatClose ||
    GameGuideVisualKind.netBoatScore ||
    GameGuideVisualKind.netBoatDifficulty ||
    GameGuideVisualKind.netBoatFailure ||
    GameGuideVisualKind.netBoatLimit ||
    GameGuideVisualKind.moleReaction => true,
    GameGuideVisualKind.westernWait ||
    GameGuideVisualKind.westernDraw ||
    GameGuideVisualKind.westernResult ||
    GameGuideVisualKind.windDartsHold ||
    GameGuideVisualKind.windDartsWind ||
    GameGuideVisualKind.windDartsDistance ||
    GameGuideVisualKind.windDartsScoring => true,
    GameGuideVisualKind.templeRunControls ||
    GameGuideVisualKind.templeRunHazards ||
    GameGuideVisualKind.templeRunManeuvers ||
    GameGuideVisualKind.templeRunCorner ||
    GameGuideVisualKind.templeRunItems ||
    GameGuideVisualKind.templeRunScore => true,
    _ => false,
  };

  bool get _isWindDartsVisual => switch (page.visual) {
    GameGuideVisualKind.windDartsHold ||
    GameGuideVisualKind.windDartsWind ||
    GameGuideVisualKind.windDartsDistance ||
    GameGuideVisualKind.windDartsScoring => true,
    _ => false,
  };

  bool get _isWesternDuelVisual => switch (page.visual) {
    GameGuideVisualKind.westernWait ||
    GameGuideVisualKind.westernDraw ||
    GameGuideVisualKind.westernResult => true,
    _ => false,
  };

  double _visualHeight(BuildContext context) {
    if (!_usesPortraitGameplay) return 268;
    if (_isWesternDuelVisual && MediaQuery.sizeOf(context).height <= 700) {
      return 300;
    }
    if (_isWindDartsVisual && MediaQuery.sizeOf(context).height <= 700) {
      return 240;
    }
    return 360;
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _visualHeight(context),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.backgroundDeep,
              border: Border.all(color: AppColors.surfaceLight, width: 2),
            ),
            child: ClipRect(
              child: _GuideVisual(kind: page.visual, pageIndex: index),
            ),
          ),
        ),
        const SizedBox(height: 16),
        WordSafeText(
          '${index + 1}'.padLeft(2, '0'),
          style: const TextStyle(
            color: AppColors.primary,
            fontFamily: 'Galmuri',
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        WordSafeText(
          page.title,
          style: const TextStyle(
            color: AppColors.text,
            fontFamily: 'Galmuri',
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        WordSafeText(
          page.description,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
        ),
        if (page.detail.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.primary.withValues(alpha: 0.1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WordSafeText(
                    page.detail,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _GuideVisual extends StatelessWidget {
  const _GuideVisual({required this.kind, this.pageIndex = 0});

  final GameGuideVisualKind kind;
  final int pageIndex;

  @override
  Widget build(BuildContext context) => switch (kind) {
    GameGuideVisualKind.dungSwipe => const _SwipeGuideVisual(),
    GameGuideVisualKind.dungGameplay => const _GameplayGuideVisual(),
    GameGuideVisualKind.dungDifficulty => const _DifficultyGuideVisual(),
    GameGuideVisualKind.dungCollision => const _CollisionGuideVisual(),
    GameGuideVisualKind.dungSurvival => const _SurvivalGuideVisual(),
    GameGuideVisualKind.appleDrag => const _AppleDragGuideVisual(),
    GameGuideVisualKind.appleTarget => const _AppleTargetGuideVisual(),
    GameGuideVisualKind.appleSparseRectangle =>
      const _AppleSparseRectangleGuideVisual(),
    GameGuideVisualKind.appleScoring => const _AppleScoringGuideVisual(),
    GameGuideVisualKind.appleResult => const _AppleResultGuideVisual(),
    GameGuideVisualKind.gravityControl => const _GravityControlGuideVisual(),
    GameGuideVisualKind.gravityLanding => const _GravityLandingGuideVisual(),
    GameGuideVisualKind.gravityObstacle => const _GravityObstacleGuideVisual(),
    GameGuideVisualKind.gravityDifficulty =>
      const _GravityDifficultyGuideVisual(),
    GameGuideVisualKind.gravitySurvival => const _GravitySurvivalGuideVisual(),
    GameGuideVisualKind.numberSequence => const _NumberSequenceGuideVisual(),
    GameGuideVisualKind.numberNext => const _NumberNextGuideVisual(),
    GameGuideVisualKind.numberRefill => const _NumberRefillGuideVisual(),
    GameGuideVisualKind.numberMistake => const _NumberMistakeGuideVisual(),
    GameGuideVisualKind.numberResult => const _NumberResultGuideVisual(),
    GameGuideVisualKind.mamaObserve => const _MamaDuckGuideVisual(
      assetName: 'guide_observe.png',
    ),
    GameGuideVisualKind.mamaRecall => const _MamaDuckGuideVisual(
      assetName: 'guide_recall.png',
    ),
    GameGuideVisualKind.mamaFailure => const _MamaDuckGuideVisual(
      assetName: 'guide_failure.png',
    ),
    GameGuideVisualKind.snakeButtons => const _MidnightSnakeVisual(
      scene: _SnakePreviewScene.buttons,
    ),
    GameGuideVisualKind.snakeQueue => const _MidnightSnakeVisual(
      scene: _SnakePreviewScene.queue,
    ),
    GameGuideVisualKind.snakeGrow => const _MidnightSnakeVisual(
      scene: _SnakePreviewScene.grow,
    ),
    GameGuideVisualKind.snakeCollision => const _MidnightSnakeVisual(
      scene: _SnakePreviewScene.collision,
    ),
    GameGuideVisualKind.sausageSwipe => const _MidnightSnakeVisual(
      scene: _SnakePreviewScene.buttons,
    ),
    GameGuideVisualKind.sausageGrow => const _MidnightSnakeVisual(
      scene: _SnakePreviewScene.grow,
    ),
    GameGuideVisualKind.sausageCollision => const _MidnightSnakeVisual(
      scene: _SnakePreviewScene.collision,
    ),
    GameGuideVisualKind.dealerGoal => const _BeatTheDealerVisual(
      scene: _DealerPreviewScene.goal,
    ),
    GameGuideVisualKind.dealerBet => const _BeatTheDealerVisual(
      scene: _DealerPreviewScene.bet,
    ),
    GameGuideVisualKind.dealerChoice => const _BeatTheDealerVisual(
      scene: _DealerPreviewScene.choice,
    ),
    GameGuideVisualKind.dealerResult => const _BeatTheDealerVisual(
      scene: _DealerPreviewScene.result,
    ),
    GameGuideVisualKind.sluggerTap => const TenPitchSluggerPreview(
      scene: TenPitchSluggerPreviewScene.tap,
      animate: false,
    ),
    GameGuideVisualKind.sluggerTiming => const TenPitchSluggerPreview(
      scene: TenPitchSluggerPreviewScene.timing,
      animate: false,
    ),
    GameGuideVisualKind.sluggerDistance => const TenPitchSluggerPreview(
      scene: TenPitchSluggerPreviewScene.distance,
      animate: false,
    ),
    GameGuideVisualKind.sluggerMagic => const TenPitchSluggerPreview(
      scene: TenPitchSluggerPreviewScene.magic,
      animate: false,
    ),
    GameGuideVisualKind.sluggerScore => const TenPitchSluggerPreview(
      scene: TenPitchSluggerPreviewScene.score,
      animate: false,
    ),
    GameGuideVisualKind.ramenCalibration => const RamenTimerPreview(
      scene: RamenTimerPreviewScene.calibration,
      animate: false,
    ),
    GameGuideVisualKind.ramenCheckpoints => const RamenTimerPreview(
      scene: RamenTimerPreviewScene.checkpoints,
      animate: false,
    ),
    GameGuideVisualKind.ramenResult => const RamenTimerPreview(
      scene: RamenTimerPreviewScene.result,
      animate: false,
    ),
    GameGuideVisualKind.bathhouseControls => const BathhouseSortPreview(
      scene: BathhouseSortPreviewScene.controls,
    ),
    GameGuideVisualKind.bathhouseQueue => const BathhouseSortPreview(
      scene: BathhouseSortPreviewScene.queue,
      animate: false,
    ),
    GameGuideVisualKind.bathhouseUnlock => const BathhouseSortPreview(
      scene: BathhouseSortPreviewScene.unlock,
      animate: false,
    ),
    GameGuideVisualKind.bathhouseScoring => const BathhouseSortPreview(
      scene: BathhouseSortPreviewScene.scoring,
    ),
    GameGuideVisualKind.lilyOrbit => const LilyFrogRuntimePreview(
      mode: LilyFrogRuntimePreviewMode.orbit,
    ),
    GameGuideVisualKind.lilyTangent => const LilyFrogRuntimePreview(
      mode: LilyFrogRuntimePreviewMode.tangent,
    ),
    GameGuideVisualKind.lilySpeed => const LilyFrogRuntimePreview(
      mode: LilyFrogRuntimePreviewMode.speed,
    ),
    GameGuideVisualKind.lilyScoring => const LilyFrogRuntimePreview(
      mode: LilyFrogRuntimePreviewMode.scoring,
    ),
    GameGuideVisualKind.lilyBonus => const LilyFrogRuntimePreview(
      mode: LilyFrogRuntimePreviewMode.bonus,
    ),
    GameGuideVisualKind.lilyFailure => const LilyFrogRuntimePreview(
      mode: LilyFrogRuntimePreviewMode.failure,
    ),
    GameGuideVisualKind.netBoatTurn => const NetBoatPreview(
      scene: NetBoatPreviewScene.turn,
      animate: true,
    ),
    GameGuideVisualKind.netBoatClose => const NetBoatPreview(
      scene: NetBoatPreviewScene.close,
      animate: false,
    ),
    GameGuideVisualKind.netBoatScore => const NetBoatPreview(
      scene: NetBoatPreviewScene.score,
      animate: false,
    ),
    GameGuideVisualKind.netBoatDifficulty => const NetBoatPreview(
      scene: NetBoatPreviewScene.difficulty,
      animate: false,
    ),
    GameGuideVisualKind.netBoatFailure => const NetBoatPreview(
      scene: NetBoatPreviewScene.failure,
      animate: false,
    ),
    GameGuideVisualKind.netBoatLimit => const NetBoatPreview(
      scene: NetBoatPreviewScene.limit,
      animate: false,
    ),
    GameGuideVisualKind.moleReaction => MoleReactionPreview(
      scene: switch (pageIndex) {
        0 => MoleReactionPreviewScene.practice,
        1 => MoleReactionPreviewScene.golden,
        _ => MoleReactionPreviewScene.score,
      },
    ),
    GameGuideVisualKind.westernWait => const WesternDuelPreview(
      scene: WesternDuelPreviewScene.wait,
      animate: false,
    ),
    GameGuideVisualKind.westernDraw => const WesternDuelPreview(
      scene: WesternDuelPreviewScene.draw,
      animate: false,
    ),
    GameGuideVisualKind.westernResult => const WesternDuelPreview(
      scene: WesternDuelPreviewScene.result,
      animate: false,
    ),
    GameGuideVisualKind.windDartsHold => const WindDartsPreview(
      scene: WindDartsPreviewScene.controls,
      animate: false,
    ),
    GameGuideVisualKind.windDartsWind => const WindDartsPreview(
      scene: WindDartsPreviewScene.wind,
      animate: false,
    ),
    GameGuideVisualKind.windDartsDistance => const WindDartsPreview(
      scene: WindDartsPreviewScene.distance,
      animate: false,
    ),
    GameGuideVisualKind.windDartsScoring => const WindDartsPreview(
      scene: WindDartsPreviewScene.scoring,
      animate: false,
    ),
    GameGuideVisualKind.templeRunControls => const TempleRunPreview(
      scene: TempleRunPreviewScene.controls,
      animate: false,
    ),
    GameGuideVisualKind.templeRunHazards => const TempleRunPreview(
      scene: TempleRunPreviewScene.hazards,
      animate: false,
    ),
    GameGuideVisualKind.templeRunManeuvers => const TempleRunPreview(
      scene: TempleRunPreviewScene.maneuvers,
      animate: false,
    ),
    GameGuideVisualKind.templeRunCorner => const TempleRunPreview(
      scene: TempleRunPreviewScene.corner,
      animate: false,
      initialFrame: 55,
    ),
    GameGuideVisualKind.templeRunItems => const TempleRunPreview(
      scene: TempleRunPreviewScene.items,
      animate: false,
    ),
    GameGuideVisualKind.templeRunScore => const TempleRunPreview(
      scene: TempleRunPreviewScene.score,
      animate: false,
    ),
  };
}

enum _DealerPreviewScene { home, goal, bet, choice, result }

class _BeatTheDealerVisual extends StatefulWidget {
  const _BeatTheDealerVisual({required this.scene});

  final _DealerPreviewScene scene;

  @override
  State<_BeatTheDealerVisual> createState() => _BeatTheDealerVisualState();
}

class _BeatTheDealerVisualState extends State<_BeatTheDealerVisual> {
  static const _homeAnimationTick = Duration(milliseconds: 100);
  static const _homeAnimationFrameCount = 75; // 7.5 seconds per loop.

  Timer? _timer;
  var _frame = 0;

  @override
  void initState() {
    super.initState();
    if (widget.scene == _DealerPreviewScene.home) {
      _timer = Timer.periodic(_homeAnimationTick, (_) {
        if (mounted) {
          setState(() => _frame = (_frame + 1) % _homeAnimationFrameCount);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.scene;
    final homeStage = _frame < 25
        ? _DealerPreviewScene.bet
        : _frame < 53
        ? _DealerPreviewScene.choice
        : _DealerPreviewScene.result;
    final visibleScene = scene == _DealerPreviewScene.home ? homeStage : scene;
    final spriteFrame = (_frame ~/ 2) % 4;
    final dealerCards = switch (visibleScene) {
      _DealerPreviewScene.choice => const [('6', '♥'), (null, null)],
      _DealerPreviewScene.result => const [('6', '♥'), ('Q', '♣'), ('2', '♦')],
      _ => const [('6', '♥'), (null, null)],
    };
    final playerCards = switch (visibleScene) {
      _DealerPreviewScene.goal => const [('A', '♠'), ('K', '♥')],
      _DealerPreviewScene.choice => const [('K', '♠'), ('6', '♦')],
      _DealerPreviewScene.result => const [('K', '♠'), ('Q', '♥')],
      _ => const <(String, String)>[],
    };
    final coins = visibleScene == _DealerPreviewScene.result ? 120 : 100;
    final status = switch (visibleScene) {
      _DealerPreviewScene.goal => 'A + K = 블랙잭!',
      _DealerPreviewScene.bet => '얼마를 걸까?',
      _DealerPreviewScene.choice => '한 장 더 받을까?',
      _DealerPreviewScene.result => '승리!  +20',
      _DealerPreviewScene.home => '',
    };

    return ColoredBox(
      key: Key(
        scene == _DealerPreviewScene.home
            ? 'beat-dealer-home-animation'
            : 'beat-dealer-guide-${scene.name}',
      ),
      color: const Color(0xFF120F25),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 360,
          height: 460,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              const Positioned.fill(
                child: Image(
                  image: AssetImage(
                    'assets/images/beat_the_dealer/background_map_v3.png',
                  ),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none,
                ),
              ),
              Positioned(
                left: 124,
                top: 4,
                width: 112,
                height: 112,
                child: _BeatTheDealerSpriteFrame(
                  asset:
                      'assets/images/beat_the_dealer/dealer_idle_sheet_v3.png',
                  frame: spriteFrame,
                  frameSize: 64,
                  scale: 1.75,
                ),
              ),
              Positioned(
                left: 18,
                top: 24,
                child: _DealerPreviewPanel(
                  child: Row(
                    children: [
                      const Image(
                        image: AssetImage(
                          'assets/images/beat_the_dealer/coin_v3.png',
                        ),
                        width: 28,
                        height: 28,
                        filterQuality: FilterQuality.none,
                      ),
                      const SizedBox(width: 5),
                      WordSafeText(
                        '$coins',
                        key: const Key('beat-dealer-preview-coins'),
                        style: const TextStyle(
                          color: Color(0xFFFFE66D),
                          fontFamily: 'Galmuri',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 104,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (
                      var index = 0;
                      index < dealerCards.length;
                      index++
                    ) ...[
                      _DealerPreviewCard(
                        rank: dealerCards[index].$1,
                        suit: dealerCards[index].$2,
                      ),
                      if (index != dealerCards.length - 1)
                        const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 214,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (
                      var index = 0;
                      index < playerCards.length;
                      index++
                    ) ...[
                      _DealerPreviewCard(
                        rank: playerCards[index].$1,
                        suit: playerCards[index].$2,
                      ),
                      if (index != playerCards.length - 1)
                        const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 28,
                right: 28,
                top: 307,
                child: WordSafeText(
                  status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFE66D),
                    fontFamily: 'Galmuri',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (visibleScene == _DealerPreviewScene.bet)
                const Positioned(
                  left: 42,
                  right: 42,
                  bottom: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _DealerPreviewButton(label: '- 5'),
                      _DealerPreviewButton(label: '배팅 5'),
                      _DealerPreviewButton(label: '+ 5'),
                    ],
                  ),
                ),
              if (visibleScene == _DealerPreviewScene.choice)
                const Positioned(
                  left: 42,
                  right: 42,
                  bottom: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _DealerPreviewButton(label: '한 장 더', wide: true),
                      _DealerPreviewButton(label: '멈추기', wide: true),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BeatTheDealerSpriteFrame extends StatelessWidget {
  const _BeatTheDealerSpriteFrame({
    required this.asset,
    required this.frame,
    required this.frameSize,
    required this.scale,
  });

  static const _columns = 2;
  static const _rows = 2;

  final String asset;
  final int frame;
  final double frameSize;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final frameWidth = frameSize * scale;
    final sheetWidth = frameWidth * _columns;
    final sheetHeight = frameWidth * _rows;
    final column = frame % _columns;
    final row = (frame ~/ _columns) % _rows;

    return SizedBox(
      width: frameWidth,
      height: frameWidth,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: sheetWidth,
          maxWidth: sheetWidth,
          minHeight: sheetHeight,
          maxHeight: sheetHeight,
          child: Transform.translate(
            offset: Offset(-column * frameWidth, -row * frameWidth),
            transformHitTests: false,
            child: Image.asset(
              asset,
              width: sheetWidth,
              height: sheetHeight,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _DealerPreviewPanel extends StatelessWidget {
  const _DealerPreviewPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xE6231839),
      border: Border.all(color: const Color(0xFF9D78C8), width: 2),
    ),
    child: child,
  );
}

class _DealerPreviewCard extends StatelessWidget {
  const _DealerPreviewCard({required this.rank, required this.suit});

  final String? rank;
  final String? suit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 58,
    height: 78,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: AssetImage(
            rank == null
                ? 'assets/images/beat_the_dealer/card_back_v3.png'
                : 'assets/images/beat_the_dealer/card_front_v3.png',
          ),
          fit: BoxFit.fill,
          filterQuality: FilterQuality.none,
        ),
        if (rank != null) ...[
          Positioned(
            left: 6,
            top: 5,
            child: WordSafeText(
              '$rank\n$suit',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: suit == '♥' || suit == '♦'
                    ? const Color(0xFFC93948)
                    : const Color(0xFF282035),
                fontFamily: 'Galmuri',
                fontSize: 13,
                height: 0.9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Center(
            child: WordSafeText(
              suit!,
              style: TextStyle(
                color: suit == '♥' || suit == '♦'
                    ? const Color(0xFFC93948)
                    : const Color(0xFF282035),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 5,
            child: RotatedBox(
              quarterTurns: 2,
              child: WordSafeText(
                '$rank\n$suit',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: suit == '♥' || suit == '♦'
                      ? const Color(0xFFC93948)
                      : const Color(0xFF282035),
                  fontFamily: 'Galmuri',
                  fontSize: 13,
                  height: 0.9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _DealerPreviewButton extends StatelessWidget {
  const _DealerPreviewButton({required this.label, this.wide = false});

  final String label;
  final bool wide;

  @override
  Widget build(BuildContext context) => Container(
    width: wide ? 126 : 82,
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: BoxDecoration(
      color: const Color(0xFF4A2F68),
      border: Border.all(color: const Color(0xFFD4B7F0), width: 2),
    ),
    child: WordSafeText(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontFamily: 'Galmuri',
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MamaDuckGuideVisual extends StatelessWidget {
  const _MamaDuckGuideVisual({required this.assetName});

  final String assetName;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF172D38),
    child: Image.asset(
      'assets/images/mama_duck_trail/$assetName',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
    ),
  );
}

enum _SnakePreviewScene { home, buttons, queue, grow, collision }

class _MidnightSnakeVisual extends StatefulWidget {
  const _MidnightSnakeVisual({required this.scene});

  final _SnakePreviewScene scene;

  @override
  State<_MidnightSnakeVisual> createState() => _MidnightSnakeVisualState();
}

class _MidnightSnakeVisualState extends State<_MidnightSnakeVisual> {
  static const _tick = Duration(milliseconds: 50);

  Timer? _timer;
  ui.Image? _pattern;
  var _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) {
        setState(() => _elapsed += _tick);
      }
    });
    unawaited(_loadPattern());
  }

  Future<void> _loadPattern() async {
    final data = await rootBundle.load(
      'assets/images/midnight_snake/snake_scale_pattern.png',
    );
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _pattern = frame.image);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pattern?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _SnakePreviewFrame.at(_elapsed, scene: widget.scene);
    final isButtonScene = widget.scene == _SnakePreviewScene.buttons;
    final previewHeight = isButtonScene ? 680.0 : 640.0;
    final head = frame.pathPoints.first;
    final headLeft =
        _SnakePreviewFrame.boardLeft +
        (head.column + 0.5) * _SnakePreviewFrame.cellSize -
        16;
    final headTop =
        _SnakePreviewFrame.boardTop +
        (head.row + 0.5) * _SnakePreviewFrame.cellSize -
        16;
    final food = frame.food;
    final keyName = widget.scene == _SnakePreviewScene.home
        ? 'midnight-snake-home-animation'
        : 'midnight-snake-${widget.scene.name}-guide-animation';

    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      alignment: isButtonScene
          ? Alignment.bottomCenter
          : widget.scene == _SnakePreviewScene.grow &&
                frame.goldenSausage != null
          ? Alignment.topCenter
          : Alignment.center,
      child: SizedBox(
        key: Key(keyName),
        width: 360,
        height: previewHeight,
        child: Stack(
          children: [
            const Positioned(
              width: 360,
              height: 640,
              child: Image(
                image: AssetImage(
                  'assets/images/midnight_snake/apartment_background.png',
                ),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _SnakePreviewBody(frame: frame, pattern: _pattern),
              ),
            ),
            if (food != null)
              Positioned(
                left:
                    _SnakePreviewFrame.boardLeft +
                    food.column * _SnakePreviewFrame.cellSize,
                top:
                    _SnakePreviewFrame.boardTop +
                    food.row * _SnakePreviewFrame.cellSize,
                child: _SausageAtlasCell(
                  assetPath:
                      'assets/images/midnight_snake/midnight_food_atlas.png',
                  columns: 6,
                  rows: 2,
                  column: frame.foodType,
                  row: frame.foodFrame,
                  dimension: 32,
                ),
              ),
            if (frame.goldenSausage case final golden?)
              Positioned(
                left:
                    _SnakePreviewFrame.boardLeft +
                    golden.column * _SnakePreviewFrame.cellSize,
                top:
                    _SnakePreviewFrame.boardTop +
                    golden.row * _SnakePreviewFrame.cellSize,
                child: _SausageAtlasCell(
                  assetPath:
                      'assets/images/midnight_snake/golden_sausage_sheet.png',
                  columns: 1,
                  rows: 2,
                  column: 0,
                  row: frame.bonusFrame,
                  dimension: 32,
                ),
              ),
            if (frame.mouse case final mouse?)
              Positioned(
                left:
                    _SnakePreviewFrame.boardLeft +
                    mouse.column * _SnakePreviewFrame.cellSize,
                top:
                    _SnakePreviewFrame.boardTop +
                    mouse.row * _SnakePreviewFrame.cellSize,
                child: _SausageAtlasCell(
                  assetPath:
                      'assets/images/midnight_snake/mouse_walk_atlas.png',
                  columns: 2,
                  rows: 4,
                  column: frame.bonusFrame,
                  row: _headDirectionRow(frame.mouseDirection),
                  dimension: 32,
                ),
              ),
            Positioned(
              left: headLeft,
              top: headTop,
              child: _SausageAtlasCell(
                assetPath:
                    'assets/images/midnight_snake/snake_head_slither_atlas.png',
                columns: 4,
                rows: 4,
                column: frame.headFrame,
                row: _headDirectionRow(frame.direction),
                dimension: 32,
              ),
            ),
            if (widget.scene == _SnakePreviewScene.home)
              _SnakePreviewHud(frame: frame),
            if (widget.scene == _SnakePreviewScene.queue)
              _SnakeQueueOverlay(frame: frame),
            if (widget.scene == _SnakePreviewScene.grow)
              _SnakeGrowOverlay(frame: frame),
            if (widget.scene == _SnakePreviewScene.collision)
              _SnakeCollisionOverlay(frame: frame),
            if (frame.fadeOpacity > 0)
              Positioned.fill(
                child: ColoredBox(
                  color: Color.fromRGBO(3, 18, 28, frame.fadeOpacity),
                ),
              ),
            if (widget.scene == _SnakePreviewScene.buttons)
              const _SnakeButtonsOverlay(),
          ],
        ),
      ),
    );
  }

  static int _headDirectionRow(SnakeDirection direction) => switch (direction) {
    SnakeDirection.down => 0,
    SnakeDirection.left => 1,
    SnakeDirection.right => 2,
    SnakeDirection.up => 3,
  };
}

class _SnakePreviewFrame {
  const _SnakePreviewFrame({
    required this.pathPoints,
    required this.direction,
    required this.food,
    required this.foodType,
    required this.foodFrame,
    required this.goldenSausage,
    required this.mouse,
    required this.mouseDirection,
    required this.bonusFrame,
    required this.headFrame,
    required this.score,
    required this.remainingSeconds,
    required this.queuedDirections,
    required this.appliedTurns,
    required this.justAte,
    required this.collision,
    required this.fadeOpacity,
  });

  static const boardLeft = 36.0;
  static const boardTop = 112.0;
  static const cellSize = 32.0;
  static const cycleSeconds = 16.0;
  static const stepSeconds = 0.62;
  static const _initialHoldSeconds = 1.25;

  static const _headTrail = <SnakeCell>[
    SnakeCell(7, 1),
    SnakeCell(7, 2),
    SnakeCell(7, 3),
    SnakeCell(7, 4),
    SnakeCell(6, 4),
    SnakeCell(6, 5),
    SnakeCell(7, 5),
    SnakeCell(7, 6),
    SnakeCell(7, 7),
    SnakeCell(6, 7),
    SnakeCell(5, 7),
    SnakeCell(5, 8),
    SnakeCell(6, 8),
    SnakeCell(7, 8),
    SnakeCell(8, 8),
    SnakeCell(8, 7),
    SnakeCell(8, 6),
    SnakeCell(9, 6),
    SnakeCell(10, 6),
    SnakeCell(10, 5),
    SnakeCell(10, 4),
    SnakeCell(9, 4),
    SnakeCell(9, 5),
    SnakeCell(10, 5),
  ];

  final List<MidnightSnakePathPoint> pathPoints;
  final SnakeDirection direction;
  final SnakeCell? food;
  final int foodType;
  final int foodFrame;
  final SnakeCell? goldenSausage;
  final SnakeCell? mouse;
  final SnakeDirection mouseDirection;
  final int bonusFrame;
  final int headFrame;
  final int score;
  final int remainingSeconds;
  final List<SnakeDirection> queuedDirections;
  final int appliedTurns;
  final bool justAte;
  final bool collision;
  final double fadeOpacity;

  static _SnakePreviewFrame at(
    Duration elapsed, {
    required _SnakePreviewScene scene,
  }) {
    final sceneCycleSeconds = switch (scene) {
      _SnakePreviewScene.queue => 8.0,
      _SnakePreviewScene.collision => 10.0,
      _ => cycleSeconds,
    };
    final cycle = (elapsed.inMilliseconds / 1000) % sceneCycleSeconds;
    final scriptCycle = switch (scene) {
      _SnakePreviewScene.grow => (cycle + 2.6) % cycleSeconds,
      _SnakePreviewScene.collision => cycle + 11.7,
      _ => cycle,
    };
    final movement = max(0.0, scriptCycle - _initialHoldSeconds);
    final rawStep = movement / stepSeconds;
    final lastStep = scene == _SnakePreviewScene.queue
        ? 3
        : _headTrail.length - 4;
    final completedStep = min(lastStep, rawStep.floor());
    final targetStep = min(lastStep, completedStep + 1);
    final progress = completedStep >= lastStep ? 1.0 : rawStep - completedStep;
    final previousBody = _bodyAt(completedStep);
    final targetBody = _bodyAt(targetStep);
    final builtPathPoints = buildMidnightSnakePath(
      body: targetBody,
      previousBody: previousBody,
      progress: progress,
    );
    final pathPoints = scene == _SnakePreviewScene.collision
        ? builtPathPoints
              .map(
                (point) => MidnightSnakePathPoint(point.row - 2, point.column),
              )
              .toList(growable: false)
        : builtPathPoints;
    final direction = targetStep == completedStep
        ? _directionAt(completedStep)
        : _directionAt(targetStep);
    final score = completedStep >= 13
        ? 2
        : completedStep >= 4
        ? 1
        : 0;
    final collision =
        scene == _SnakePreviewScene.collision && completedStep >= lastStep;
    final fadeStart = sceneCycleSeconds - 0.55;
    final fadeOpacity = cycle <= fadeStart
        ? 0.0
        : ((cycle - fadeStart) / (sceneCycleSeconds - fadeStart)).clamp(
            0.0,
            1.0,
          );
    final queue = _queueAt(scriptCycle, completedStep);
    final showGolden =
        (scene == _SnakePreviewScene.home ||
            scene == _SnakePreviewScene.grow) &&
        cycle >= 3 &&
        cycle < 7;
    final showMouse =
        (scene == _SnakePreviewScene.home ||
            scene == _SnakePreviewScene.grow) &&
        cycle >= 9 &&
        cycle < 14;
    return _SnakePreviewFrame(
      pathPoints: pathPoints,
      direction: direction,
      food: scene == _SnakePreviewScene.collision
          ? null
          : completedStep < 4
          ? const SnakeCell(7, 6)
          : completedStep < 13
          ? const SnakeCell(8, 6)
          : const SnakeCell(4, 2),
      foodType: score % 6,
      foodFrame: ((scriptCycle / 0.18).floor()) % 2,
      goldenSausage: showGolden ? const SnakeCell(0, 8) : null,
      mouse: showMouse
          ? SnakeCell(3, 2 + ((cycle - 9) / 1.2).floor().clamp(0, 3))
          : null,
      mouseDirection: SnakeDirection.right,
      bonusFrame: ((scriptCycle / 0.5).floor()) % 2,
      headFrame: ((scriptCycle / 0.11).floor()) % 4,
      score: score,
      remainingSeconds: max(0, 300 - cycle.floor()),
      queuedDirections: queue,
      appliedTurns: min(3, completedStep),
      justAte: (completedStep == 4 || completedStep == 13) && progress < 0.45,
      collision: collision,
      fadeOpacity: fadeOpacity,
    );
  }

  static List<SnakeCell> _bodyAt(int step) {
    final headIndex = 3 + step;
    final length = step >= 13
        ? 6
        : step >= 4
        ? 5
        : 4;
    return [
      for (var index = 0; index < length; index++)
        _headTrail[max(0, headIndex - index)],
    ];
  }

  static SnakeDirection _directionAt(int step) {
    if (step <= 0) return SnakeDirection.right;
    final from = _headTrail[3 + step - 1];
    final to = _headTrail[3 + step];
    if (to.row < from.row) return SnakeDirection.up;
    if (to.row > from.row) return SnakeDirection.down;
    return to.column < from.column ? SnakeDirection.left : SnakeDirection.right;
  }

  static List<SnakeDirection> _queueAt(double cycle, int completedStep) {
    const opening = [
      SnakeDirection.up,
      SnakeDirection.right,
      SnakeDirection.down,
    ];
    if (completedStep >= 3) return const [];
    if (cycle < 0.35) return const [];
    final revealed = cycle < 0.65
        ? 1
        : cycle < 0.95
        ? 2
        : 3;
    return opening
        .skip(completedStep)
        .take(max(0, revealed - completedStep))
        .toList(growable: false);
  }
}

class _SnakePreviewBody extends CustomPainter {
  const _SnakePreviewBody({required this.frame, required this.pattern});

  final _SnakePreviewFrame frame;
  final ui.Image? pattern;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var index = 0; index < frame.pathPoints.length; index++) {
      final point = frame.pathPoints[index];
      final center = Offset(
        _SnakePreviewFrame.boardLeft +
            (point.column + 0.5) * _SnakePreviewFrame.cellSize,
        _SnakePreviewFrame.boardTop +
            (point.row + 0.5) * _SnakePreviewFrame.cellSize,
      );
      if (index == 0) {
        path.moveTo(center.dx, center.dy);
      } else {
        path.lineTo(center.dx, center.dy);
      }
    }
    final bodyPaint = Paint()
      ..color = const Color(0xFFDC9819)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = false;
    canvas.drawPath(path, bodyPaint);
    if (pattern case final image?) {
      final patternPaint = Paint()
        ..shader = ui.ImageShader(
          image,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Float64List.fromList([
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
        )
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none;
      canvas.drawPath(path, patternPaint);
    }
    if (frame.collision) {
      final head = frame.pathPoints.first;
      canvas.drawRect(
        Rect.fromLTWH(
          _SnakePreviewFrame.boardLeft +
              head.column * _SnakePreviewFrame.cellSize,
          _SnakePreviewFrame.boardTop + head.row * _SnakePreviewFrame.cellSize,
          _SnakePreviewFrame.cellSize,
          _SnakePreviewFrame.cellSize,
        ).inflate(2),
        Paint()..color = const Color(0x99FF4B2B),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnakePreviewBody oldDelegate) => true;
}

class _SnakePreviewHud extends StatelessWidget {
  const _SnakePreviewHud({required this.frame});

  final _SnakePreviewFrame frame;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 42,
        top: 54,
        child: _SnakeHudValue(
          eyebrow: 'SURVIVE',
          value: '${frame.score.toString().padLeft(2, '0')}개',
        ),
      ),
      Positioned(
        right: 38,
        top: 54,
        child: _SnakeHudValue(
          eyebrow: 'TIME',
          value: frame.remainingSeconds.toString(),
          alignEnd: true,
        ),
      ),
      const Positioned(
        left: 38,
        right: 38,
        bottom: 62,
        child: _SnakePreviewCaption(text: '하단 방향 버튼 · 최대 3개 예약'),
      ),
    ],
  );
}

class _SnakeHudValue extends StatelessWidget {
  const _SnakeHudValue({
    required this.eyebrow,
    required this.value,
    this.alignEnd = false,
  });

  final String eyebrow;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      WordSafeText(
        eyebrow,
        style: const TextStyle(
          color: Color(0xFFB8D8DC),
          fontFamily: 'Galmuri',
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
      WordSafeText(
        value,
        style: const TextStyle(
          color: Color(0xFFFFE1A3),
          fontFamily: 'Galmuri',
          fontSize: 21,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Color(0xFF020A10), offset: Offset(2, 2))],
        ),
      ),
    ],
  );
}

class _SnakeButtonsOverlay extends StatelessWidget {
  const _SnakeButtonsOverlay();

  static const _directions = <SnakeDirection>[
    SnakeDirection.left,
    SnakeDirection.up,
    SnakeDirection.down,
    SnakeDirection.right,
  ];

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned(
        left: 30,
        right: 30,
        top: 410,
        child: _SnakePreviewCaption(text: '위에 ↑ · 아래에 ← ↓ →'),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 195,
        child: Stack(
          key: const Key('midnight-snake-direction-buttons'),
          children: [
            const Positioned.fill(
              child: Image(
                image: AssetImage(
                  'assets/images/midnight_snake/arcade_controls.png',
                ),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
              ),
            ),
            for (var i = 0; i < _directions.length; i++)
              Positioned.fromRect(
                rect: const [
                  Rect.fromLTWH(113, 73, 40, 39),
                  Rect.fromLTWH(160, 31, 40, 38),
                  Rect.fromLTWH(160, 73, 40, 39),
                  Rect.fromLTWH(207, 73, 40, 39),
                ][i],
                child: _SnakeGuideDirectionButton(direction: _directions[i]),
              ),
          ],
        ),
      ),
    ],
  );
}

class _SnakeGuideDirectionButton extends StatelessWidget {
  const _SnakeGuideDirectionButton({required this.direction});

  final SnakeDirection direction;

  @override
  Widget build(BuildContext context) {
    final label = switch (direction) {
      SnakeDirection.left => '왼쪽',
      SnakeDirection.up => '위쪽',
      SnakeDirection.down => '아래쪽',
      SnakeDirection.right => '오른쪽',
    };
    return Semantics(
      button: true,
      label: '$label 방향 버튼',
      child: SizedBox.expand(
        key: Key('midnight-snake-guide-button-${direction.name}'),
      ),
    );
  }
}

class _SnakeQueueOverlay extends StatelessWidget {
  const _SnakeQueueOverlay({required this.frame});

  final _SnakePreviewFrame frame;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 86,
        right: 86,
        top: 270,
        child: Container(
          key: const Key('midnight-snake-queued-inputs'),
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: const Color(0xD903121C),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < 3; index++) ...[
                _SnakeQueueSlot(
                  direction: index < frame.queuedDirections.length
                      ? frame.queuedDirections[index]
                      : null,
                  index: index,
                  applied: index < frame.appliedTurns,
                ),
                if (index < 2) const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ),
      Positioned(
        left: 40,
        right: 40,
        bottom: 58,
        child: _SnakePreviewCaption(
          text: frame.queuedDirections.isEmpty
              ? '예약한 방향이 실제 회전에 적용됐어요'
              : '예약 ${frame.queuedDirections.length}/3 · 입력 순서대로 적용',
        ),
      ),
    ],
  );
}

class _SnakeQueueSlot extends StatelessWidget {
  const _SnakeQueueSlot({
    required this.direction,
    required this.index,
    required this.applied,
  });

  final SnakeDirection? direction;
  final int index;
  final bool applied;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('midnight-snake-queue-slot-$index'),
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: direction != null
          ? const Color(0xFFDC9819)
          : applied
          ? const Color(0xFF285A50)
          : const Color(0xFF102C35),
      border: Border.all(
        color: direction != null || applied
            ? const Color(0xFFFFE1A3)
            : const Color(0xFF28515A),
        width: 2,
      ),
    ),
    child: direction == null
        ? applied
              ? const Icon(
                  Icons.check_rounded,
                  color: Color(0xFFFFE1A3),
                  size: 25,
                )
              : null
        : Icon(
            _directionIcon(direction!),
            color: const Color(0xFF03121C),
            size: 25,
          ),
  );
}

class _SnakeGrowOverlay extends StatelessWidget {
  const _SnakeGrowOverlay({required this.frame});

  final _SnakePreviewFrame frame;

  @override
  Widget build(BuildContext context) {
    final bonusText = frame.goldenSausage != null
        ? '황금 +3 · 몸길이 +1'
        : frame.mouse != null
        ? '쥐 +2 · 몸길이 +1'
        : frame.justAte
        ? '+1 · 몸길이 +1'
        : null;
    return Stack(
      children: [
        if (bonusText != null)
          Positioned(
            key: const Key('midnight-snake-grow-score'),
            left: 104,
            right: 104,
            top: frame.goldenSausage != null ? 176 : 288,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: const Color(0xD903121C),
              child: WordSafeText(
                bonusText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFC875),
                  fontFamily: 'Galmuri',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        const Positioned(
          left: 40,
          right: 40,
          bottom: 58,
          child: _SnakePreviewCaption(text: '일반 +1 · 황금 +3 · 쥐 +2'),
        ),
      ],
    );
  }
}

class _SnakeCollisionOverlay extends StatelessWidget {
  const _SnakeCollisionOverlay({required this.frame});

  final _SnakePreviewFrame frame;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (frame.collision)
        const Positioned(
          key: Key('midnight-snake-collision-warning'),
          left: 102,
          right: 102,
          top: 286,
          child: _SnakePreviewCaption(text: 'GAME OVER'),
        ),
      Positioned(
        left: 40,
        right: 40,
        bottom: 58,
        child: _SnakePreviewCaption(
          text: frame.collision ? '자기 몸과 충돌했어요' : '벽과 자기 몸을 피하세요',
        ),
      ),
    ],
  );
}

class _SnakePreviewCaption extends StatelessWidget {
  const _SnakePreviewCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xD903121C),
      border: Border.all(color: const Color(0xFF28515A)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: WordSafeText(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFFFE1A3),
          fontFamily: 'Galmuri',
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

IconData _directionIcon(SnakeDirection direction) => switch (direction) {
  SnakeDirection.up => Icons.arrow_upward_rounded,
  SnakeDirection.right => Icons.arrow_forward_rounded,
  SnakeDirection.down => Icons.arrow_downward_rounded,
  SnakeDirection.left => Icons.arrow_back_rounded,
};

class _SausageAtlasCell extends StatelessWidget {
  const _SausageAtlasCell({
    required this.assetPath,
    required this.columns,
    required this.rows,
    required this.column,
    required this.row,
    this.dimension = 32,
  });

  final String assetPath;
  final int columns;
  final int rows;
  final int column;
  final int row;
  final double dimension;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: dimension,
    child: ClipRect(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: -column * dimension,
            top: -row * dimension,
            width: columns * dimension,
            height: rows * dimension,
            child: Image.asset(
              assetPath,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AppleGuideScene extends StatelessWidget {
  const _AppleGuideScene({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/apple_game_v2/apple_game_background.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.22),
        filterQuality: FilterQuality.none,
      ),
      const ColoredBox(color: Color(0x4D010B27)),
      child,
    ],
  );
}

class _AppleDragGuideVisual extends StatelessWidget {
  const _AppleDragGuideVisual();

  @override
  Widget build(BuildContext context) => const _AppleGuideSpriteAnimation(
    id: 'apple-drag-guide',
    assetPath: 'assets/images/apple_game_v2/guide_drag_sprite_sheet.png',
    frameCount: 8,
    frameDuration: Duration(milliseconds: 175),
  );
}

class _AppleTargetGuideVisual extends StatelessWidget {
  const _AppleTargetGuideVisual();

  @override
  Widget build(BuildContext context) => const _AppleGuideSpriteAnimation(
    id: 'apple-target-guide',
    assetPath: 'assets/images/apple_game_v2/guide_target_pop_sprite_sheet.png',
    frameCount: 12,
    frameDuration: Duration(milliseconds: 125),
  );
}

class _AppleSparseRectangleGuideVisual extends StatelessWidget {
  const _AppleSparseRectangleGuideVisual();

  @override
  Widget build(BuildContext context) => const _AppleGuideSpriteAnimation(
    id: 'apple-sparse-guide',
    assetPath: 'assets/images/apple_game_v2/guide_sparse_pop_sprite_sheet.png',
    frameCount: 12,
    frameDuration: Duration(milliseconds: 125),
  );
}

class _AppleGuideSpriteAnimation extends StatefulWidget {
  const _AppleGuideSpriteAnimation({
    required this.id,
    required this.assetPath,
    required this.frameCount,
    required this.frameDuration,
  });

  final String id;
  final String assetPath;
  final int frameCount;
  final Duration frameDuration;

  @override
  State<_AppleGuideSpriteAnimation> createState() =>
      _AppleGuideSpriteAnimationState();
}

class _AppleGuideSpriteAnimationState
    extends State<_AppleGuideSpriteAnimation> {
  Timer? _frameTimer;
  var _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    _frameTimer = Timer.periodic(widget.frameDuration, (_) {
      if (!mounted) return;
      setState(() => _frameIndex = (_frameIndex + 1) % widget.frameCount);
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AppleGuideScene(
    child: Center(
      child: SizedBox(
        key: Key('${widget.id}-sprite'),
        width: _AppleGuideLayout.sceneWidth,
        height: _AppleGuideLayout.sceneHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              key: Key('${widget.id}-frame-$_frameIndex'),
              left: -_frameIndex * _AppleGuideLayout.sceneWidth,
              top: 0,
              width: _AppleGuideLayout.sceneWidth * widget.frameCount,
              height: _AppleGuideLayout.sceneHeight,
              child: Image.asset(
                widget.assetPath,
                key: Key('${widget.id}-sheet'),
                width: _AppleGuideLayout.sceneWidth * widget.frameCount,
                height: _AppleGuideLayout.sceneHeight,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppleScoringGuideVisual extends StatelessWidget {
  const _AppleScoringGuideVisual();

  @override
  Widget build(BuildContext context) => _AppleGuideScene(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      child: Row(
        children: [
          const Expanded(
            child: _AppleScoreExample(
              label: '4 + 6',
              values: [4, 6],
              score: '+2점',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.primary.withValues(alpha: 0.9),
              size: 26,
            ),
          ),
          const Expanded(
            child: _AppleScoreExample(
              label: '1 + 2 + 3 + 4',
              values: [1, 2, 3, 4],
              score: '+4점',
              emphasized: true,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AppleResultGuideVisual extends StatelessWidget {
  const _AppleResultGuideVisual();

  @override
  Widget build(BuildContext context) => _AppleGuideScene(
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xE6011B19),
          border: Border.all(color: const Color(0xFFFFD24A), width: 2),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WordSafeText(
              'TIME  02:00',
              style: TextStyle(
                fontFamily: 'Galmuri',
                color: Color(0xFFFFD24A),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 10),
            WordSafeText(
              '48개',
              style: TextStyle(
                fontFamily: 'Galmuri',
                color: Color(0xFFFFF3C4),
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 6),
            WordSafeText(
              '많이 지울수록 높은 순위',
              style: TextStyle(
                color: AppColors.reward,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppleGuideBoard extends StatelessWidget {
  const _AppleGuideBoard({required this.values});

  static const cellSize = 42.0;
  static const padding = 8.0;

  final List<List<int?>> values;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.all(padding),
      color: const Color(0xB3011B19),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in row)
                  value == null
                      ? const SizedBox.square(dimension: cellSize)
                      : _AppleGuideTile(value: value),
              ],
            ),
        ],
      ),
    ),
  );
}

class _AppleGuideTile extends StatelessWidget {
  const _AppleGuideTile({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _AppleGuideBoard.cellSize,
    child: Stack(
      alignment: Alignment.center,
      children: [
        _AppleAtlasFrame(value: value),
        WordSafeText(
          '$value',
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: const Color(0xFFFFF3C4),
            fontSize: _AppleGuideBoard.cellSize * 0.38,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(color: Color(0xFF591F2C), offset: Offset(1, 1)),
              Shadow(color: Color(0xFF591F2C), offset: Offset(-1, -1)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AppleAtlasFrame extends StatelessWidget {
  const _AppleAtlasFrame({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final index = value - 1;
    final row = index ~/ 3;
    final column = index % 3;
    const frameSize = _AppleGuideBoard.cellSize;
    const sheetSize = frameSize * 3;
    return SizedBox.square(
      dimension: frameSize,
      child: ClipRect(
        child: Transform.translate(
          offset: Offset(-column * frameSize, -row * frameSize),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: sheetSize,
            maxWidth: sheetSize,
            minHeight: sheetSize,
            maxHeight: sheetSize,
            child: Image.asset(
              'assets/images/apple_game_v2/apple_faces_atlas.png',
              width: sheetSize,
              height: sheetSize,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppleScoreExample extends StatelessWidget {
  const _AppleScoreExample({
    required this.label,
    required this.values,
    required this.score,
    this.emphasized = false,
  });

  final String label;
  final List<int> values;
  final String score;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xD9011B19),
      border: Border.all(
        color: emphasized ? const Color(0xFFFFD24A) : AppColors.border,
        width: 2,
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          children: [for (final value in values) _AppleGuideTile(value: value)],
        ),
        const SizedBox(height: 7),
        WordSafeText(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFFFF3C4),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        WordSafeText(
          score,
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: emphasized ? const Color(0xFFFFD24A) : AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

abstract final class _AppleGuideLayout {
  static const sceneWidth = 246.0;
  static const sceneHeight = 176.0;
}

class _SwipeGuideVisual extends StatelessWidget {
  const _SwipeGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/background_map.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.72),
        filterQuality: FilterQuality.none,
      ),
      const Positioned(
        bottom: 40,
        left: 0,
        right: 0,
        child: Center(
          child: _AtlasPreviewFrame(
            assetPath: 'assets/images/dung_dodge_v2/player_run_sheet.png',
            frameSize: 82,
          ),
        ),
      ),
      Positioned(
        left: 34,
        right: 34,
        bottom: 22,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(
              Icons.keyboard_double_arrow_left_rounded,
              color: AppColors.primary,
              size: 38,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              color: AppColors.backgroundDeep.withValues(alpha: 0.8),
              child: const Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    color: AppColors.text,
                    size: 22,
                  ),
                  SizedBox(width: 5),
                  WordSafeText(
                    '누르고 드래그',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_double_arrow_right_rounded,
              color: AppColors.primary,
              size: 38,
            ),
          ],
        ),
      ),
    ],
  );
}

class _GameplayGuideVisual extends StatelessWidget {
  const _GameplayGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/home_gameplay_hero.png',
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        filterQuality: FilterQuality.none,
      ),
      const Positioned(left: 10, top: 10, child: _VisualLabel(label: '인게임 화면')),
    ],
  );
}

class _DifficultyGuideVisual extends StatelessWidget {
  const _DifficultyGuideVisual();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: _DifficultyLane(
          label: '초반',
          color: AppColors.reward,
          poopPositions: [Alignment(0.35, -0.45), Alignment(-0.55, 0.05)],
        ),
      ),
      Container(width: 2, color: AppColors.border),
      const Expanded(
        child: _DifficultyLane(
          label: '후반',
          color: AppColors.danger,
          poopPositions: [
            Alignment(-0.65, -0.75),
            Alignment(0.45, -0.55),
            Alignment(-0.1, -0.15),
            Alignment(0.7, 0.08),
            Alignment(-0.7, 0.38),
            Alignment(0.08, 0.62),
          ],
        ),
      ),
    ],
  );
}

class _DifficultyLane extends StatelessWidget {
  const _DifficultyLane({
    required this.label,
    required this.color,
    required this.poopPositions,
  });

  final String label;
  final Color color;
  final List<Alignment> poopPositions;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/background_map.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.55),
        filterQuality: FilterQuality.none,
      ),
      for (final position in poopPositions)
        Align(
          alignment: position,
          child: const _AtlasPreviewFrame(
            assetPath: 'assets/images/dung_dodge_v2/poop_fall_sheet.png',
            frameSize: 35,
          ),
        ),
      Positioned(
        left: 8,
        top: 8,
        child: _VisualLabel(label: label, color: color),
      ),
    ],
  );
}

class _CollisionGuideVisual extends StatelessWidget {
  const _CollisionGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/background_map.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.75),
        filterQuality: FilterQuality.none,
      ),
      const Positioned(
        bottom: 36,
        left: 92,
        child: _AtlasPreviewFrame(
          assetPath: 'assets/images/dung_dodge_v2/player_idle_sheet.png',
          frameSize: 86,
        ),
      ),
      const Positioned(
        bottom: 116,
        left: 111,
        child: _AtlasPreviewFrame(
          assetPath: 'assets/images/dung_dodge_v2/poop_fall_sheet.png',
          frameSize: 48,
        ),
      ),
      Positioned(
        right: 16,
        top: 18,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          color: AppColors.danger.withValues(alpha: 0.92),
          child: const WordSafeText(
            '한 번 충돌 = 종료',
            style: TextStyle(
              color: AppColors.backgroundDeep,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    ],
  );
}

class _SurvivalGuideVisual extends StatelessWidget {
  const _SurvivalGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/home_gameplay_hero.png',
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        color: AppColors.backgroundDeep.withValues(alpha: 0.35),
        colorBlendMode: BlendMode.srcOver,
        filterQuality: FilterQuality.none,
      ),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          color: AppColors.backgroundDeep.withValues(alpha: 0.88),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: AppColors.primary,
                size: 34,
              ),
              SizedBox(height: 8),
              WordSafeText(
                '최대 5:00',
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 5),
              WordSafeText(
                '0.01초 단위로 랭킹 경쟁',
                style: TextStyle(
                  color: AppColors.reward,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _GravityControlGuideVisual extends StatelessWidget {
  const _GravityControlGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-control-sprite-animation'),
    mode: _GravityGuideMode.control,
  );
}

class _GravityLandingGuideVisual extends StatelessWidget {
  const _GravityLandingGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-landing-animation'),
    mode: _GravityGuideMode.landing,
  );
}

class _GravityObstacleGuideVisual extends StatelessWidget {
  const _GravityObstacleGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-obstacle-animation'),
    mode: _GravityGuideMode.obstacle,
  );
}

class _GravityDifficultyGuideVisual extends StatelessWidget {
  const _GravityDifficultyGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-difficulty-animation'),
    mode: _GravityGuideMode.difficulty,
  );
}

class _GravitySurvivalGuideVisual extends StatelessWidget {
  const _GravitySurvivalGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-collision-game-over-animation'),
    mode: _GravityGuideMode.collision,
  );
}

class _NumberSequenceGuideVisual extends StatelessWidget {
  const _NumberSequenceGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-sequence-animation'),
    mode: _NumberRushSceneMode.sequence,
  );
}

class _NumberNextGuideVisual extends StatelessWidget {
  const _NumberNextGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-next-animation'),
    mode: _NumberRushSceneMode.next,
  );
}

class _NumberRefillGuideVisual extends StatelessWidget {
  const _NumberRefillGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-refill-animation'),
    mode: _NumberRushSceneMode.refill,
  );
}

class _NumberMistakeGuideVisual extends StatelessWidget {
  const _NumberMistakeGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-mistake-animation'),
    mode: _NumberRushSceneMode.mistake,
  );
}

class _NumberResultGuideVisual extends StatelessWidget {
  const _NumberResultGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-result-animation'),
    mode: _NumberRushSceneMode.result,
  );
}

class _VisualLabel extends StatelessWidget {
  const _VisualLabel({required this.label, this.color = AppColors.primary});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    color: AppColors.backgroundDeep.withValues(alpha: 0.86),
    child: WordSafeText(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: SafeArea(top: false, child: child),
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.eyebrow,
    required this.title,
    required this.onClose,
    this.closeKey,
  });

  final String eyebrow;
  final String title;
  final VoidCallback onClose;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 44,
        height: 4,
        color: AppColors.border.withValues(alpha: 0.6),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WordSafeText(
                  eyebrow,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                WordSafeText(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          IconButton(
            key: closeKey,
            tooltip: '닫기',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppColors.text),
          ),
        ],
      ),
    ],
  );
}

class _RewardValue extends StatelessWidget {
  const _RewardValue({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: AppColors.reward, size: 16),
      const SizedBox(height: 2),
      WordSafeText(
        value,
        style: const TextStyle(
          color: AppColors.reward,
          fontFamily: 'Galmuri',
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 2),
      WordSafeText(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    ],
  );
}

class _TicketInventory extends StatelessWidget {
  const _TicketInventory({
    required this.practiceCount,
    required this.challengeCount,
    required this.showChallengeTicketAnimation,
    required this.practiceDelta,
    required this.practiceAnimationRevision,
    super.key,
  });

  final int practiceCount;
  final int challengeCount;
  final bool showChallengeTicketAnimation;
  final int practiceDelta;
  final int practiceAnimationRevision;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      _PracticeTicketBadge(
        key: const Key('practice-ticket-badge'),
        count: practiceCount,
        delta: practiceDelta,
        animationRevision: practiceAnimationRevision,
      ),
      if (challengeCount > 0 || showChallengeTicketAnimation) ...[
        const SizedBox(width: 8),
        _ChallengeTicketBadge(count: challengeCount),
      ],
    ],
  );
}

const _ticketBadgeHeight = 25.0;
const _ticketBadgeIconBoxSize = 24.0;
const _ticketBadgeIconSize = 20.0;
const _ticketBadgeIconGap = 4.0;
const _challengeTicketAnimationDuration = Duration(milliseconds: 600);
const _ticketBadgeCountTextStyle = TextStyle(
  fontFamily: 'Galmuri',
  fontSize: 13,
  fontWeight: FontWeight.w900,
  height: 1,
);

class _PracticeTicketBadge extends StatefulWidget {
  const _PracticeTicketBadge({
    required this.count,
    required this.delta,
    required this.animationRevision,
    super.key,
  });

  final int count;
  final int delta;
  final int animationRevision;

  @override
  State<_PracticeTicketBadge> createState() => _PracticeTicketBadgeState();
}

class _PracticeTicketBadgeState extends State<_PracticeTicketBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _activeDelta = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 650),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _activeDelta = 0);
          }
        });
  }

  @override
  void didUpdateWidget(covariant _PracticeTicketBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationRevision != oldWidget.animationRevision &&
        widget.delta != 0) {
      _activeDelta = widget.delta;
      _controller.forward(from: 0);
    } else if (widget.delta == 0 &&
        oldWidget.delta == 0 &&
        widget.count != oldWidget.count) {
      // Gift confirmations refresh the server-backed inventory after the
      // dialog closes. Animate that count change even though it does not use
      // the rewarded-ad animation path above.
      _activeDelta = widget.count - oldWidget.count;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _interval(double value, double start, double end) =>
      ((value - start) / (end - start)).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final progress = Curves.easeOutCubic.transform(_controller.value);
      final isGain = _activeDelta > 0;
      final shake = _activeDelta < 0
          ? sin(_controller.value * pi * 6) * (1 - progress) * 3
          : 0.0;
      final pulse = isGain
          ? 1 + sin(_controller.value * pi) * 0.16
          : 1 - sin(_controller.value * pi) * 0.05;

      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (isGain)
            for (var index = 0; index < 2; index++)
              Builder(
                builder: (context) {
                  final particleProgress = Curves.easeInBack.transform(
                    _interval(
                      _controller.value,
                      index * 0.12,
                      0.62 + index * 0.12,
                    ),
                  );
                  return Transform.translate(
                    offset: Offset(
                      (index == 0 ? -22 : 22) * (1 - particleProgress),
                      28 * (1 - particleProgress),
                    ),
                    child: Opacity(
                      opacity: _interval(
                        _controller.value,
                        index * 0.12,
                        0.25 + index * 0.12,
                      ),
                      child: const Icon(
                        Icons.confirmation_number_rounded,
                        key: Key('practice-ticket-gain-particle'),
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                  );
                },
              ),
          Transform.translate(
            offset: Offset(shake, 0),
            child: Transform.scale(scale: pulse, child: child),
          ),
          if (_activeDelta != 0)
            Transform.translate(
              offset: Offset(0, -8 - progress * 25),
              child: Opacity(
                opacity: (1 - progress).clamp(0.0, 1.0).toDouble(),
                child: Row(
                  key: const Key('practice-ticket-delta'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_activeDelta < 0)
                      const Icon(
                        Icons.confirmation_number_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    WordSafeText(
                      _activeDelta > 0 ? '+$_activeDelta' : '$_activeDelta',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontFamily: 'Galmuri',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
    child: Semantics(
      label: '연습권 ${widget.count}장',
      excludeSemantics: true,
      child: SizedBox(
        key: const Key('practice-ticket-inline'),
        height: _ticketBadgeHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: const Key('practice-ticket-icon-box'),
              width: _ticketBadgeIconBoxSize,
              height: _ticketBadgeIconBoxSize,
              child: const Center(
                child: Icon(
                  Icons.confirmation_number_rounded,
                  color: AppColors.primary,
                  size: _ticketBadgeIconSize,
                ),
              ),
            ),
            const SizedBox(width: _ticketBadgeIconGap),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: WordSafeText(
                '${widget.count}',
                key: ValueKey(widget.count),
                style: _ticketBadgeCountTextStyle.copyWith(
                  color: widget.count == 0
                      ? AppColors.textMuted
                      : AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChallengeTicketBadge extends StatefulWidget {
  const _ChallengeTicketBadge({required this.count});

  final int count;

  @override
  State<_ChallengeTicketBadge> createState() => _ChallengeTicketBadgeState();
}

class _ChallengeTicketBadgeState extends State<_ChallengeTicketBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _activeDelta = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: _challengeTicketAnimationDuration,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _activeDelta = 0);
          }
        });
  }

  @override
  void didUpdateWidget(covariant _ChallengeTicketBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count == oldWidget.count) return;
    _activeDelta = widget.count - oldWidget.count;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final progress = Curves.easeOutCubic.transform(_controller.value);
      final isGain = _activeDelta > 0;
      final pulse = isGain
          ? 1 + sin(_controller.value * pi) * 0.14
          : 1 - sin(_controller.value * pi) * 0.05;
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.scale(scale: pulse, child: child),
          if (_activeDelta != 0)
            Transform.translate(
              offset: Offset(0, -8 - progress * 22),
              child: Opacity(
                opacity: (1 - progress).clamp(0.0, 1.0).toDouble(),
                child: Row(
                  key: const Key('challenge-ticket-delta'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_activeDelta < 0)
                      const Icon(
                        Icons.sports_score_rounded,
                        color: AppColors.primary,
                        size: 16,
                      ),
                    WordSafeText(
                      _activeDelta > 0 ? '+$_activeDelta' : '$_activeDelta',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontFamily: 'Galmuri',
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
    child: Semantics(
      label: '도전권 ${widget.count}장',
      excludeSemantics: true,
      child: SizedBox(
        key: const Key('challenge-ticket-badge'),
        height: _ticketBadgeHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: const Key('challenge-ticket-icon-box'),
              width: _ticketBadgeIconBoxSize,
              height: _ticketBadgeIconBoxSize,
              child: const Center(
                child: Icon(
                  Icons.sports_score_rounded,
                  color: AppColors.primary,
                  size: _ticketBadgeIconSize,
                ),
              ),
            ),
            const SizedBox(width: _ticketBadgeIconGap),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: WordSafeText(
                '${widget.count}',
                key: ValueKey(widget.count),
                style: _ticketBadgeCountTextStyle.copyWith(
                  color: widget.count == 0
                      ? AppColors.textMuted
                      : AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.reward.withValues(alpha: 0.16),
      border: Border.all(color: AppColors.reward),
    ),
    child: WordSafeText(
      label,
      style: const TextStyle(
        color: AppColors.reward,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    ),
  );
}

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.compact = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: WordSafeText(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.text,
      minimumSize: const Size.fromHeight(50),
      padding: compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
      side: const BorderSide(color: AppColors.border, width: 2),
      shape: const RoundedRectangleBorder(),
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.playDate,
    required this.isTomorrow,
    required this.tomorrowAvailable,
    required this.onSettings,
    required this.onHistory,
    required this.onShop,
    required this.isSaving,
    required this.onTomorrow,
  });

  final DateTime playDate;
  final bool isTomorrow;
  final bool tomorrowAvailable;
  final VoidCallback onSettings;
  final VoidCallback onHistory;
  final VoidCallback onShop;
  final bool isSaving;
  final VoidCallback onTomorrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: WordSafeText(
                    isTomorrow ? '내일의 게임' : '오늘의 게임',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineLarge?.copyWith(fontSize: 28),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WordSafeText(
                  '${_monthName(playDate.month)} ${playDate.day}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: !tomorrowAvailable
                  ? '내일 게임 준비 중'
                  : isTomorrow
                  ? '오늘 게임으로 돌아가기 (-1일)'
                  : '내일 미리보기 (+1일)',
              child: IconButton(
                key: const Key('tomorrow-selector'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 40,
                ),
                padding: const EdgeInsets.all(6),
                onPressed: tomorrowAvailable ? onTomorrow : null,
                icon: _TomorrowIcon(
                  selected: isTomorrow,
                  enabled: tomorrowAvailable,
                ),
              ),
            ),
            IconButton(
              key: const Key('shop-button'),
              tooltip: '코인 상점',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 40),
              padding: const EdgeInsets.all(6),
              onPressed: isSaving ? null : onShop,
              icon: const Icon(
                Icons.storefront_outlined,
                color: AppColors.primary,
              ),
            ),
            IconButton(
              tooltip: '내 기록',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 40),
              padding: const EdgeInsets.all(6),
              onPressed: onHistory,
              icon: const Icon(Icons.history, color: AppColors.text),
            ),
            IconButton(
              tooltip: '설정',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 40),
              padding: const EdgeInsets.all(6),
              onPressed: isSaving ? null : onSettings,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.settings_outlined, color: AppColors.text),
            ),
          ],
        ),
      ],
    );
  }
}

class _TomorrowIcon extends StatelessWidget {
  const _TomorrowIcon({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.primary
        : enabled
        ? AppColors.text
        : AppColors.textMuted.withValues(alpha: 0.45);
    return Semantics(
      button: true,
      selected: selected,
      label: !enabled
          ? '내일 게임 준비 중'
          : selected
          ? '오늘 게임으로 돌아가기 (-1일)'
          : '내일 미리보기 (+1일)',
      child: SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.calendar_today_outlined, color: color, size: 22),
            Positioned(
              right: -6,
              top: -6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: enabled ? AppColors.primary : AppColors.surfaceLight,
                  border: Border.all(color: AppColors.backgroundDeep, width: 1),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  child: WordSafeText(
                    selected ? '-1' : '+1',
                    style: TextStyle(
                      color: AppColors.backgroundDeep,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _monthName(int month) {
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return months[month - 1];
}

class _GamePreview extends StatelessWidget {
  const _GamePreview({required this.gameId});

  final String? gameId;

  @override
  Widget build(BuildContext context) {
    final presentation = GamePresentationRegistry.forId(gameId);
    return AspectRatio(
      aspectRatio: presentation.homeAspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.backgroundDeep,
          border: Border.all(color: AppColors.border, width: 2),
          boxShadow: const [
            BoxShadow(color: AppColors.backgroundDeep, offset: Offset(6, 6)),
          ],
        ),
        child: switch (presentation.homePreview) {
          GameHomePreviewKind.dungDodgeV2 => const _DungDodgeV2Preview(),
          GameHomePreviewKind.gravitySwitch => const _GravityGamePreview(),
          GameHomePreviewKind.appleGameV2 => const _AppleGameV2Preview(),
          GameHomePreviewKind.numberRush => const _NumberRushHomePreview(),
          GameHomePreviewKind.mamaDuckTrail => const MamaDuckTrailHomePreview(),
          GameHomePreviewKind.midnightSnake =>
            const _MidnightSnakeHomePreview(),
          GameHomePreviewKind.sausageDachshund =>
            const _MidnightSnakeHomePreview(),
          GameHomePreviewKind.beatTheDealer => const _BeatTheDealerVisual(
            scene: _DealerPreviewScene.home,
          ),
          GameHomePreviewKind.tenPitchSlugger => const TenPitchSluggerPreview(
            scene: TenPitchSluggerPreviewScene.home,
          ),
          GameHomePreviewKind.ramenTimer => const RamenTimerPreview(
            scene: RamenTimerPreviewScene.home,
          ),
          GameHomePreviewKind.bathhouseSort => const BathhouseSortPreview(
            scene: BathhouseSortPreviewScene.home,
          ),
          GameHomePreviewKind.lilyFrog => const LilyFrogHomePreview(),
          GameHomePreviewKind.netBoat => const NetBoatPreview(
            scene: NetBoatPreviewScene.home,
          ),
          GameHomePreviewKind.moleReaction => const MoleReactionPreview(),
          GameHomePreviewKind.westernDuel => const WesternDuelPreview(
            animate: true,
          ),
          GameHomePreviewKind.windDarts => const WindDartsPreview(),
          GameHomePreviewKind.templeRun => const TempleRunPreview(),
        },
      ),
    );
  }
}

class _MidnightSnakeHomePreview extends StatelessWidget {
  const _MidnightSnakeHomePreview();

  @override
  Widget build(BuildContext context) =>
      const _MidnightSnakeVisual(scene: _SnakePreviewScene.home);
}

class _DungDodgeV2Preview extends StatelessWidget {
  const _DungDodgeV2Preview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('dung-dodge-v2-preview'),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/images/dung_dodge_v2/home_gameplay_hero.png',
          ),
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _AtlasPreviewFrame extends StatelessWidget {
  const _AtlasPreviewFrame({required this.assetPath, required this.frameSize});

  final String assetPath;
  final double frameSize;

  @override
  Widget build(BuildContext context) {
    final sheetSize = frameSize * 2;
    return SizedBox.square(
      dimension: frameSize,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: sheetSize,
          maxWidth: sheetSize,
          minHeight: sheetSize,
          maxHeight: sheetSize,
          child: Image.asset(
            assetPath,
            width: sheetSize,
            height: sheetSize,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    );
  }
}

class _NumberRushHomePreview extends StatefulWidget {
  const _NumberRushHomePreview();

  @override
  State<_NumberRushHomePreview> createState() => _NumberRushHomePreviewState();
}

class _NumberRushHomePreviewState extends State<_NumberRushHomePreview> {
  static const _frameCount = 40;

  Timer? _frameTimer;
  var _frame = 0;

  @override
  void initState() {
    super.initState();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _frame++);
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cycleFrame = _frame % _frameCount;
    final progress = cycleFrame / _frameCount;
    final elapsed = 8.80 + cycleFrame / 10;
    final firstFrame = progress >= 0.12 && progress < 0.22
        ? 1
        : progress >= 0.22
        ? 2
        : 0;
    final secondFrame = progress >= 0.36 && progress < 0.46
        ? 1
        : progress >= 0.46
        ? 2
        : 0;
    final thirdFrame = progress >= 0.60 && progress < 0.70
        ? 1
        : progress >= 0.70
        ? 2
        : 0;
    final expected = progress < 0.22
        ? 1
        : progress < 0.46
        ? 2
        : progress < 0.70
        ? 3
        : 4;

    return DecoratedBox(
      key: const Key('number-rush-home-hero'),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/number_rush/home_gameplay_hero.png'),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final tileSize = width * 0.1444;
          return Stack(
            key: const Key('number-rush-home-tap-animation'),
            fit: StackFit.expand,
            children: [
              Positioned(
                left: width * 0.2398,
                top: height * 0.1927,
                width: width * 0.167,
                height: height * 0.0743,
                child: ColoredBox(
                  color: const Color(0xFF020715),
                  child: Center(
                    child: WordSafeText(
                      elapsed.toStringAsFixed(2),
                      key: const Key('number-rush-home-time-value'),
                      style: const TextStyle(
                        fontFamily: 'Galmuri',
                        color: Color(0xFF39F3FF),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              _NumberRushHomeTapTile(
                number: 1,
                frame: firstFrame,
                left: width * 0.1053,
                top: height * 0.575,
                size: tileSize,
              ),
              _NumberRushHomeTapTile(
                number: 2,
                frame: secondFrame,
                left: width * 0.1053,
                top: height * 0.4534,
                size: tileSize,
              ),
              _NumberRushHomeTapTile(
                number: 3,
                frame: thirdFrame,
                left: width * 0.4145,
                top: height * 0.4534,
                size: tileSize,
              ),
              Positioned(
                left: width * 0.6388,
                top: height * 0.1927,
                width: width * 0.0835,
                height: height * 0.0743,
                child: ColoredBox(
                  color: const Color(0xFF020715),
                  child: Center(
                    child: WordSafeText(
                      '$expected',
                      key: const Key('number-rush-home-next-value'),
                      style: const TextStyle(
                        fontFamily: 'Galmuri',
                        color: Color(0xFFFF77CE),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NumberRushHomeTapTile extends StatelessWidget {
  const _NumberRushHomeTapTile({
    required this.number,
    required this.frame,
    required this.left,
    required this.top,
    required this.size,
  });

  final int number;
  final int frame;
  final double left;
  final double top;
  final double size;

  @override
  Widget build(BuildContext context) => Positioned(
    key: Key('number-rush-home-tile-$number'),
    left: left,
    top: top,
    width: size,
    height: size,
    child: Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        _NumberRushAtlasFrame(
          assetPath: 'assets/images/number_rush/number_button_states.png',
          columns: 3,
          rows: 2,
          frame: frame,
        ),
        Center(
          child: WordSafeText(
            '$number',
            style: TextStyle(
              fontFamily: 'Galmuri',
              color: frame == 2
                  ? const Color(0xFF183348)
                  : const Color(0xFF5DF5FF),
              fontSize: number >= 10 ? 17 : 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (frame == 1) ...[
          Positioned.fill(
            child: _NumberRushAtlasFrame(
              assetPath: 'assets/images/number_rush/arcade_fx_sheet.png',
              columns: 4,
              rows: 2,
              frame: 0,
            ),
          ),
          const Positioned(
            right: -3,
            bottom: -3,
            child: Icon(
              Icons.touch_app_rounded,
              color: Color(0xFFFFD84A),
              size: 18,
              shadows: [Shadow(color: Color(0xFF030713), blurRadius: 3)],
            ),
          ),
        ],
      ],
    ),
  );
}

enum _NumberRushSceneMode { main, sequence, next, refill, mistake, result }

class _NumberRushPreview extends StatefulWidget {
  const _NumberRushPreview({this.mode = _NumberRushSceneMode.main, super.key});

  final _NumberRushSceneMode mode;

  @override
  State<_NumberRushPreview> createState() => _NumberRushPreviewState();
}

class _NumberRushPreviewState extends State<_NumberRushPreview> {
  static const _frameCount = 40;
  static const _numbers = [
    12,
    3,
    19,
    7,
    24,
    15,
    1,
    21,
    9,
    5,
    18,
    11,
    25,
    2,
    14,
    6,
    23,
    10,
    17,
    4,
    20,
    8,
    16,
    22,
    13,
  ];

  Timer? _frameTimer;
  var _frame = 0;

  @override
  void initState() {
    super.initState();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % _frameCount);
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _frame / _frameCount;
    var expected = 8;
    var elapsed = 28.80 + progress;
    var caption = '8을 찾으세요';
    var clearedNumbers = <int>{1, 2, 3, 4, 5, 6, 7};
    int? pressedNumber;
    int? wrongNumber;
    int? ignitionNumber;
    var replacementIndex = -1;
    int? replacementNumber;
    var replacementIsOn = false;
    var completed = false;

    switch (widget.mode) {
      case _NumberRushSceneMode.main:
        if (progress >= 0.36 && progress < 0.5) pressedNumber = 8;
        if (progress >= 0.5) {
          clearedNumbers.add(8);
          expected = 9;
          caption = '다음 숫자로!';
        }
        if (progress >= 0.62) {
          replacementIndex = _numbers.indexOf(7);
          replacementNumber = 26;
          ignitionNumber = 26;
          replacementIsOn = progress >= 0.78;
        }
      case _NumberRushSceneMode.sequence:
        elapsed = 3.10 + progress;
        clearedNumbers = {};
        expected = 1;
        caption = '1 → 2 → 3';
        if (progress >= 0.12 && progress < 0.23) pressedNumber = 1;
        if (progress >= 0.23) {
          clearedNumbers.add(1);
          expected = 2;
        }
        if (progress >= 0.38 && progress < 0.49) pressedNumber = 2;
        if (progress >= 0.49) {
          clearedNumbers.add(2);
          expected = 3;
        }
        if (progress >= 0.64 && progress < 0.75) pressedNumber = 3;
        if (progress >= 0.75) {
          clearedNumbers.add(3);
          expected = 4;
        }
      case _NumberRushSceneMode.next:
        caption = 'NEXT와 같은 숫자를 탭';
        if (progress >= 0.32 && progress < 0.48) pressedNumber = 8;
        if (progress >= 0.48) {
          clearedNumbers.add(8);
          expected = 9;
        }
      case _NumberRushSceneMode.refill:
        elapsed = 34.20 + progress;
        expected = 12;
        caption = progress < 0.48 ? '빈칸을 살펴보세요' : '0.5~2초 뒤 26 점화';
        clearedNumbers = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};
        if (progress >= 0.38) {
          replacementIndex = _numbers.indexOf(1);
          replacementNumber = 26;
          ignitionNumber = 26;
          replacementIsOn = progress >= 0.68;
        }
      case _NumberRushSceneMode.mistake:
        elapsed = 28.80 + progress * 1.5;
        caption = '오답이어도 시간은 계속';
        if (progress >= 0.3 && progress < 0.56) wrongNumber = 18;
      case _NumberRushSceneMode.result:
        elapsed = 42.37;
        expected = 50;
        caption = progress < 0.48 ? '마지막 50을 탭' : '42.37초 · 기록 확정';
        clearedNumbers = {..._numbers}..remove(25);
        replacementIndex = _numbers.indexOf(25);
        replacementNumber = 50;
        replacementIsOn = true;
        if (progress >= 0.32 && progress < 0.48) pressedNumber = 50;
        completed = progress >= 0.48;
    }

    return DecoratedBox(
      key: widget.mode == _NumberRushSceneMode.main
          ? const Key('number-rush-home-animation')
          : null,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/number_rush/arcade_background.png'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF2071025),
            border: Border.all(color: const Color(0xFF7B2FB0), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xAAFF3EBC), blurRadius: 8),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 5,
                                  mainAxisSpacing: 2,
                                  crossAxisSpacing: 2,
                                ),
                            itemCount: _numbers.length,
                            itemBuilder: (context, index) {
                              final originalNumber = _numbers[index];
                              final number = index == replacementIndex
                                  ? replacementNumber!
                                  : originalNumber;
                              final isReplacement = index == replacementIndex;
                              final isCleared = isReplacement
                                  ? !replacementIsOn
                                  : clearedNumbers.contains(originalNumber);
                              final isPressed = pressedNumber == number;
                              final isWrong = wrongNumber == number;
                              return _NumberRushPreviewTile(
                                number: number,
                                cleared: isCleared,
                                pressed: isPressed,
                                wrong: isWrong,
                                igniting: ignitionNumber == number,
                                completed: completed && number == 50,
                                shakeRight: isWrong && (_frame ~/ 2).isEven,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _NumberRushPreviewHud(
                        elapsed: elapsed,
                        expected: expected,
                        caption: caption,
                        completed: completed,
                      ),
                    ),
                  ],
                ),
              ),
              if (completed)
                Center(
                  child: Container(
                    key: const Key('number-rush-clear-overlay'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    color: const Color(0xF2050A19),
                    child: const WordSafeText(
                      'CLEAR!',
                      style: TextStyle(
                        fontFamily: 'Galmuri',
                        color: Color(0xFFFFD84A),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberRushPreviewHud extends StatelessWidget {
  const _NumberRushPreviewHud({
    required this.elapsed,
    required this.expected,
    required this.caption,
    required this.completed,
  });

  final double elapsed;
  final int expected;
  final String caption;
  final bool completed;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const FittedBox(
        child: WordSafeText(
          'TAP 50',
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: Color(0xFF39F3FF),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 7),
      Row(
        children: [
          Expanded(
            child: _NumberRushHudValue(
              label: 'TIME',
              value: elapsed.toStringAsFixed(2),
              color: const Color(0xFF39F3FF),
            ),
          ),
          Container(width: 1, height: 39, color: const Color(0xFF64268F)),
          Expanded(
            child: _NumberRushHudValue(
              key: const Key('number-rush-preview-next'),
              label: 'NEXT',
              value: completed ? 'CLEAR' : '$expected',
              color: completed
                  ? const Color(0xFFFFD84A)
                  : const Color(0xFFFF77CE),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF030713),
          border: Border.all(color: const Color(0xFF3C255D)),
        ),
        child: WordSafeText(
          caption,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFFFD84A),
            fontSize: 9,
            height: 1.25,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _NumberRushHudValue extends StatelessWidget {
  const _NumberRushHudValue({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      WordSafeText(
        label,
        style: TextStyle(
          fontFamily: 'Galmuri',
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 3),
      FittedBox(
        child: WordSafeText(
          value,
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _NumberRushPreviewTile extends StatelessWidget {
  const _NumberRushPreviewTile({
    required this.number,
    required this.cleared,
    required this.pressed,
    required this.wrong,
    required this.igniting,
    required this.completed,
    required this.shakeRight,
  });

  final int number;
  final bool cleared;
  final bool pressed;
  final bool wrong;
  final bool igniting;
  final bool completed;
  final bool shakeRight;

  @override
  Widget build(BuildContext context) {
    final frame = completed
        ? 5
        : wrong
        ? 3
        : pressed
        ? 1
        : cleared
        ? 2
        : number == 50
        ? 4
        : 0;
    final numberColor = cleared
        ? const Color(0xFF183348)
        : number == 50
        ? const Color(0xFFFFD84A)
        : const Color(0xFF5DF5FF);

    return Transform.translate(
      offset: wrong ? Offset(shakeRight ? 2 : -2, 0) : Offset.zero,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          _NumberRushAtlasFrame(
            assetPath: 'assets/images/number_rush/number_button_states.png',
            columns: 3,
            rows: 2,
            frame: frame,
          ),
          Center(
            child: FittedBox(
              child: WordSafeText(
                '$number',
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: numberColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (pressed)
            const Positioned(
              right: -3,
              bottom: -3,
              child: Icon(
                Icons.touch_app_rounded,
                color: Color(0xFFFFD84A),
                size: 15,
                shadows: [Shadow(color: Color(0xFF030713), blurRadius: 3)],
              ),
            ),
          if (wrong || igniting || completed)
            Positioned.fill(
              child: Opacity(
                opacity: igniting && cleared ? 0.35 : 0.9,
                child: _NumberRushAtlasFrame(
                  assetPath: 'assets/images/number_rush/arcade_fx_sheet.png',
                  columns: 4,
                  rows: 2,
                  frame: wrong
                      ? 4
                      : completed
                      ? 6
                      : 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberRushAtlasFrame extends StatelessWidget {
  const _NumberRushAtlasFrame({
    required this.assetPath,
    required this.columns,
    required this.rows,
    required this.frame,
  });

  final String assetPath;
  final int columns;
  final int rows;
  final int frame;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final column = frame % columns;
      final row = frame ~/ columns;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -column * width,
              top: -row * height,
              width: width * columns,
              height: height * rows,
              child: Image.asset(
                assetPath,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _AppleGameV2Preview extends StatefulWidget {
  const _AppleGameV2Preview();

  @override
  State<_AppleGameV2Preview> createState() => _AppleGameV2PreviewState();
}

class _AppleGameV2PreviewState extends State<_AppleGameV2Preview> {
  static const _frameCount = 40;
  static const _cellSize = 42.0;
  static const _boardLeft = 12.0;
  static const _boardTop = 66.0;
  static const _firstTargetIndex = 17;
  static const _secondTargetIndex = 18;
  static const _values = [
    8, 2, 4, 3, 8, 6, 3, 5, //
    8, 6, 4, 7, 1, 1, 2, 3, //
    1, 4, 6, 5, 1, 3, 9, 6, //
    2, 8, 5, 7, 5, 9, 2, 4, //
    6, 7, 9, 7, 6, 6, 8, 3, //
    4, 1, 7, 1, 7, 9, 1, 5, //
    7, 9, 8, 4, 3, 7, 3, 4, //
    9, 1, 3, 4, 6, 6, 4, 7,
  ];

  Timer? _frameTimer;
  var _frame = 0;

  @override
  void initState() {
    super.initState();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % _frameCount);
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDragging = _frame >= 6 && _frame < 16;
    final reachedSecondApple = _frame >= 9;
    final firstAppleRemoved = _frame >= 16;
    final secondAppleRemoved = _frame >= 20;
    final firstPopFrame = _frame >= 16 && _frame < 20 ? _frame - 16 : null;
    final secondPopFrame = _frame >= 20 && _frame < 24 ? _frame - 20 : null;
    final score = _frame >= 24 ? 2 : 0;
    final sumLabel = switch (_frame) {
      >= 9 => '10 / 10',
      >= 6 => '4 / 10',
      _ => '합계 10 만들기',
    };
    final caption = switch (_frame) {
      >= 24 => '사과 2개 제거!',
      >= 16 => '펑!',
      >= 9 => '4 + 6 = 10',
      >= 6 => '4에서 6까지 드래그',
      _ => '드래그해서 10을 만드세요',
    };
    final dragProgress = ((_frame - 6) / 5).clamp(0.0, 1.0);
    final pointerLeft = 63.0 + 42.0 * dragProgress;

    return ClipRect(
      key: const Key('apple-game-v2-preview'),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          key: const Key('apple-home-animation'),
          width: 360,
          height: 462,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/apple_game_v2/apple_game_background.png',
                  key: const Key('apple-home-background'),
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.25),
                  filterQuality: FilterQuality.none,
                ),
              ),
              const Positioned.fill(
                child: ColoredBox(color: Color(0x26010B27)),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 10,
                height: 44,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6011B19),
                    border: Border.all(
                      color: const Color(0xFFFFD24A),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AppleHomeHudValue(
                          key: const Key('apple-home-score'),
                          label: 'APPLES',
                          value: '$score',
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 28,
                        color: const Color(0xFF6B4E1E),
                      ),
                      Expanded(
                        child: _AppleHomeHudValue(
                          key: const Key('apple-home-sum'),
                          label: 'SUM',
                          value: sumLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (var index = 0; index < _values.length; index++)
                Positioned(
                  left: _boardLeft + (index % 8) * _cellSize,
                  top: _boardTop + (index ~/ 8) * _cellSize,
                  width: _cellSize,
                  height: _cellSize,
                  child: _AppleHomeTile(
                    value: _values[index],
                    removed:
                        index == _firstTargetIndex && firstAppleRemoved ||
                        index == _secondTargetIndex && secondAppleRemoved,
                    popFrame: index == _firstTargetIndex
                        ? firstPopFrame
                        : index == _secondTargetIndex
                        ? secondPopFrame
                        : null,
                    popKey: index == _firstTargetIndex
                        ? const Key('apple-home-pop-first')
                        : index == _secondTargetIndex
                        ? const Key('apple-home-pop-second')
                        : null,
                    showCombo:
                        index == _secondTargetIndex && secondPopFrame != null,
                  ),
                ),
              if (isDragging)
                Positioned(
                  key: const Key('apple-home-selection'),
                  left: _boardLeft + _cellSize,
                  top: _boardTop + _cellSize * 2,
                  width: reachedSecondApple ? _cellSize * 2 : _cellSize,
                  height: _cellSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x55FFF3C4),
                      border: Border.all(
                        color: const Color(0xFFFFD24A),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              if (isDragging)
                Positioned(
                  key: const Key('apple-home-drag-pointer'),
                  left: pointerLeft,
                  top: _boardTop + _cellSize * 2 + 22,
                  child: const Icon(
                    Icons.touch_app_rounded,
                    color: Color(0xFFFFF3C4),
                    size: 26,
                    shadows: [Shadow(color: Color(0xFF011B19), blurRadius: 4)],
                  ),
                ),
              if (score > 0)
                const Positioned(
                  key: Key('apple-home-score-burst'),
                  left: 88,
                  top: 132,
                  child: WordSafeText(
                    '+2',
                    style: TextStyle(
                      fontFamily: 'Galmuri',
                      color: Color(0xFFFFD24A),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: Color(0xFF011B19), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 34,
                right: 34,
                bottom: 13,
                height: 34,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6011B19),
                    border: Border.all(
                      color: score > 0
                          ? const Color(0xFFFFD24A)
                          : const Color(0xFF5C806A),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: WordSafeText(
                      caption,
                      key: const Key('apple-home-caption'),
                      style: TextStyle(
                        fontFamily: 'Galmuri',
                        color: score > 0
                            ? const Color(0xFFFFD24A)
                            : const Color(0xFFFFF3C4),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleHomeHudValue extends StatelessWidget {
  const _AppleHomeHudValue({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      WordSafeText(
        label,
        style: const TextStyle(
          fontFamily: 'Galmuri',
          color: Color(0xFF91C9A9),
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 2),
      FittedBox(
        child: WordSafeText(
          value,
          style: const TextStyle(
            fontFamily: 'Galmuri',
            color: Color(0xFFFFD24A),
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _AppleHomeTile extends StatelessWidget {
  const _AppleHomeTile({
    required this.value,
    required this.removed,
    required this.popFrame,
    required this.popKey,
    required this.showCombo,
  });

  final int value;
  final bool removed;
  final int? popFrame;
  final Key? popKey;
  final bool showCombo;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      if (!removed)
        Positioned.fill(
          child: _AppleHomeAtlasFrame(
            assetPath: 'assets/images/apple_game_v2/apple_faces_atlas.png',
            columns: 3,
            rows: 3,
            frame: value - 1,
          ),
        ),
      if (!removed)
        Positioned.fill(
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, 4),
              child: WordSafeText(
                '$value',
                style: const TextStyle(
                  fontFamily: 'Galmuri',
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFF3C4),
                  shadows: [
                    Shadow(color: Color(0xFF591F2C), offset: Offset(1, 0)),
                    Shadow(color: Color(0xFF591F2C), offset: Offset(-1, 0)),
                    Shadow(color: Color(0xFF591F2C), offset: Offset(0, 1)),
                    Shadow(color: Color(0xFF591F2C), offset: Offset(0, -1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      if (popFrame != null)
        Positioned(
          left: 1,
          top: 1,
          width: 40,
          height: 40,
          child: _AppleHomeAtlasFrame(
            key: popKey,
            assetPath: 'assets/images/apple_game_v2/apple_pop_sheet.png',
            columns: 4,
            rows: 1,
            frame: popFrame!,
          ),
        ),
      if (showCombo)
        Positioned(
          key: const Key('apple-home-combo'),
          left: -11,
          top: -11,
          width: 64,
          height: 64,
          child: _AppleHomeAtlasFrame(
            assetPath:
                'assets/images/apple_game_v2/apple_combo_burst_sheet.png',
            columns: 4,
            rows: 3,
            frame: popFrame!,
          ),
        ),
    ],
  );
}

class _AppleHomeAtlasFrame extends StatelessWidget {
  const _AppleHomeAtlasFrame({
    required this.assetPath,
    required this.columns,
    required this.rows,
    required this.frame,
    super.key,
  });

  final String assetPath;
  final int columns;
  final int rows;
  final int frame;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final column = frame % columns;
      final row = frame ~/ columns;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -column * width,
              top: -row * height,
              width: width * columns,
              height: height * rows,
              child: Image.asset(
                assetPath,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      );
    },
  );
}

enum _GravityGuideMode { control, landing, obstacle, difficulty, collision }

class _GravityGuideAnimation extends StatefulWidget {
  const _GravityGuideAnimation({required this.mode, super.key});

  final _GravityGuideMode mode;

  @override
  State<_GravityGuideAnimation> createState() => _GravityGuideAnimationState();
}

class _GravityGuideAnimationState extends State<_GravityGuideAnimation> {
  @override
  Widget build(BuildContext context) => _GravityRuntimeGuide(mode: widget.mode);
}

class _GravityRuntimeGuide extends StatelessWidget {
  const _GravityRuntimeGuide({required this.mode});

  final _GravityGuideMode mode;

  @override
  Widget build(BuildContext context) {
    if (mode == _GravityGuideMode.difficulty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/gravity_switch_v2/gravity_runtime_hard.webp',
            key: const ValueKey('gravity-runtime-difficulty'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.none,
            gaplessPlayback: true,
          ),
          const Positioned(
            left: 10,
            top: 10,
            child: _VisualLabel(label: '후반 플레이', color: AppColors.danger),
          ),
        ],
      );
    }

    final assetPath = switch (mode) {
      _GravityGuideMode.control =>
        'assets/images/gravity_switch_v2/gravity_runtime_tap.webp',
      _GravityGuideMode.landing || _GravityGuideMode.obstacle =>
        'assets/images/gravity_switch_v2/gravity_runtime_control.webp',
      _GravityGuideMode.collision =>
        'assets/images/gravity_switch_v2/gravity_runtime_collision.webp',
      _GravityGuideMode.difficulty => throw StateError(
        'Difficulty uses a comparison.',
      ),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          assetPath,
          key: ValueKey('gravity-runtime-${mode.name}'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
        ),
        if (mode == _GravityGuideMode.control)
          const Positioned(
            left: 116,
            top: 112,
            child: _GravityTapCue(label: 'TAP ↑↓'),
          ),
        if (mode == _GravityGuideMode.landing)
          const Positioned(
            right: 10,
            top: 10,
            child: _VisualLabel(label: '착지 후 다시 탭', color: AppColors.reward),
          ),
        if (mode == _GravityGuideMode.obstacle)
          const Positioned(
            left: 10,
            top: 10,
            child: _VisualLabel(label: '안전한 쪽으로 이동 → 통과'),
          ),
      ],
    );
  }
}

class _GravityTapCue extends StatelessWidget {
  const _GravityTapCue({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    color: const Color(0xDD020617),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.touch_app_rounded, color: AppColors.primary, size: 22),
        const SizedBox(width: 5),
        WordSafeText(
          label,
          style: TextStyle(
            color: AppColors.text,
            fontFamily: 'Galmuri',
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _GravityGamePreview extends StatefulWidget {
  const _GravityGamePreview();

  @override
  State<_GravityGamePreview> createState() => _GravityGamePreviewState();
}

class _GravityGamePreviewState extends State<_GravityGamePreview> {
  static const _frameCount = 80;
  Timer? _timer;
  final _frame = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frame >= 0) {
      return ClipRect(
        key: const Key('gravity-home-animation'),
        child: Image.asset(
          'assets/images/gravity_switch_v2/gravity_runtime_main.webp',
          key: const Key('gravity-home-runtime-capture'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
        ),
      );
    }
    final cycleFrame = _frame % _frameCount;
    final goingUp = cycleFrame >= 8 && cycleFrame < 24;
    final onCeiling = cycleFrame >= 24 && cycleFrame < 39;
    final goingDown = cycleFrame >= 39 && cycleFrame < 55;
    final progressUp = ((cycleFrame - 8) / 16).clamp(0.0, 1.0);
    final progressDown = ((cycleFrame - 39) / 16).clamp(0.0, 1.0);
    final playerY = goingUp
        ? 350 - 116 * Curves.easeIn.transform(progressUp)
        : onCeiling
        ? 234.0
        : goingDown
        ? 234 + 116 * Curves.easeIn.transform(progressDown)
        : 350.0;
    final airborne = goingUp || goingDown;
    final double playerAngle = airborne
        ? (goingUp ? -1 : 1) * (cycleFrame % 16) / 16 * pi * 2
        : 0.0;
    final playerFrame = airborne
        ? 2 + ((cycleFrame ~/ 2) % 2)
        : (cycleFrame ~/ 2) % 2;
    final timer = 8.80 + cycleFrame / 10;
    final floorObstacleX = 310 - cycleFrame * 4.2;
    final ceilingObstacleX = 500 - cycleFrame * 5.0;

    return ClipRect(
      key: const Key('gravity-home-animation'),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 360,
          height: 462,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              const Positioned.fill(
                child: _GravitySceneBackground(
                  assetPath:
                      'assets/images/gravity_switch_v2/current_runtime_home.png',
                ),
              ),
              Positioned(
                left: floorObstacleX,
                bottom: 97,
                width: 48,
                height: 144,
                child: const _GravityObstacleModule(),
              ),
              Positioned(
                left: ceilingObstacleX,
                top: 76,
                width: 48,
                height: 144,
                child: const _GravityObstacleModule(ceiling: true),
              ),
              Positioned(
                left: 70,
                top: playerY - 24,
                width: 48,
                height: 48,
                child: Transform.rotate(
                  angle: playerAngle,
                  child: _GravityPlayerFrame(frame: playerFrame),
                ),
              ),
              if (cycleFrame == 24 ||
                  cycleFrame == 25 ||
                  cycleFrame == 55 ||
                  cycleFrame == 56)
                Positioned(
                  left: 70,
                  top: cycleFrame < 40 ? 210 : 320,
                  width: 48,
                  height: 48,
                  child: _GravityLandingFrame(frame: cycleFrame % 4),
                ),
              if (cycleFrame >= 5 && cycleFrame <= 11 ||
                  cycleFrame >= 36 && cycleFrame <= 42)
                const Positioned(
                  left: 124,
                  top: 205,
                  child: _GravityTapCue(label: 'TAP'),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 16,
                child: WordSafeText(
                  timer.toStringAsFixed(2),
                  key: const Key('gravity-home-time'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Galmuri',
                    color: Colors.white,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(color: Color(0xCC020617), offset: Offset(3, 3)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GravitySceneBackground extends StatelessWidget {
  const _GravitySceneBackground({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) => Image.asset(
    assetPath,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.none,
  );
}

class _GravityObstacleModule extends StatelessWidget {
  const _GravityObstacleModule({this.ceiling = false});

  final bool ceiling;

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipY: ceiling,
    child: Image.asset(
      'assets/images/gravity_switch_v2/platform_modules_v4/'
      'scrap_basic_1x3_01.png',
      fit: BoxFit.fill,
      filterQuality: FilterQuality.none,
    ),
  );
}

class _GravityPlayerFrame extends StatelessWidget {
  const _GravityPlayerFrame({required this.frame});

  final int frame;

  @override
  Widget build(BuildContext context) => _GravityAtlasFrame(
    assetPath:
        'assets/images/gravity_switch_v2/player_magnet_mite_sheet_v3.png',
    columns: 2,
    rows: 2,
    frame: frame,
  );
}

class _GravityLandingFrame extends StatelessWidget {
  const _GravityLandingFrame({required this.frame});

  final int frame;

  @override
  Widget build(BuildContext context) => _GravityAtlasFrame(
    assetPath: 'assets/images/gravity_switch_v2/landing_impact_sheet.png',
    columns: 2,
    rows: 2,
    frame: frame,
  );
}

class _GravityAtlasFrame extends StatelessWidget {
  const _GravityAtlasFrame({
    required this.assetPath,
    required this.columns,
    required this.rows,
    required this.frame,
  });

  final String assetPath;
  final int columns;
  final int rows;
  final int frame;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final column = frame % columns;
      final row = frame ~/ columns;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -column * width,
              top: -row * height,
              width: width * columns,
              height: height * rows,
              child: Image.asset(
                assetPath,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PixelGridBackground extends StatelessWidget {
  const _PixelGridBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.surface.withValues(alpha: 0.28);
    const gap = 24.0;

    for (var x = 0.0; x < size.width; x += gap) {
      for (var y = 0.0; y < size.height; y += gap) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

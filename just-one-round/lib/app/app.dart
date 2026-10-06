import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/critical_ota_restart_screen.dart';
import 'package:just_one_round/app/startup_intro.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/app/theme/app_theme.dart';
import 'package:just_one_round/core/events/chuseok_gift.dart';
import 'package:just_one_round/core/notifications/push_notification_service.dart';
import 'package:just_one_round/core/notifications/push_opt_in_reward.dart';
import 'package:just_one_round/core/notifications/push_notification_route.dart';
import 'package:just_one_round/core/update/app_update_reward.dart';
import 'package:just_one_round/core/update/critical_ota_update.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/history/presentation/play_history_screen.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/social/domain/social_notification.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

enum _PushOptInRewardAction { enable, openSettings, dismiss }

GoRouter createAppRouter({String initialLocation = '/'}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (context, state) => const TodayScreen()),
    GoRoute(
      path: '/play',
      redirect: (context, state) => state.extra is PlayAttempt ? null : '/',
      builder: (context, state) =>
          GameScreen(attempt: state.extra! as PlayAttempt),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const PlayHistoryScreen(),
    ),
  ],
);

class JustOneRoundApp extends StatefulWidget {
  const JustOneRoundApp({super.key});

  @override
  State<JustOneRoundApp> createState() => _JustOneRoundAppState();
}

class _JustOneRoundAppState extends State<JustOneRoundApp> {
  late final GoRouter _router = createAppRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '딱한판만',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
      builder: (context, child) =>
          _AppContent(router: _router, child: child ?? const SizedBox.shrink()),
    );
  }
}

class _AppContent extends ConsumerStatefulWidget {
  const _AppContent({required this.child, required this.router});

  final Widget child;
  final GoRouter router;

  @override
  ConsumerState<_AppContent> createState() => _AppContentState();
}

class _AppContentState extends ConsumerState<_AppContent>
    with WidgetsBindingObserver {
  late final RewardedAdService _rewardedAdService;
  var _mainPageVisible = false;
  var _preloadRequested = false;
  var _criticalOtaReady = false;
  var _socialInboxRequested = false;
  var _socialInboxLoading = false;
  var _socialInboxRefreshPending = false;
  var _pushTapPending = false;
  var _startupModalFlowActive = false;
  var _pushOptInRewardBusy = false;
  var _pushOptInRewardResumePending = false;
  var _appIsResumed = true;
  final _handledPushKeys = <String>{};
  late String _lastKnownLocation;
  String? _criticalOtaRestartMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastKnownLocation = _currentLocation;
    widget.router.routerDelegate.addListener(_handleRouteChanged);
    _rewardedAdService = ref.read(rewardedAdServiceProvider);
    unawaited(_prepareCriticalOtaUpdate());
    ref.listenManual(
      todayStateProvider,
      (_, next) => next.whenData(_handleTodayState),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_handleRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String get _currentLocation {
    final configuration = widget.router.routerDelegate.currentConfiguration;
    if (configuration.matches.isEmpty) return '/';
    return widget.router.state.matchedLocation;
  }

  bool get _isLobbyVisible => _currentLocation == '/';

  void _handleRouteChanged() {
    final location = _currentLocation;
    final wasLobbyVisible = _lastKnownLocation == '/';
    _lastKnownLocation = location;
    if (location != '/' || wasLobbyVisible || !_mainPageVisible) return;
    _requestSocialInboxOnLobby();
  }

  void _requestSocialInboxOnLobby() {
    if (!mounted || !_mainPageVisible || !_isLobbyVisible) return;
    if (_pushOptInRewardBusy) {
      _socialInboxRefreshPending = true;
      return;
    }
    if (_socialInboxLoading) {
      _socialInboxRefreshPending = true;
      return;
    }
    _socialInboxRefreshPending = false;
    if (_pushTapPending) {
      unawaited(_showSocialInboxAfterPushTap());
      return;
    }
    unawaited(_showSocialInboxAfterLobbyTransition());
  }

  Future<void> _showSocialInboxAfterLobbyTransition() async {
    // Wait for go_router to finish replacing the game route before pushing a
    // dialog onto the root navigator. Pushing during that replacement can
    // make the dialog disappear with the outgoing game route.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || !_isLobbyVisible || _pushOptInRewardBusy) {
      _socialInboxRefreshPending = true;
      return;
    }
    if (_socialInboxLoading) {
      _socialInboxRefreshPending = true;
      return;
    }
    _socialInboxRefreshPending = false;
    await _showSocialInbox(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    if (!_appIsResumed || !_mainPageVisible) return;
    // Re-check an accepted, not-yet-paid opt-in if the player granted OS
    // notification permission directly in Settings and returned to the app.
    _pushOptInRewardResumePending = true;

    final today = ref.read(todayStateProvider).value;
    unawaited(
      refreshPushTokenRegistration(
        ref.read(socialRepositoryProvider),
        appNotificationsEnabled: today?.socialNotificationsEnabled ?? true,
      ).then<void>((_) {}),
    );
    if (_pushTapPending) unawaited(_showSocialInboxAfterPushTap());
    if (_pushOptInRewardResumePending) {
      unawaited(_retryPushOptInRewardAfterResume());
    }
  }

  @override
  Widget build(BuildContext context) {
    final requiresStoreUpdate =
        ref.watch(todayStateProvider).value?.requiresUpdate ?? false;
    final today = ref.watch(todayStateProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        StartupIntro(
          ready: _criticalOtaReady && (today.hasValue || today.hasError),
          onFinished: _handleStartupFinished,
          child: widget.child,
        ),
        if (_criticalOtaRestartMessage case final message?
            when !requiresStoreUpdate)
          Positioned.fill(child: CriticalOtaRestartScreen(message: message)),
      ],
    );
  }

  Future<void> _prepareCriticalOtaUpdate() async {
    final result = await ref
        .read(criticalOtaUpdateServiceProvider)
        .prepareUpdate();
    if (!mounted) return;
    setState(() {
      _criticalOtaReady = true;
      if (result.shouldPromptRestart) {
        _criticalOtaRestartMessage =
            result.message ?? defaultCriticalOtaMessage;
      }
    });
  }

  void _handleStartupFinished() {
    if (_mainPageVisible || _criticalOtaRestartMessage != null) return;
    _mainPageVisible = true;
    unawaited(_initializeRewardedAds());
    final today = ref.read(todayStateProvider).value;
    unawaited(
      initializePushNotifications(
        ref.read(socialRepositoryProvider),
        onMessage: _handleForegroundPush,
        onMessageOpenedApp: _handlePushOpened,
        appNotificationsEnabled: today?.socialNotificationsEnabled ?? true,
      ),
    );
    unawaited(_showStartupModals());
    if (today != null) _handleTodayState(today);
  }

  Future<void> _showStartupModals() async {
    _startupModalFlowActive = true;
    try {
      await _showSocialInbox();
      // A cold-start notification tap has priority over every other startup
      // modal. Finish that inbox flow before showing rewards or permissions.
      if (_pushTapPending) await _showSocialInboxAfterPushTap();
      await _showAppUpdateReward();
      await _showChuseokGift();
      if (!mounted || _pushTapPending) return;
      if (!ref.read(pushNotificationServiceProvider).isAvailable) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted || _pushTapPending) return;
      await _maybeShowPushOptInReward();
    } finally {
      _startupModalFlowActive = false;
      if (_pushOptInRewardResumePending && mounted) {
        unawaited(_retryPushOptInRewardAfterResume());
      }
      if (_socialInboxRefreshPending && mounted && _isLobbyVisible) {
        _socialInboxRefreshPending = false;
        unawaited(_showSocialInbox(force: true));
      }
    }
  }

  Future<void> _showAppUpdateReward() async {
    if (!mounted || !_isLobbyVisible) return;
    final today = ref.read(todayStateProvider).value;
    if (today == null || today.requiresUpdate || today.testMode) return;

    final repository = ref.read(dailyGameRepositoryProvider);
    if (repository is! AppUpdateRewardRepository) return;
    final updateRepository = repository as AppUpdateRewardRepository;

    AppUpdateReward reward;
    try {
      reward = await updateRepository.claimAppUpdateReward().timeout(
        const Duration(seconds: 8),
      );
    } catch (error, stackTrace) {
      // The reward is optional at startup. A temporary network or migration
      // failure must never prevent the player from reaching the lobby.
      debugPrint('[UpdateReward] Claim failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }
    if (!mounted || !_isLobbyVisible || !reward.hasReward) return;

    final dialogContext = await _waitForDialogContext();
    if (dialogContext == null ||
        !dialogContext.mounted ||
        !mounted ||
        !_isLobbyVisible) {
      return;
    }
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => _AppUpdateRewardDialog(reward: reward),
    );
    if (mounted) ref.invalidate(todayStateProvider);
  }

  Future<void> _showChuseokGift() async {
    if (!mounted || !_isLobbyVisible) return;
    final today = ref.read(todayStateProvider).value;
    if (today == null || today.requiresUpdate) return;

    final repository = ref.read(dailyGameRepositoryProvider);
    if (repository is! ChuseokGiftRepository) return;
    final giftRepository = repository as ChuseokGiftRepository;

    ChuseokGiftStatus status;
    try {
      status = await giftRepository.fetchChuseokGiftStatus().timeout(
        const Duration(seconds: 8),
      );
    } catch (error, stackTrace) {
      // The event is optional at startup. A temporary outage leaves the
      // account unclaimed, so the next launch can retry the status check.
      debugPrint('[ChuseokGift] Status check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }
    if (!mounted || !_isLobbyVisible || !status.shouldShow) return;

    final dialogContext = await _waitForDialogContext();
    if (dialogContext == null || !dialogContext.mounted || !mounted) return;
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => _ChuseokGiftDialog(
        onClaim: () => giftRepository.claimChuseokGift().timeout(
          const Duration(seconds: 8),
        ),
      ),
    );
    if (mounted) ref.invalidate(todayStateProvider);
  }

  Future<void> _maybeShowPushOptInReward() async {
    if (!mounted ||
        !_mainPageVisible ||
        !_isLobbyVisible ||
        _pushOptInRewardBusy) {
      return;
    }
    final today = ref.read(todayStateProvider).value;
    if (today == null || today.requiresUpdate || today.testMode) return;

    final pushService = ref.read(pushNotificationServiceProvider);
    if (!pushService.isAvailable) return;
    final repository = ref.read(dailyGameRepositoryProvider);
    if (repository is! PushOptInRewardRepository) return;
    final rewardRepository = repository as PushOptInRewardRepository;

    _pushOptInRewardBusy = true;
    try {
      PushOptInRewardStatus status;
      try {
        status = await rewardRepository.fetchPushOptInRewardStatus().timeout(
          const Duration(seconds: 8),
        );
      } catch (error, stackTrace) {
        debugPrint('[PushOptInReward] Status check failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        return;
      }
      if (!mounted || !_isLobbyVisible || status.claimed) return;

      final authorization = await pushService.getAuthorizationStatus();
      if (!mounted || !_isLobbyVisible) return;
      if (authorization == PushAuthorizationStatus.unavailable) return;

      // An already accepted account only needs a fresh device registration
      // before the server can settle its pending reward. It never sees the
      // prompt again.
      if (status.accepted &&
          authorization == PushAuthorizationStatus.authorized &&
          today.socialNotificationsEnabled) {
        await _settlePushOptInReward(
          rewardRepository,
          pushService,
          authorization,
          appNotificationsEnabled: today.socialNotificationsEnabled,
        );
        return;
      }

      final shouldPrompt =
          authorization != PushAuthorizationStatus.authorized ||
          !today.socialNotificationsEnabled;
      if (!status.shouldShow || !shouldPrompt) return;

      final dialogContext = await _waitForDialogContext();
      if (dialogContext == null ||
          !dialogContext.mounted ||
          !mounted ||
          !_isLobbyVisible) {
        return;
      }

      // The server reserves the monthly prompt here. The popup is only shown
      // when that reservation still reports should_show=true.
      final reserved = await rewardRepository
          .recordPushOptInRewardPrompt()
          .timeout(const Duration(seconds: 8));
      if (!mounted ||
          !dialogContext.mounted ||
          !_isLobbyVisible ||
          !reserved.shouldShow ||
          reserved.claimed) {
        return;
      }

      final action = await showDialog<_PushOptInRewardAction>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (_) => _PushOptInRewardDialog(
          denied: authorization == PushAuthorizationStatus.denied,
        ),
      );
      if (!mounted || action == null) return;
      if (action == _PushOptInRewardAction.dismiss) return;

      // Persist acceptance before touching OS permission or token state so a
      // settings round-trip can finish the reward on the next resume/start.
      final accepted = await rewardRepository
          .recordPushOptInRewardPrompt(accepted: true)
          .timeout(const Duration(seconds: 8));
      if (!mounted || !_isLobbyVisible || !accepted.accepted) return;

      try {
        await ref
            .read(socialRepositoryProvider)
            .setSocialNotificationsEnabled(true);
        ref.invalidate(todayStateProvider);
      } catch (error, stackTrace) {
        debugPrint('[PushOptInReward] App preference update failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        return;
      }

      if (action == _PushOptInRewardAction.openSettings) {
        _pushOptInRewardResumePending = true;
        await pushService.openNotificationSettings();
        return;
      }

      final requested = await pushService.requestPermissionAndRegister(
        ref.read(socialRepositoryProvider),
      );
      if (!mounted || !_isLobbyVisible) return;
      final refreshedAuthorization = await pushService.getAuthorizationStatus();
      await _settlePushOptInReward(
        rewardRepository,
        pushService,
        refreshedAuthorization == PushAuthorizationStatus.unavailable
            ? requested
            : refreshedAuthorization,
        appNotificationsEnabled: true,
      );
    } catch (error, stackTrace) {
      debugPrint('[PushOptInReward] Flow failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _pushOptInRewardBusy = false;
      if (_socialInboxRefreshPending &&
          !_startupModalFlowActive &&
          mounted &&
          _isLobbyVisible &&
          !_pushTapPending) {
        _socialInboxRefreshPending = false;
        unawaited(_showSocialInbox(force: true));
      }
    }
  }

  Future<void> _retryPushOptInRewardAfterResume() async {
    if (!_pushOptInRewardResumePending ||
        !mounted ||
        !_appIsResumed ||
        _pushOptInRewardBusy) {
      return;
    }
    if (!mounted ||
        !_appIsResumed ||
        !_isLobbyVisible ||
        _startupModalFlowActive ||
        _socialInboxLoading ||
        _pushTapPending) {
      return;
    }
    _pushOptInRewardResumePending = false;
    await _maybeShowPushOptInReward();
    if (mounted &&
        (ref.read(todayStateProvider).value == null || _pushOptInRewardBusy)) {
      _pushOptInRewardResumePending = true;
    }
  }

  Future<void> _settlePushOptInReward(
    PushOptInRewardRepository repository,
    PushNotificationService pushService,
    PushAuthorizationStatus authorization, {
    required bool appNotificationsEnabled,
  }) async {
    if (!mounted ||
        !_isLobbyVisible ||
        authorization != PushAuthorizationStatus.authorized ||
        !appNotificationsEnabled) {
      return;
    }
    final registered = await pushService
        .refreshTokenRegistration(
          ref.read(socialRepositoryProvider),
          appNotificationsEnabled: true,
        )
        .timeout(const Duration(seconds: 25), onTimeout: () => false);
    if (!registered || !mounted || !_isLobbyVisible) return;

    final claim = await repository.claimPushOptInReward().timeout(
      const Duration(seconds: 8),
    );
    if (mounted && claim.claimed) ref.invalidate(todayStateProvider);
    if (!mounted || !_isLobbyVisible || !claim.hasReward) return;

    final dialogContext = await _waitForDialogContext();
    if (dialogContext == null ||
        !dialogContext.mounted ||
        !mounted ||
        !_isLobbyVisible) {
      return;
    }
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => const _PushOptInRewardSuccessDialog(),
    );
  }

  void _handleForegroundPush(RemoteMessage message) {
    if (!mounted) return;
    debugPrint('[Push] Foreground message received: ${message.messageId}');
    if (_pushOptInRewardBusy || _startupModalFlowActive) {
      _socialInboxRefreshPending = true;
      return;
    }
    if (!_isLobbyVisible) {
      _socialInboxRefreshPending = true;
      return;
    }
    if (_socialInboxLoading) {
      _socialInboxRefreshPending = true;
      return;
    }
    unawaited(_showSocialInbox(force: true).then<void>((_) {}));
  }

  void _handlePushOpened(RemoteMessage message) {
    if (!mounted) return;
    debugPrint('[Push] Notification opened: ${message.messageId}');
    final notificationId = message.data['notification_id']?.toString();
    final eventKey = notificationId?.isNotEmpty == true
        ? notificationId!
        : message.messageId;
    if (eventKey != null &&
        eventKey.isNotEmpty &&
        !_handledPushKeys.add(eventKey)) {
      return;
    }
    _pushTapPending = true;
    // A push tap should land on the safe daily-game home first, then show the
    // same in-app inbox dialog used by foreground delivery. Reading the
    // notification is deferred until the user confirms that dialog so a tap
    // never loses the social message.
    final destination = pushDestinationPath(message.data);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(destination);
      unawaited(_showSocialInboxAfterPushTap());
    });
  }

  Future<void> _showSocialInboxAfterPushTap() async {
    if (!_mainPageVisible) {
      debugPrint(
        '[SocialInbox] Push tap queued until the home screen is ready',
      );
      return;
    }
    if (!_isLobbyVisible) {
      _socialInboxRefreshPending = true;
      return;
    }
    // Let go_router finish rebuilding the destination before presenting the
    // modal, especially on a cold launch from a terminated iOS app.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_socialInboxLoading) {
      // Startup may already be fetching the inbox when the initial FCM tap is
      // delivered. Queue one more fetch instead of dropping the tap while
      // the first request is in flight.
      _socialInboxRefreshPending = true;
      _pushTapPending = false;
      return;
    }

    // On a cold iOS launch the navigator can take more than one frame to be
    // attached after go_router changes location. Retry the inbox fetch rather
    // than silently returning with only the home screen visible.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted) return;
      final displayed = await _showSocialInbox(force: true);
      if (displayed) {
        _pushTapPending = false;
        return;
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    debugPrint('[SocialInbox] Push tap had no dialog to display after retries');
    _pushTapPending = false;
  }

  Future<BuildContext?> _waitForDialogContext() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted) return null;
      final navigator = rootNavigatorKey.currentState;
      final dialogContext =
          navigator?.overlay?.context ?? rootNavigatorKey.currentContext;
      if (dialogContext != null && dialogContext.mounted) return dialogContext;
      await WidgetsBinding.instance.endOfFrame;
      if (attempt < 11) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    return null;
  }

  Future<bool> _showSocialInbox({bool force = false}) async {
    if (_pushOptInRewardBusy) {
      _socialInboxRefreshPending = true;
      return false;
    }
    if (_socialInboxLoading || (_socialInboxRequested && !force)) return false;
    if (!_isLobbyVisible) {
      _socialInboxRefreshPending = true;
      return false;
    }
    _socialInboxRequested = true;
    _socialInboxLoading = true;
    final repository = ref.read(socialRepositoryProvider);
    var displayed = false;
    try {
      final notifications = await repository.fetchUnseenSocialNotifications();
      debugPrint(
        '[SocialInbox] fetched ${notifications.length} unseen notifications',
      );
      final orderedNotifications = [...notifications];
      final shownIds = <String>[];
      for (final notification in orderedNotifications) {
        if (!mounted || !_isLobbyVisible) {
          _socialInboxRefreshPending = true;
          return displayed;
        }
        final dialogContext = await _waitForDialogContext();
        if (dialogContext == null ||
            !mounted ||
            !_isLobbyVisible ||
            !dialogContext.mounted) {
          if (_isLobbyVisible == false) _socialInboxRefreshPending = true;
          debugPrint('[SocialInbox] navigator was not ready for the dialog');
          return displayed;
        }
        displayed = true;
        await showDialog<void>(
          context: dialogContext,
          builder: (_) => _SocialNotificationDialog(notification: notification),
        );
        shownIds.add(notification.id);
      }
      await repository.acknowledgeSocialNotifications(shownIds);
      if (orderedNotifications.any((item) => item.actionType == 'gift')) {
        ref.invalidate(todayStateProvider);
      }
      return displayed;
    } catch (error, stackTrace) {
      debugPrint('[SocialInbox] Failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return displayed;
    } finally {
      _socialInboxLoading = false;
      if (_socialInboxRefreshPending &&
          !_pushOptInRewardBusy &&
          mounted &&
          _isLobbyVisible) {
        _socialInboxRefreshPending = false;
        unawaited(_showSocialInbox(force: true).then<void>((_) {}));
      }
    }
  }

  void _handleTodayState(TodayState state) {
    final hasAdGatedChoice =
        (state.canChooseChallenge && state.requiresAdForChallenge) ||
        (state.canChoosePractice && state.requiresAdForPractice);
    if (!hasAdGatedChoice) {
      _preloadRequested = false;
      return;
    }
    if (!_mainPageVisible || _preloadRequested) return;
    _preloadRequested = true;
    unawaited(_preloadRewardedAd());
  }

  Future<void> _initializeRewardedAds() async {
    try {
      await _rewardedAdService.initialize();
    } catch (error, stackTrace) {
      debugPrint('[AdWarmup] Initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _preloadRewardedAd() async {
    try {
      await _rewardedAdService.preload();
    } catch (error, stackTrace) {
      _preloadRequested = false;
      debugPrint('[AdWarmup] Preload failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

class _SocialNotificationDialog extends StatelessWidget {
  const _SocialNotificationDialog({required this.notification});

  final SocialNotification notification;

  @override
  Widget build(BuildContext context) {
    final action = notification.actionType;
    final (title, icon, accent) = switch (action) {
      'poke' => ('콕! 찔렸어요', Icons.touch_app_rounded, AppColors.reward),
      'boast' => ('자랑 ON', Icons.emoji_events_rounded, AppColors.primary),
      'gift' => ('선물이 도착했어요!', Icons.card_giftcard_rounded, AppColors.reward),
      _ => ('새 알림', Icons.notifications_rounded, AppColors.primary),
    };

    return Dialog(
      key: action == 'boast' ? const Key('social-boast-dialog') : null,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: PixelPanel(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: 38),
              const SizedBox(height: 10),
              WordSafeText(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 22,
                  height: 1.3,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
                decoration: BoxDecoration(
                  color: AppColors.backgroundDeep,
                  border: Border.all(color: AppColors.surfaceLight),
                ),
                child: WordSafeText(
                  notification.message,
                  key: action == 'boast'
                      ? const Key('social-boast-message')
                      : null,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 15,
                    height: 1.55,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: PixelButton(
                  key: const Key('social-notification-confirm-button'),
                  label: '확인',
                  icon: Icons.check_rounded,
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

class _AppUpdateRewardDialog extends StatelessWidget {
  const _AppUpdateRewardDialog({required this.reward});

  final AppUpdateReward reward;

  @override
  Widget build(BuildContext context) {
    final tickets = reward.ticketsGranted;
    final ticketLabel = tickets == 1 ? '도전권 1장' : '도전권 $tickets장';
    return Dialog(
      key: const Key('app-update-reward-dialog'),
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: PixelPanel(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.card_giftcard_rounded,
                color: AppColors.reward,
                size: 44,
              ),
              const SizedBox(height: 10),
              const WordSafeText(
                '업데이트 감사 보상',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 22,
                  height: 1.3,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              WordSafeText(
                '${reward.message}\n$ticketLabel이 지급되었어요!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.backgroundDeep,
                  border: Border.all(color: AppColors.reward, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.confirmation_number_rounded,
                      color: AppColors.reward,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    WordSafeText(
                      ticketLabel,
                      style: const TextStyle(
                        color: AppColors.reward,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: PixelButton(
                  key: const Key('app-update-reward-confirm'),
                  label: '확인',
                  icon: Icons.check_rounded,
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

class _ChuseokGiftDialog extends StatefulWidget {
  const _ChuseokGiftDialog({required this.onClaim});

  final Future<ChuseokGiftClaim> Function() onClaim;

  @override
  State<_ChuseokGiftDialog> createState() => _ChuseokGiftDialogState();
}

class _ChuseokGiftDialogState extends State<_ChuseokGiftDialog> {
  var _claiming = false;
  ChuseokGiftClaim? _claim;
  String? _error;

  Future<void> _claimGift() async {
    if (_claiming || _claim != null) return;
    setState(() {
      _claiming = true;
      _error = null;
    });
    try {
      final claim = await widget.onClaim();
      if (!mounted) return;
      setState(() {
        _claiming = false;
        if (claim.completed || !claim.eligible) {
          _claim = claim;
        } else {
          _error = '선물을 받지 못했어요. 잠시 후 다시 눌러 주세요.';
        }
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      debugPrint('[ChuseokGift] Claim failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() {
        _claiming = false;
        _error = '선물을 받지 못했어요. 인터넷 연결을 확인하고 다시 눌러 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final claim = _claim;
    final completed = claim?.completed == true;
    final expired = claim != null && !claim.eligible;
    final title = completed ? '추석 선물을 받았어요!' : '즐거운 추석 되세요!';
    final message = completed
        ? '추석 선물로 도전권 1장을 받았어요.'
        : expired
        ? '추석 선물 기간이 끝났어요.'
        : '추석 선물로 도전권 1장을 준비했어요.';

    return Dialog(
      key: const Key('chuseok-gift-dialog'),
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: PixelPanel(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                completed || expired
                    ? Icons.card_giftcard_rounded
                    : Icons.celebration_rounded,
                color: AppColors.reward,
                size: 44,
              ),
              const SizedBox(height: 10),
              WordSafeText(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 22,
                  height: 1.3,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              WordSafeText(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!completed && !expired) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundDeep,
                    border: Border.all(color: AppColors.reward, width: 2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.confirmation_number_rounded,
                        color: AppColors.reward,
                        size: 24,
                      ),
                      SizedBox(width: 8),
                      WordSafeText(
                        '도전권 1장',
                        style: TextStyle(
                          color: AppColors.reward,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                WordSafeText(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: PixelButton(
                  key: Key(
                    completed || expired
                        ? 'chuseok-gift-confirm'
                        : 'chuseok-gift-claim',
                  ),
                  label: completed || expired
                      ? '확인'
                      : _claiming
                      ? '받는 중...'
                      : '도전권 받기',
                  icon: completed || expired
                      ? Icons.check_rounded
                      : Icons.card_giftcard_rounded,
                  onPressed: _claiming
                      ? null
                      : completed || expired
                      ? () => Navigator.of(context).pop()
                      : _claimGift,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PushOptInRewardDialog extends StatelessWidget {
  const _PushOptInRewardDialog({required this.denied});

  final bool denied;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('push-opt-in-reward-dialog'),
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: PixelPanel(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                color: AppColors.reward,
                size: 38,
              ),
              const SizedBox(height: 10),
              const WordSafeText(
                '알림 켜고 도전권 받기',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 22,
                  height: 1.3,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              const WordSafeText(
                '친구 선물과 랭킹 소식을 놓치지 않도록\n알림을 켜면 도전권 1장을 드려요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.backgroundDeep,
                  border: Border.all(color: AppColors.reward, width: 2),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sports_score_rounded,
                      color: AppColors.reward,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    WordSafeText(
                      '도전권 1장',
                      style: TextStyle(
                        color: AppColors.reward,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const WordSafeText(
                '보상은 계정당 한 번만 받을 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: PixelButton(
                  key: const Key('push-opt-in-reward-primary-button'),
                  label: denied ? '설정에서 알림 켜기' : '알림 켜고 받기',
                  icon: denied
                      ? Icons.settings_outlined
                      : Icons.notifications_active_outlined,
                  onPressed: () => Navigator.of(context).pop(
                    denied
                        ? _PushOptInRewardAction.openSettings
                        : _PushOptInRewardAction.enable,
                  ),
                ),
              ),
              TextButton(
                key: const Key('push-opt-in-reward-dismiss-button'),
                onPressed: () =>
                    Navigator.of(context).pop(_PushOptInRewardAction.dismiss),
                child: const WordSafeText('나중에'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PushOptInRewardSuccessDialog extends StatelessWidget {
  const _PushOptInRewardSuccessDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('push-opt-in-reward-success-dialog'),
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: PixelPanel(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.card_giftcard_rounded,
                color: AppColors.reward,
                size: 44,
              ),
              const SizedBox(height: 10),
              const WordSafeText(
                '도전권을 받았어요!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 22,
                  height: 1.3,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              const WordSafeText(
                '알림을 켜 주셔서 고마워요.\n도전권 1장을 선물했어요!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.backgroundDeep,
                  border: Border.all(color: AppColors.reward, width: 2),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sports_score_rounded,
                      color: AppColors.reward,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    WordSafeText(
                      '도전권 1장',
                      style: TextStyle(
                        color: AppColors.reward,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: PixelButton(
                  key: const Key('push-opt-in-reward-success-confirm'),
                  label: '확인',
                  icon: Icons.check_rounded,
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

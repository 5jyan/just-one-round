import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/startup_intro.dart';
import 'package:just_one_round/app/theme/app_theme.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/history/presentation/play_history_screen.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';

GoRouter createAppRouter({String initialLocation = '/'}) => GoRouter(
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
          _AppContent(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _AppContent extends ConsumerStatefulWidget {
  const _AppContent({required this.child});

  final Widget child;

  @override
  ConsumerState<_AppContent> createState() => _AppContentState();
}

class _AppContentState extends ConsumerState<_AppContent> {
  late final RewardedAdService _rewardedAdService;
  var _mainPageVisible = false;
  var _preloadRequested = false;

  @override
  void initState() {
    super.initState();
    _rewardedAdService = ref.read(rewardedAdServiceProvider);
    ref.listenManual(
      todayStateProvider,
      (_, next) => next.whenData(_handleTodayState),
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayStateProvider);
    return StartupIntro(
      ready: today.hasValue || today.hasError,
      onFinished: _handleStartupFinished,
      child: widget.child,
    );
  }

  void _handleStartupFinished() {
    if (_mainPageVisible) return;
    _mainPageVisible = true;
    unawaited(_initializeRewardedAds());
    final today = ref.read(todayStateProvider).value;
    if (today != null) _handleTodayState(today);
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

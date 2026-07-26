import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/startup_intro.dart';
import 'package:just_one_round/app/theme/app_theme.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/history/presentation/play_history_screen.dart';
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
      builder: (context, child) => Consumer(
        builder: (context, ref, _) {
          final today = ref.watch(todayStateProvider);
          return StartupIntro(
            ready: today.hasValue || today.hasError,
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

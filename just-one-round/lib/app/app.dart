import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_theme.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const TodayScreen()),
  ],
);

class JustOneRoundApp extends StatelessWidget {
  const JustOneRoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '딱한판만',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}

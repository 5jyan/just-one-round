import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/core/notifications/push_notification_route.dart';

void main() {
  testWidgets('duel notification destination is registered as an app route', (
    tester,
  ) async {
    final router = createAppRouter(initialLocation: duelLobbyRoutePath);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      duelLobbyRoutePath,
    );
  });
}

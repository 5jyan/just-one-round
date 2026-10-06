import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/core/notifications/push_notification_service.dart';
import 'package:just_one_round/core/notifications/push_opt_in_reward.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';

void main() {
  testWidgets('shows the opt-in reward and claims after permission succeeds', (
    tester,
  ) async {
    final repository = _PushOptInRewardRepository();
    final push = _FakePushNotificationService();
    await _pumpApp(tester, repository, push);

    expect(find.byKey(const Key('push-opt-in-reward-dialog')), findsOneWidget);
    expect(find.text('알림 켜고 도전권 받기'), findsOneWidget);
    expect(find.text('도전권 1장'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('push-opt-in-reward-primary-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.acceptedPromptCalls, 1);
    expect(repository.claimCalls, 1);
    expect(push.requestCalls, 1);
    expect(push.refreshCalls, 1);
    expect(
      find.byKey(const Key('push-opt-in-reward-success-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('does not prompt an authorized app-enabled account', (
    tester,
  ) async {
    final repository = _PushOptInRewardRepository();
    final push = _FakePushNotificationService(
      authorization: PushAuthorizationStatus.authorized,
    );
    await _pumpApp(tester, repository, push);

    expect(find.byKey(const Key('push-opt-in-reward-dialog')), findsNothing);
    expect(repository.promptCalls, 0);
    expect(repository.claimCalls, 0);
  });

  testWidgets('token registration failure keeps the reward unclaimed', (
    tester,
  ) async {
    final repository = _PushOptInRewardRepository();
    final push = _FakePushNotificationService(refreshSucceeds: false);
    await _pumpApp(tester, repository, push);

    await tester.tap(
      find.byKey(const Key('push-opt-in-reward-primary-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.claimCalls, 0);
    expect(
      find.byKey(const Key('push-opt-in-reward-success-dialog')),
      findsNothing,
    );
  });

  testWidgets(
    'settings return retries an accepted reward after authorization',
    (tester) async {
      final repository = _PushOptInRewardRepository();
      final settingsReturn = Completer<bool>();
      final push = _FakePushNotificationService(
        authorization: PushAuthorizationStatus.denied,
        settingsReturn: settingsReturn,
      );
      await _pumpApp(tester, repository, push);

      expect(
        find.byKey(const Key('push-opt-in-reward-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('push-opt-in-reward-primary-button')),
      );
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      push.authorization = PushAuthorizationStatus.authorized;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      settingsReturn.complete(true);
      await tester.pumpAndSettle();

      expect(repository.claimCalls, 1);
      expect(push.refreshCalls, 1);
      expect(
        find.byKey(const Key('push-opt-in-reward-success-dialog')),
        findsOneWidget,
      );
    },
  );

  testWidgets('an accepted account can receive the monthly denied reminder', (
    tester,
  ) async {
    final repository = _PushOptInRewardRepository(
      initialStatus: const PushOptInRewardStatus(
        shouldShow: true,
        accepted: true,
        claimed: false,
      ),
    );
    final push = _FakePushNotificationService(
      authorization: PushAuthorizationStatus.denied,
    );
    await _pumpApp(tester, repository, push);

    expect(find.byKey(const Key('push-opt-in-reward-dialog')), findsOneWidget);
    expect(repository.promptCalls, 1);
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  _PushOptInRewardRepository repository,
  _FakePushNotificationService push,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dailyGameRepositoryProvider.overrideWithValue(repository),
        pushNotificationServiceProvider.overrideWithValue(push),
      ],
      child: const JustOneRoundApp(),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

class _PushOptInRewardRepository extends PreviewDailyGameRepository {
  _PushOptInRewardRepository({PushOptInRewardStatus? initialStatus})
    : _status =
          initialStatus ??
          const PushOptInRewardStatus(
            shouldShow: true,
            accepted: false,
            claimed: false,
          );

  var promptCalls = 0;
  var acceptedPromptCalls = 0;
  var claimCalls = 0;
  PushOptInRewardStatus _status;

  @override
  Future<PushOptInRewardStatus> fetchPushOptInRewardStatus() async => _status;

  @override
  Future<PushOptInRewardStatus> recordPushOptInRewardPrompt({
    bool accepted = false,
  }) async {
    if (accepted) {
      acceptedPromptCalls += 1;
      _status = const PushOptInRewardStatus(
        shouldShow: true,
        accepted: true,
        claimed: false,
      );
    } else {
      promptCalls += 1;
    }
    return _status;
  }

  @override
  Future<PushOptInRewardClaim> claimPushOptInReward() async {
    claimCalls += 1;
    _status = const PushOptInRewardStatus(
      shouldShow: false,
      accepted: true,
      claimed: true,
    );
    return const PushOptInRewardClaim(
      claimed: true,
      granted: true,
      ticketsGranted: 1,
      challengeTickets: 1,
    );
  }
}

class _FakePushNotificationService implements PushNotificationService {
  _FakePushNotificationService({
    this.authorization = PushAuthorizationStatus.notDetermined,
    this.refreshSucceeds = true,
    this.settingsReturn,
  });

  PushAuthorizationStatus authorization;
  final bool refreshSucceeds;
  final Completer<bool>? settingsReturn;
  var requestCalls = 0;
  var refreshCalls = 0;

  @override
  bool get isAvailable {
    return true;
  }

  @override
  Future<PushAuthorizationStatus> getAuthorizationStatus() async =>
      authorization;

  @override
  Future<PushAuthorizationStatus> requestPermissionAndRegister(
    SocialRepository repository,
  ) async {
    requestCalls += 1;
    authorization = PushAuthorizationStatus.authorized;
    return authorization;
  }

  @override
  Future<bool> refreshTokenRegistration(
    SocialRepository repository, {
    bool appNotificationsEnabled = true,
  }) async {
    refreshCalls += 1;
    return refreshSucceeds &&
        appNotificationsEnabled &&
        authorization == PushAuthorizationStatus.authorized;
  }

  @override
  Future<bool> openNotificationSettings() {
    return settingsReturn?.future ?? Future<bool>.value(true);
  }
}

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';

const firebasePushEnabled = bool.fromEnvironment(
  'ENABLE_FIREBASE_PUSH',
  defaultValue: kReleaseMode || kProfileMode,
);

enum PushAuthorizationStatus {
  unavailable,
  notDetermined,
  authorized,
  provisional,
  denied,
}

extension PushAuthorizationStatusX on PushAuthorizationStatus {
  bool get canDisplayNotifications =>
      this == PushAuthorizationStatus.authorized ||
      this == PushAuthorizationStatus.provisional;

  bool get needsSystemSettings => this == PushAuthorizationStatus.denied;
}

const _notificationSettingsChannel = MethodChannel(
  'just_one_round/notification_settings',
);

// APNs registration can complete well after the permission callback on a
// freshly installed physical iPhone. Keep the registration work off the app
// startup path while giving iOS enough time to deliver the device token.
const _apnsTokenWaitAttempts = 30;
const _apnsTokenWaitInterval = Duration(milliseconds: 500);

/// Small seam for startup flows that need to verify the current device state
/// without coupling their UI tests to Firebase platform channels.
abstract interface class PushNotificationService {
  bool get isAvailable;

  Future<PushAuthorizationStatus> getAuthorizationStatus();

  Future<PushAuthorizationStatus> requestPermissionAndRegister(
    SocialRepository repository,
  );

  Future<bool> refreshTokenRegistration(
    SocialRepository repository, {
    bool appNotificationsEnabled = true,
  });

  Future<bool> openNotificationSettings();
}

final pushNotificationServiceProvider = Provider<PushNotificationService>(
  (ref) => const FirebasePushNotificationService(),
);

class FirebasePushNotificationService implements PushNotificationService {
  const FirebasePushNotificationService();

  @override
  bool get isAvailable =>
      firebasePushEnabled && !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Future<PushAuthorizationStatus> getAuthorizationStatus() =>
      getPushAuthorizationStatus();

  @override
  Future<PushAuthorizationStatus> requestPermissionAndRegister(
    SocialRepository repository,
  ) => requestPushPermissionAndRegister(repository);

  @override
  Future<bool> refreshTokenRegistration(
    SocialRepository repository, {
    bool appNotificationsEnabled = true,
  }) => refreshPushTokenRegistration(
    repository,
    appNotificationsEnabled: appNotificationsEnabled,
  );

  @override
  Future<bool> openNotificationSettings() => openPushNotificationSettings();
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('[Push] Background Firebase initialization failed: $error');
  }
}

Future<bool> _waitForApnsToken(FirebaseMessaging messaging) async {
  for (var attempt = 0; attempt < _apnsTokenWaitAttempts; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(_apnsTokenWaitInterval);
    }
    try {
      final token = await messaging.getAPNSToken();
      if (token != null && token.isNotEmpty) return true;
    } catch (error) {
      debugPrint('[Push] APNs token check failed: $error');
    }
  }
  debugPrint(
    '[Push] APNs token was not ready; FCM token registration deferred',
  );
  return false;
}

Future<FirebaseMessaging?> _messagingOrNull() async {
  if (!firebasePushEnabled ||
      kIsWeb ||
      (!Platform.isIOS && !Platform.isAndroid)) {
    return null;
  }
  try {
    await Firebase.initializeApp();
    return FirebaseMessaging.instance;
  } catch (error, stackTrace) {
    debugPrint('[Push] Firebase messaging is unavailable: $error');
    debugPrintStack(stackTrace: stackTrace);
    return null;
  }
}

PushAuthorizationStatus _authorizationStatus(AuthorizationStatus status) =>
    switch (status) {
      AuthorizationStatus.notDetermined =>
        PushAuthorizationStatus.notDetermined,
      AuthorizationStatus.authorized => PushAuthorizationStatus.authorized,
      AuthorizationStatus.provisional => PushAuthorizationStatus.provisional,
      AuthorizationStatus.denied => PushAuthorizationStatus.denied,
    };

Future<PushAuthorizationStatus> getPushAuthorizationStatus() async {
  final messaging = await _messagingOrNull();
  if (messaging == null) return PushAuthorizationStatus.unavailable;
  try {
    final settings = await messaging.getNotificationSettings();
    return _authorizationStatus(settings.authorizationStatus);
  } catch (error, stackTrace) {
    debugPrint('[Push] Notification permission lookup failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return PushAuthorizationStatus.unavailable;
  }
}

Future<PushAuthorizationStatus> requestPushPermissionAndRegister(
  SocialRepository repository,
) async {
  final messaging = await _messagingOrNull();
  if (messaging == null) return PushAuthorizationStatus.unavailable;

  try {
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final status = _authorizationStatus(settings.authorizationStatus);
    if (!status.canDisplayNotifications) return status;

    await refreshPushTokenRegistration(repository);
    return status;
  } catch (error, stackTrace) {
    debugPrint(
      '[Push] Permission request or token registration failed: $error',
    );
    debugPrintStack(stackTrace: stackTrace);
    return PushAuthorizationStatus.unavailable;
  }
}

/// Re-reads the system permission and registers the current FCM token.
///
/// Android can grant POST_NOTIFICATIONS in system settings after the app has
/// already initialized Firebase. In that case the token listener may have
/// fired before permission was granted, so the token must be fetched again on
/// the next app resume. The same refresh also keeps iOS registrations alive
/// after an APNs token rotation.
Future<bool> refreshPushTokenRegistration(
  SocialRepository repository, {
  bool appNotificationsEnabled = true,
}) async {
  final messaging = await _messagingOrNull();
  if (messaging == null) return false;

  try {
    final permission = await messaging.getNotificationSettings();
    final status = _authorizationStatus(permission.authorizationStatus);
    if (!status.canDisplayNotifications) {
      debugPrint(
        '[Push] Token refresh skipped; notification authorization is '
        '${permission.authorizationStatus}',
      );
      return false;
    }
    if (!appNotificationsEnabled) {
      debugPrint(
        '[Push] Token refresh skipped; app notification preference is off',
      );
      return false;
    }

    if (Platform.isIOS) {
      await registerForRemoteNotifications();
      if (!await _waitForApnsToken(messaging)) return false;
    }
    debugPrint('[Push] Requesting FCM token refresh');
    final token = await messaging.getToken().timeout(
      const Duration(seconds: 20),
    );
    debugPrint('[Push] FCM token refresh received');
    return _registerPushToken(
      repository: repository,
      platform: Platform.isIOS ? 'ios' : 'android',
      token: token,
    );
  } catch (error, stackTrace) {
    debugPrint('[Push] Token refresh failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  }
}

Future<bool> openPushNotificationSettings() async {
  if (!Platform.isIOS && !Platform.isAndroid) return false;
  try {
    return await _notificationSettingsChannel.invokeMethod<bool>('open') ??
        false;
  } catch (error, stackTrace) {
    debugPrint('[Push] Notification settings could not be opened: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  }
}

Future<bool> _registerPushToken({
  required SocialRepository repository,
  required String platform,
  required String? token,
}) async {
  if (token == null || token.isEmpty) {
    debugPrint('[Push] FCM token was empty; registration skipped');
    return false;
  }
  try {
    debugPrint('[Push] Registering FCM token for $platform');
    await repository.registerPushDevice(platform: platform, token: token);
    debugPrint('[Push] FCM token registration completed');
    return true;
  } catch (error, stackTrace) {
    debugPrint('[Push] Token registration failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  }
}

/// Initializes FCM when the build opts in and the native Firebase files exist.
/// Missing local credentials are caught so simulator and unit-test builds keep
/// working without production Firebase configuration.
Future<void> initializePushNotifications(
  SocialRepository repository, {
  void Function(RemoteMessage message)? onMessage,
  void Function(RemoteMessage message)? onMessageOpenedApp,
  bool appNotificationsEnabled = true,
}) async {
  if (!firebasePushEnabled ||
      kIsWeb ||
      (!Platform.isIOS && !Platform.isAndroid)) {
    return;
  }
  try {
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    if (Platform.isIOS) {
      // The app shows the fetched social inbox in the foreground. Suppress a
      // second iOS banner for the same FCM message.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    }
    // Permission is requested only after the app has given the user context
    // through the update prompt or notification setting action. Startup
    // otherwise only observes an already-granted permission.
    final permission = await messaging.getNotificationSettings();
    debugPrint(
      '[Push] Notification authorization: ${permission.authorizationStatus}',
    );
    final platform = Platform.isIOS ? 'ios' : 'android';
    if (onMessage != null) FirebaseMessaging.onMessage.listen(onMessage);
    if (onMessageOpenedApp != null) {
      FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpenedApp);
    }

    // Register listeners even before permission is granted. If the user
    // grants permission later from the settings action, the same app session
    // still receives foreground and tap callbacks.
    messaging.onTokenRefresh.listen(
      (newToken) {
        debugPrint('[Push] FCM token refresh received');
        unawaited(
          _registerPushToken(
            repository: repository,
            platform: platform,
            token: newToken,
          ).then<void>((_) {}),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[Push] Token refresh stream failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );

    // A notification tap is independent from APNs token registration. On a
    // cold iOS launch, waiting for APNs here can otherwise lose the initial
    // message before the app has a chance to route it.
    if (onMessageOpenedApp != null) {
      try {
        final initialMessage = await messaging.getInitialMessage().timeout(
          const Duration(seconds: 5),
        );
        if (initialMessage != null) onMessageOpenedApp(initialMessage);
      } catch (error, stackTrace) {
        debugPrint('[Push] Initial message lookup failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint(
        '[Push] Notification permission is not granted; token registration skipped',
      );
      return;
    }
    if (!appNotificationsEnabled) {
      debugPrint(
        '[Push] App notification preference is off; token registration skipped',
      );
      return;
    }
    await refreshPushTokenRegistration(
      repository,
      appNotificationsEnabled: appNotificationsEnabled,
    );
  } catch (error, stackTrace) {
    debugPrint('[Push] Initialization skipped: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

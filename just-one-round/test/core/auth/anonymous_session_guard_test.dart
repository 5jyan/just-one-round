import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/core/auth/anonymous_session_guard.dart';

void main() {
  test(
    'keeps an existing persisted session without signing in again',
    () async {
      var signInCalls = 0;
      final guard = AnonymousSessionGuard(
        hasSession: () => true,
        signInAnonymously: () async {
          signInCalls++;
        },
      );

      await guard.ensureSignedIn();
      await guard.ensureSignedIn();

      expect(signInCalls, 0);
    },
  );

  test('shares one anonymous sign-in between concurrent callers', () async {
    var hasSession = false;
    var signInCalls = 0;
    final signInCompleter = Completer<void>();
    final guard = AnonymousSessionGuard(
      hasSession: () => hasSession,
      signInAnonymously: () async {
        signInCalls++;
        await signInCompleter.future;
        hasSession = true;
      },
    );

    final first = guard.ensureSignedIn();
    final second = guard.ensureSignedIn();
    expect(signInCalls, 1);

    signInCompleter.complete();
    await Future.wait([first, second]);

    expect(signInCalls, 1);
  });

  test('allows a later retry when anonymous sign-in fails', () async {
    var hasSession = false;
    var signInCalls = 0;
    final guard = AnonymousSessionGuard(
      hasSession: () => hasSession,
      signInAnonymously: () async {
        signInCalls++;
        if (signInCalls == 1) throw StateError('offline');
        hasSession = true;
      },
    );

    await expectLater(guard.ensureSignedIn(), throwsStateError);
    await guard.ensureSignedIn();

    expect(signInCalls, 2);
    expect(hasSession, isTrue);
  });
}

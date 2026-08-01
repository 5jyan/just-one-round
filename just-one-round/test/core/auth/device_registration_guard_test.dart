import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/core/auth/device_registration_guard.dart';

void main() {
  test('registers a device only once for the same user', () async {
    var registrations = 0;
    final guard = DeviceRegistrationGuard(
      currentUserId: () => 'user-1',
      readDeviceHash: () async => 'device-hash',
      registerDevice: (deviceHash) async {
        expect(deviceHash, 'device-hash');
        registrations++;
      },
    );

    await guard.ensureRegistered();
    await guard.ensureRegistered();

    expect(registrations, 1);
  });

  test('registers the same device again after the account changes', () async {
    var userId = 'user-1';
    final registeredUsers = <String>[];
    final guard = DeviceRegistrationGuard(
      currentUserId: () => userId,
      readDeviceHash: () async => 'device-hash',
      registerDevice: (_) async => registeredUsers.add(userId),
    );

    await guard.ensureRegistered();
    userId = 'user-2';
    await guard.ensureRegistered();

    expect(registeredUsers, ['user-1', 'user-2']);
  });

  test('shares an in-flight registration between concurrent calls', () async {
    var registrations = 0;
    final completer = Completer<void>();
    final guard = DeviceRegistrationGuard(
      currentUserId: () => 'user-1',
      readDeviceHash: () async => 'device-hash',
      registerDevice: (_) async {
        registrations++;
        await completer.future;
      },
    );

    final first = guard.ensureRegistered();
    final second = guard.ensureRegistered();
    await Future<void>.delayed(Duration.zero);
    expect(registrations, 1);

    completer.complete();
    await Future.wait([first, second]);

    expect(registrations, 1);
  });

  test('registers again when the server-side association is lost', () async {
    var registrations = 0;
    final guard = DeviceRegistrationGuard(
      currentUserId: () => 'user-1',
      readDeviceHash: () async => 'device-hash',
      registerDevice: (_) async {
        registrations++;
      },
    );

    await guard.ensureRegistered();
    await guard.registerAgain();
    await guard.ensureRegistered();

    expect(registrations, 2);
  });
}

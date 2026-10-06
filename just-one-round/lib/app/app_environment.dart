import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _environmentChannel = MethodChannel('just_one_round/app_environment');
const _fallbackDeviceInstallIdKey = 'device_install_id';

class AppBuildInfo {
  const AppBuildInfo({
    required this.version,
    required this.buildNumber,
    required this.platform,
  });

  final String version;
  final int buildNumber;
  final String platform;
}

final appBuildInfoProvider = Provider<AppBuildInfo>(
  (ref) =>
      const AppBuildInfo(version: '1.0.4', buildNumber: 9, platform: 'unknown'),
);

const _unavailableAppBuildInfo = AppBuildInfo(
  version: 'unknown',
  buildNumber: 0,
  platform: 'unknown',
);

Future<bool> isIosSimulator() async {
  try {
    return await _environmentChannel
            .invokeMethod<bool>('isIosSimulator')
            .timeout(const Duration(seconds: 3)) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  } on TimeoutException {
    return false;
  }
}

Future<void> registerForRemoteNotifications() async {
  try {
    await _environmentChannel
        .invokeMethod<void>('registerForRemoteNotifications')
        .timeout(const Duration(seconds: 3));
  } on MissingPluginException {
    // Unsupported platforms and widget tests do not have the iOS channel.
  } on PlatformException {
    // A temporary platform-channel failure must not prevent app startup.
  } on TimeoutException {
    // APNs registration is retried by the messaging SDK on the next launch.
  }
}

Future<AppBuildInfo> readAppBuildInfo() async {
  try {
    final response = await _environmentChannel
        .invokeMapMethod<String, dynamic>('getAppBuildInfo')
        .timeout(const Duration(seconds: 3));
    final buildNumber = int.tryParse('${response?['build_number'] ?? ''}');
    return AppBuildInfo(
      version: response?['version'] as String? ?? 'unknown',
      buildNumber: buildNumber ?? 0,
      platform: response?['platform'] as String? ?? 'unknown',
    );
  } on MissingPluginException {
    return _unavailableAppBuildInfo;
  } on PlatformException {
    return _unavailableAppBuildInfo;
  } on TimeoutException {
    return _unavailableAppBuildInfo;
  }
}

Future<String> readDeviceInstallHash() async {
  String? installId;
  try {
    installId = await _environmentChannel
        .invokeMethod<String>('getDeviceInstallId')
        .timeout(const Duration(seconds: 3));
  } on MissingPluginException {
    // Widget tests and unsupported platforms use the local fallback below.
  } on PlatformException {
    // A temporary platform-channel failure must not prevent app startup.
  } on TimeoutException {
    // A stalled platform channel must not block account/device registration.
  }

  installId = installId?.trim();
  if (installId == null || installId.isEmpty) {
    final preferences = await SharedPreferences.getInstance();
    installId = preferences.getString(_fallbackDeviceInstallIdKey);
    if (installId == null || installId.isEmpty) {
      final random = Random.secure();
      installId = List<int>.generate(
        32,
        (_) => random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      await preferences.setString(_fallbackDeviceInstallIdKey, installId);
    }
  }

  return sha256.convert(utf8.encode(installId)).toString();
}

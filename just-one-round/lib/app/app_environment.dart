import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
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

Future<bool> isIosSimulator() async {
  try {
    return await _environmentChannel.invokeMethod<bool>('isIosSimulator') ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

Future<AppBuildInfo> readAppBuildInfo() async {
  try {
    final response = await _environmentChannel.invokeMapMethod<String, dynamic>(
      'getAppBuildInfo',
    );
    final buildNumber = int.tryParse('${response?['build_number'] ?? ''}');
    return AppBuildInfo(
      version: response?['version'] as String? ?? '1.0.0',
      buildNumber: buildNumber ?? 1,
      platform: response?['platform'] as String? ?? 'unknown',
    );
  } on MissingPluginException {
    return const AppBuildInfo(
      version: '1.0.0',
      buildNumber: 1,
      platform: 'unknown',
    );
  } on PlatformException {
    return const AppBuildInfo(
      version: '1.0.0',
      buildNumber: 1,
      platform: 'unknown',
    );
  }
}

Future<String> readDeviceInstallHash() async {
  String? installId;
  try {
    installId = await _environmentChannel.invokeMethod<String>(
      'getDeviceInstallId',
    );
  } on MissingPluginException {
    // Widget tests and unsupported platforms use the local fallback below.
  } on PlatformException {
    // A temporary platform-channel failure must not prevent app startup.
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

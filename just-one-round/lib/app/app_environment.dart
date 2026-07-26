import 'package:flutter/services.dart';

const _environmentChannel = MethodChannel('just_one_round/app_environment');

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

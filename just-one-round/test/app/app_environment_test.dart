import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const environmentChannel = MethodChannel('just_one_round/app_environment');
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    binaryMessenger.setMockMethodCallHandler(environmentChannel, null);
  });

  test('unavailable platform build info fails closed', () async {
    final info = await readAppBuildInfo();

    expect(info.version, 'unknown');
    expect(info.buildNumber, 0);
    expect(info.platform, 'unknown');
    expect(info.isFirebaseTestLab, isFalse);
  });

  test(
    'fallback device hash is stable and does not expose its source',
    () async {
      SharedPreferences.setMockInitialValues({});

      final first = await readDeviceInstallHash();
      final second = await readDeviceInstallHash();

      expect(first, hasLength(64));
      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(second, first);
    },
  );

  test('reads Firebase Test Lab detection from native build info', () async {
    binaryMessenger.setMockMethodCallHandler(environmentChannel, (call) async {
      expect(call.method, 'getAppBuildInfo');
      return <String, dynamic>{
        'version': '1.0.21',
        'build_number': '30',
        'platform': 'android',
        'is_firebase_test_lab': true,
      };
    });

    final info = await readAppBuildInfo();

    expect(info.isFirebaseTestLab, isTrue);
  });

  test('missing native Firebase Test Lab flag stays disabled', () async {
    binaryMessenger.setMockMethodCallHandler(environmentChannel, (call) async {
      return <String, dynamic>{
        'version': '1.0.21',
        'build_number': '30',
        'platform': 'android',
      };
    });

    final info = await readAppBuildInfo();

    expect(info.isFirebaseTestLab, isFalse);
  });
}

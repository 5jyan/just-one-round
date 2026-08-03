import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unavailable platform build info fails closed', () async {
    final info = await readAppBuildInfo();

    expect(info.version, 'unknown');
    expect(info.buildNumber, 0);
    expect(info.platform, 'unknown');
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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/core/auth/shared_test_profile.dart';

void main() {
  test('공용 테스트 프로필이 꺼져 있으면 자격 증명이 없어도 된다', () {
    const config = SharedTestProfileConfig(
      enabled: false,
      email: '',
      password: '',
    );

    expect(config.validate, returnsNormally);
  });

  test('공용 테스트 프로필은 이메일과 비밀번호를 모두 요구한다', () {
    const config = SharedTestProfileConfig(
      enabled: true,
      email: 'shared-device-test@justoneround.local',
      password: '',
    );

    expect(config.validate, throwsStateError);
  });

  test('완전한 공용 테스트 프로필 설정은 유효하다', () {
    const config = SharedTestProfileConfig(
      enabled: true,
      email: 'shared-device-test@justoneround.local',
      password: 'local-only-password',
    );

    expect(config.validate, returnsNormally);
  });
}

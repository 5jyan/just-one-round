import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/profile/domain/nickname_policy.dart';

void main() {
  test('정상 닉네임을 허용한다', () {
    expect(NicknamePolicy.validate('말랑주먹'), isNull);
    expect(NicknamePolicy.validate('player42'), isNull);
  });

  test('욕설과 연락처를 차단한다', () {
    expect(NicknamePolicy.validate('씨 발'), isNotNull);
    expect(NicknamePolicy.validate('010-1234-5678'), isNotNull);
    expect(NicknamePolicy.validate('hello@example.com'), isNotNull);
  });

  test('길이와 반복 입력을 제한한다', () {
    expect(NicknamePolicy.validate('한'), isNotNull);
    expect(NicknamePolicy.validate('ㅋㅋㅋㅋㅋ'), isNotNull);
  });

  test('자동 발급 닉네임 형식은 직접 사용할 수 없다', () {
    expect(NicknamePolicy.validate('신원미상#123'), isNotNull);
    expect(NicknamePolicy.validate('신원미상'), isNull);
  });
}

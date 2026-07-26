import 'package:characters/characters.dart';

class NicknamePolicy {
  const NicknamePolicy._();

  static const _blockedFragments = [
    '시발',
    '씨발',
    'ㅅㅂ',
    '병신',
    '개새끼',
    '좆',
    '섹스',
    'sex',
    'fuck',
    'nigger',
  ];

  static String? validate(String? value) {
    final nickname = value?.trim() ?? '';
    final length = nickname.characters.length;
    if (length < 2 || length > 12) return '2~12자로 입력해 주세요.';

    final normalized = nickname.toLowerCase().replaceAll(
      RegExp(r'[\s._\-]'),
      '',
    );
    if (_blockedFragments.any(normalized.contains)) {
      return '사용할 수 없는 표현이 포함되어 있어요.';
    }
    if (RegExp(r'https?://|www\.|@').hasMatch(nickname) ||
        RegExp(r'01[016789][\s-]?\d{3,4}[\s-]?\d{4}').hasMatch(nickname)) {
      return '연락처나 인터넷 주소는 닉네임으로 사용할 수 없어요.';
    }
    if (RegExp(r'(.)\1{4,}').hasMatch(nickname)) {
      return '같은 글자를 지나치게 반복할 수 없어요.';
    }
    return null;
  }
}

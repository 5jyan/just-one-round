import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/game_registry.dart';

void main() {
  test('등록된 게임 ID로 게임 정의를 찾는다', () {
    final definition = GameRegistry.forId('dung_dodge_v2');

    expect(definition.id, 'dung_dodge_v2');
    expect(definition.scoreLabel, 'SURVIVAL TIME');
  });

  test('알 수 없는 게임은 지원하지 않는 버전으로 처리한다', () {
    expect(
      () => GameRegistry.forId('unknown'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('똥피하기는 기존 생존 규칙을 그대로 사용한다', () {
    final definition = GameRegistry.forId('dung_dodge_v2');

    expect(definition.id, 'dung_dodge_v2');
    expect(definition.scoreLabel, 'SURVIVAL TIME');
    expect(definition.formatScore(12345), '12.35초');
    expect(definition.defaultDuration, const Duration(minutes: 5));
  });

  test('중력 스위치 게임을 선택한다', () {
    final definition = GameRegistry.forId('gravity_switch');

    expect(definition.id, 'gravity_switch');
    expect(definition.countdownInstruction, contains('중력'));
  });

  test('비운 게임 ID는 더 이상 실행하지 않는다', () {
    for (final id in [
      'star_dodge',
      'dung_dodge',
      'failed_bakery',
      'apple_game',
    ]) {
      expect(() => GameRegistry.forId(id), throwsA(isA<UnsupportedError>()));
    }
  });

  test('비운 게임의 과거 기록 형식은 유지한다', () {
    expect(GameRegistry.formatScore('failed_bakery', 27), '27층');
    expect(GameRegistry.formatScore('apple_game', 42), '42개');
    expect(GameRegistry.formatScore('star_dodge', 12345), '12.35초');
  });

  test('사과게임은 기존 규칙과 별도 에셋 세트를 사용한다', () {
    final definition = GameRegistry.forId('apple_game_v2');

    expect(definition.id, 'apple_game_v2');
    expect(definition.scoreLabel, 'APPLES');
    expect(definition.formatScore(42), '42개');
    expect(definition.countdownInstruction, contains('합을 10'));
    expect(definition.defaultDuration, const Duration(seconds: 120));
    expect(definition.hudStyle.name, 'appleGame');
  });

  test('탭50은 완주 시간을 소수점 둘째 자리로 표시한다', () {
    final definition = GameRegistry.forId('number_rush');

    expect(definition.id, 'number_rush');
    expect(definition.scoreLabel, 'CLEAR TIME');
    expect(definition.formatScore(3590123), '9.88초');
    expect(definition.hudStyle.name, 'numberRush');
    expect(definition.countdownInstruction, contains('1부터 50'));
    expect(definition.defaultDuration, const Duration(minutes: 3));
  });
}

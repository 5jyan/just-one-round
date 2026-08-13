import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/game_registry.dart';

void main() {
  test('등록된 모든 게임에 직관적인 한 줄 시작 설명이 있다', () {
    for (final id in GameRegistry.registeredIds) {
      final instruction = GameRegistry.forId(id).startInstruction;
      expect(instruction.trim(), isNotEmpty, reason: id);
      expect(instruction.contains('\n'), isFalse, reason: id);
    }

    expect(
      GameRegistry.forId('ramen_timer').startInstruction,
      '본인의 직감으로 10초·20초·30초에 버튼을 누르세요!',
    );
    expect(
      GameRegistry.forId('apple_game_v2').startInstruction,
      '사과를 드래그해 숫자의 합을 10으로 만드세요!',
    );
  });

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
    expect(definition.formatHudScore(12345), '12.35');
    expect(definition.defaultDuration, const Duration(minutes: 5));
    expect(definition.hudStyle.name, 'survivalTime');
  });

  test('중력 스위치 게임을 선택한다', () {
    final definition = GameRegistry.forId('gravity_switch');

    expect(definition.id, 'gravity_switch');
    expect(definition.countdownInstruction, contains('중력'));
    expect(definition.formatHudScore(12345), '12.35');
    expect(definition.defaultDuration, const Duration(minutes: 5));
    expect(definition.hudStyle.name, 'survivalTime');
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

  test('게임 ID와 버전을 함께 검사한다', () {
    expect(GameRegistry.supports('number_rush', 1), isTrue);
    expect(GameRegistry.supports('number_rush', 2), isFalse);
    expect(GameRegistry.supports('future_game', 1), isFalse);
  });

  test('비운 게임의 과거 기록 형식은 유지한다', () {
    expect(GameRegistry.formatScore('failed_bakery', 27), '27층');
    expect(GameRegistry.formatScore('apple_game', 42), '42개');
    expect(GameRegistry.formatScore('star_dodge', 12345), '12.35초');
    expect(GameRegistry.formatScore('sausage_dachshund', 12), '12개');
  });

  test('사과게임은 기존 규칙과 별도 에셋 세트를 사용한다', () {
    final definition = GameRegistry.forId('apple_game_v2');

    expect(definition.id, 'apple_game_v2');
    expect(definition.scoreLabel, 'APPLES');
    expect(definition.formatScore(42), '42개');
    expect(definition.countdownInstruction, contains('합을 10'));
    expect(definition.defaultDuration, const Duration(seconds: 140));
    expect(definition.hudStyle.name, 'appleGame');
  });

  test('탭50은 완주 시간을 소수점 둘째 자리로 표시한다', () {
    final definition = GameRegistry.forId('number_rush');

    expect(definition.id, 'number_rush');
    expect(definition.scoreLabel, 'CLEAR TIME');
    expect(definition.formatScore(3590123), '9.88초');
    expect(definition.formatScore(0), '0점');
    expect(definition.hudStyle.name, 'numberRush');
    expect(definition.countdownInstruction, contains('1부터 50'));
    expect(definition.defaultDuration, const Duration(minutes: 3));
  });

  test('엄마 어디가는 120초 경로 점수전을 사용한다', () {
    final definition = GameRegistry.forId('mama_duck_trail');

    expect(definition.id, 'mama_duck_trail');
    expect(definition.scoreLabel, 'TRAIL SCORE');
    expect(definition.formatScore(12345), '12,345점');
    expect(definition.formatHudScore(12345), '12,345');
    expect(definition.defaultDuration, const Duration(seconds: 120));
    expect(definition.countdownInstruction, contains('발자국'));
    expect(definition.hudStyle.name, 'mamaDuckTrail');
    expect(GameRegistry.supports('mama_duck_trail', 1), isTrue);
  });

  test('야식털이 뱀은 최대 5분 음식 개수 점수전을 사용한다', () {
    final definition = GameRegistry.forId('midnight_snake');

    expect(definition.id, 'midnight_snake');
    expect(definition.scoreLabel, 'MIDNIGHT SNACKS');
    expect(definition.formatScore(12), '12개');
    expect(definition.formatHudScore(12), '12');
    expect(definition.defaultDuration, const Duration(minutes: 5));
    expect(definition.countdownInstruction, contains('스와이프'));
    expect(GameRegistry.supports('midnight_snake', 2), isTrue);
    expect(GameRegistry.supports('midnight_snake', 1), isFalse);
  });

  test('블랙잭은 10라운드 코인 점수전을 사용한다', () {
    final definition = GameRegistry.forId('beat_the_dealer');

    expect(definition.id, 'beat_the_dealer');
    expect(definition.scoreLabel, 'COINS');
    expect(definition.formatScore(125), '125코인');
    expect(definition.defaultDuration, const Duration(minutes: 3));
    expect(definition.countdownInstruction, contains('공개 카드'));
    expect(definition.hudStyle.name, 'beatTheDealer');
    expect(GameRegistry.supports('beat_the_dealer', 3), isTrue);
    expect(GameRegistry.supports('beat_the_dealer', 2), isFalse);
    expect(GameRegistry.supports('beat_the_dealer', 1), isFalse);
  });

  test('홈런왕은 제한시간 표시 없는 최대 비거리 점수전이다', () {
    final definition = GameRegistry.forId('ten_pitch_slugger');

    expect(definition.scoreLabel, 'MAX DISTANCE');
    expect(definition.formatScore(15000), '150.00m');
    expect(definition.defaultDuration, const Duration(seconds: 300));
    expect(definition.hudStyle.name, 'tenPitchSlugger');
    expect(definition.countdownInstruction, contains('언제든 탭'));
    expect(GameRegistry.supports('ten_pitch_slugger', 7), isTrue);
    expect(GameRegistry.supports('ten_pitch_slugger', 6), isFalse);
    expect(GameRegistry.supports('ten_pitch_slugger', 5), isFalse);
    expect(GameRegistry.supports('ten_pitch_slugger', 4), isFalse);
    expect(GameRegistry.supports('ten_pitch_slugger', 3), isFalse);
    expect(GameRegistry.supports('ten_pitch_slugger', 2), isFalse);
    expect(GameRegistry.supports('ten_pitch_slugger', 1), isFalse);
  });

  test('30초 컵라면은 45초 안에 세 시각의 총 오차를 경쟁한다', () {
    final definition = GameRegistry.forId('ramen_timer');

    expect(definition.scoreLabel, 'TOTAL ERROR');
    expect(definition.formatScore(3599410), '총 오차 0.59초');
    expect(definition.formatScore(0), '시간 초과');
    expect(definition.defaultDuration, const Duration(seconds: 45));
    expect(definition.hudStyle.name, 'ramenTimer');
    expect(definition.countdownInstruction, contains('처음 3초'));
    expect(GameRegistry.supports('ramen_timer', 3), isTrue);
    expect(GameRegistry.supports('ramen_timer', 2), isFalse);
    expect(GameRegistry.supports('ramen_timer', 1), isFalse);
  });
}

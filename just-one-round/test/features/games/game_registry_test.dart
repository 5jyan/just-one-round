import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/game_registry.dart';

void main() {
  test('등록된 게임 ID로 게임 정의를 찾는다', () {
    final definition = GameRegistry.forId('dung_dodge');

    expect(definition.id, 'dung_dodge');
    expect(definition.scoreLabel, 'SURVIVAL TIME');
  });

  test('알 수 없는 게임은 기본 게임으로 안전하게 대체한다', () {
    expect(GameRegistry.forId('unknown').id, GameRegistry.fallbackGameId);
  });

  test('똥피하기 2는 기존 생존 규칙을 그대로 사용한다', () {
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

  test('대충 케이크 게임을 층수 점수로 선택한다', () {
    final definition = GameRegistry.forId('failed_bakery');

    expect(definition.id, 'failed_bakery');
    expect(definition.scoreLabel, 'CAKE TOWER');
    expect(definition.formatScore(27), '27층');
    expect(definition.hudStyle, MiniGameHudStyle.failedBakery);
  });

  test('사과게임을 제거한 사과 수 점수로 선택한다', () {
    final definition = GameRegistry.forId('apple_game');

    expect(definition.id, 'apple_game');
    expect(definition.scoreLabel, 'APPLES');
    expect(definition.formatScore(42), '42개');
    expect(definition.countdownInstruction, contains('합을 10'));
    expect(definition.defaultDuration, const Duration(seconds: 120));
  });

  test('사과게임 2는 기존 규칙과 별도 에셋 세트를 사용한다', () {
    final definition = GameRegistry.forId('apple_game_v2');

    expect(definition.id, 'apple_game_v2');
    expect(definition.scoreLabel, 'APPLES');
    expect(definition.formatScore(42), '42개');
    expect(definition.countdownInstruction, contains('합을 10'));
    expect(definition.defaultDuration, const Duration(seconds: 120));
    expect(definition.hudStyle, MiniGameHudStyle.appleGame);
  });

  test('넘버 러시는 완주 시간을 소수점 둘째 자리로 표시한다', () {
    final definition = GameRegistry.forId('number_rush');

    expect(definition.id, 'number_rush');
    expect(definition.scoreLabel, 'CLEAR TIME');
    expect(definition.formatScore(3590123), '9.88초');
    expect(definition.hudStyle, MiniGameHudStyle.numberRush);
    expect(definition.countdownInstruction, contains('1부터 50'));
    expect(definition.defaultDuration, const Duration(minutes: 3));
  });
}

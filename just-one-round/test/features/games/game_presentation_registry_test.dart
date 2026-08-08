import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_registry.dart';

void main() {
  test('모든 실행 가능한 게임에 메인 화면 설정이 존재한다', () {
    final presentationIds = GamePresentationRegistry.all
        .map((definition) => definition.id)
        .toSet();

    expect(presentationIds, GameRegistry.registeredIds);
  });

  test('모든 활성 게임 설명서는 3~7페이지이며 필수 내용이 있다', () {
    for (final definition in GamePresentationRegistry.all) {
      expect(
        definition.guidePages.length,
        inInclusiveRange(3, 7),
        reason: definition.id,
      );
      expect(definition.loadingLabel.trim(), isNotEmpty, reason: definition.id);
      expect(
        definition.durationLabel.trim(),
        isNotEmpty,
        reason: definition.id,
      );
      expect(
        definition.guideDurationText.trim(),
        isNotEmpty,
        reason: definition.id,
      );
      for (final page in definition.guidePages) {
        expect(page.title.trim(), isNotEmpty, reason: definition.id);
        expect(page.description.trim(), isNotEmpty, reason: definition.id);
      }
    }
  });

  test('게임별 시작 준비 문구를 화면 설정에서 제공한다', () {
    expect(
      GamePresentationRegistry.forId('apple_game_v2').loadingLabel,
      '사과나무 심는 중...',
    );
    expect(
      GamePresentationRegistry.forId('dung_dodge_v2').loadingLabel,
      '화장실 가는 중...',
    );
    expect(
      GamePresentationRegistry.forId('gravity_switch').loadingLabel,
      '고철 수집 중...',
    );
    expect(
      GamePresentationRegistry.forId('number_rush').loadingLabel,
      '오락실 가는 중...',
    );
  });

  test('사과게임 메인 화면은 세로형 실기 캡처 비율을 사용한다', () {
    final presentation = GamePresentationRegistry.forId('apple_game_v2');

    expect(presentation.homeAspectRatio, 0.78);
    expect(presentation.durationLabel, '2분 20초');
    expect(presentation.guideDurationText, '2분 20초 동안 도전할 수 있어요.');
  });

  test('중력 스위치와 탭50 설명서는 시간 종료 규칙을 정확히 안내한다', () {
    final gravity = GamePresentationRegistry.forId('gravity_switch');
    final numberRush = GamePresentationRegistry.forId('number_rush');

    expect(gravity.durationLabel, '최대 5분');
    expect(gravity.guideDurationText, contains('5분'));
    expect(gravity.guidePages.last.description, contains('최대 5분'));
    expect(numberRush.guidePages.last.detail, contains('0점'));
  });

  test('엄마 어디가는 120초와 목숨 3개를 안내한다', () {
    final presentation = GamePresentationRegistry.forId('mama_duck_trail');

    expect(presentation.durationLabel, '120초');
    expect(presentation.guideDurationText, contains('목숨 3개'));
    expect(presentation.guidePages.last.title, '목숨은 3개');
    expect(presentation.guidePages.last.description, contains('120초'));
  });

  test('알 수 없는 ID는 지원하지 않는 화면으로 처리한다', () {
    expect(
      () => GamePresentationRegistry.forId('unknown'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('야식털이 뱀 화면은 5분과 예약 입력 규칙을 안내한다', () {
    final presentation = GamePresentationRegistry.forId('midnight_snake');

    expect(presentation.durationLabel, '최대 5분');
    expect(presentation.guideDurationText, contains('5분'));
    expect(presentation.guidePages, hasLength(4));
    expect(presentation.guidePages.first.description, contains('짧게'));
    expect(presentation.guidePages[2].description, contains('최대 3개'));
    expect(presentation.guidePages.last.detail, contains('5분'));
  });

  test('30초 컵라면 설명서는 세 탭·가림·결과 공개 순서로 안내한다', () {
    final presentation = GamePresentationRegistry.forId('ramen_timer');

    expect(presentation.durationLabel, '약 30초 · 최대 45초');
    expect(presentation.guidePages, hasLength(3));
    expect(presentation.guidePages.first.description, contains('체감 10초'));
    expect(presentation.guidePages.first.description, contains('20초'));
    expect(presentation.guidePages.first.description, contains('30초'));
    expect(presentation.guidePages[1].description, contains('처음 3초'));
    expect(presentation.guidePages[1].description, contains('증기'));
    expect(presentation.guidePages[1].detail, contains('12~13초'));
    expect(presentation.guidePages[1].detail, contains('22~23초'));
    expect(presentation.guidePages.last.description, contains('총 오차'));
    expect(presentation.guidePages.last.detail, contains('45초'));
  });
}

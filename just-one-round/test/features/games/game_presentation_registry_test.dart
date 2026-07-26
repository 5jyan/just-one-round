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
    expect(
      GamePresentationRegistry.forId('apple_game_v2').homeAspectRatio,
      0.78,
    );
  });

  test('알 수 없는 ID는 지원하지 않는 화면으로 처리한다', () {
    expect(
      () => GamePresentationRegistry.forId('unknown'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

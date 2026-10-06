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
    expect(numberRush.guidePages[1].detail, contains('3초'));
    expect(numberRush.guidePages[1].detail, contains('점멸'));
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
    expect(presentation.guidePages.first.description, contains('네 방향 버튼'));
    expect(presentation.guidePages[2].description, contains('최대 3개'));
    expect(presentation.guidePages.last.detail, contains('5분'));
  });

  test('30초 컵라면 설명서는 세 탭·가림·결과 공개 순서로 안내한다', () {
    final presentation = GamePresentationRegistry.forId('ramen_timer');

    expect(presentation.durationLabel, '약 30초 · 최대 45초');
    expect(presentation.guidePages, hasLength(3));
    expect(presentation.guidePages.first.description, contains('10초'));
    expect(presentation.guidePages.first.description, contains('20초'));
    expect(presentation.guidePages.first.description, contains('30초'));
    expect(presentation.guidePages[1].description, contains('처음 3초'));
    final copy = presentation.guidePages
        .map((page) => '${page.description} ${page.detail}')
        .join(' ');
    expect(copy, contains('오차'));
    expect(copy, isNot(contains('12~13초')));
    expect(copy, isNot(contains('22~23초')));
    expect(presentation.guidePages.last.description, contains('총 오차'));
    expect(presentation.guidePages.last.detail, contains('45초'));
  });

  test('남탕 여탕 설명서는 성별·동물 도감·시간 변화·콤보 점수를 안내한다', () {
    final presentation = GamePresentationRegistry.forId('bathhouse_sort');

    expect(presentation.durationLabel, '60초');
    expect(presentation.guidePages, hasLength(4));
    expect(presentation.guidePages.first.description, contains('남자 동물은 남탕'));
    expect(presentation.guidePages.first.detail, contains('연속 탭'));
    expect(presentation.guidePages[1].description, contains('흑곰'));
    expect(presentation.guidePages[1].description, contains('치즈 고양이'));
    expect(presentation.guidePages[1].detail, contains('남자는 파란 옷'));
    expect(presentation.guidePages[1].detail, contains('여자는 빨간 옷'));
    expect(presentation.guidePages[2].description, contains('종류가 하나씩 늘어나'));
    expect(presentation.guidePages[2].detail, contains('15·30·45초'));
    expect(presentation.guidePages[2].detail, contains('멈추지'));
    expect(presentation.guidePages.last.description, contains('콤보'));
    expect(presentation.guidePages.last.detail, contains('27콤보'));
    expect(presentation.guidePages.last.detail, contains('360점'));
    expect(presentation.guidePages.last.detail, contains('판이 소진'));
  });

  test('빙글개굴 설명서는 접선·가속·점수와 한 번 실패를 여섯 장으로 안내한다', () {
    final presentation = GamePresentationRegistry.forId('lily_frog');

    expect(presentation.durationLabel, contains('150초'));
    expect(presentation.homeAspectRatio, 0.78);
    expect(presentation.guidePages, hasLength(6));
    expect(presentation.guidePages.first.description, contains('90°'));
    expect(presentation.guidePages.first.detail, contains('점선을 따라 실제로'));
    expect(presentation.guidePages[1].description, contains('첫 3번'));
    expect(presentation.guidePages[1].detail, contains('4번째 점프부터'));
    expect(presentation.guidePages[2].description, contains('2.80'));
    expect(presentation.guidePages[2].detail, contains('2.24초'));
    expect(presentation.guidePages[3].description, contains('기본 300점'));
    expect(presentation.guidePages[3].description, contains('콤보×10점'));
    expect(presentation.guidePages[3].description, contains('1,000점'));
    expect(presentation.guidePages[3].detail, contains('게이지가 비기 전에'));
    expect(presentation.guidePages[4].description, contains('연잎 5개마다'));
    expect(presentation.guidePages[4].detail, contains('황금 선택 구간이 아닌'));
    expect(presentation.guidePages[4].detail, contains('+100점'));
    expect(presentation.guidePages.last.description, contains('바로 제출'));
    expect(presentation.guidePages.last.description, contains('150초'));
    expect(presentation.guidePages.last.detail, contains('앱을 닫아도'));
  });

  test('만선호는 조작·포획·실패·점수·그물 한계를 다섯 장으로 안내한다', () {
    final presentation = GamePresentationRegistry.forId('net_boat');

    expect(presentation.durationLabel, contains('300초'));
    expect(presentation.homeAspectRatio, 0.78);
    expect(presentation.guidePages, hasLength(5));
    expect(
      presentation.guidePages[0].description,
      contains('무조건 오른쪽으로 정확히 90°'),
    );
    expect(presentation.guidePages[1].description, contains('그물을 이어 사각형'));
    expect(
      presentation.guidePages[1].visual,
      presentation.guidePages[0].visual,
    );
    expect(presentation.guidePages[1].detail, contains('고래는 그물을 통과할 수 있어요'));
    expect(presentation.guidePages[2].title, '정어리는 안전해요');
    expect(presentation.guidePages[2].description, contains('바깥 돌 벽'));
    expect(presentation.guidePages[2].detail, contains('절대 게임이 끝나지 않아요'));
    expect(presentation.guidePages[3].description, contains('고래 2,500점'));
    expect(presentation.guidePages[3].detail, contains('위협적이지 않아요'));
    expect(presentation.guidePages[4].description, contains('최대 1000'));
    expect(presentation.guidePages[4].detail, contains('고래는 그물을 통과할 수 있어요'));
  });
}

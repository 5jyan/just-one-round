import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/mama_duck_trail/presentation/mama_duck_trail_presentation.dart';

void main() {
  test('가이드는 첫 7칸, 성공 증가, 엄마 도착지와 즉시 목숨 차감을 설명한다', () {
    final pages = mamaDuckTrailPresentation.guidePages;
    final copy = pages
        .expand((page) => [page.title, page.description, page.detail])
        .join(' ');

    expect(pages, hasLength(3));
    expect(copy, contains('첫 길은 7칸'));
    expect(copy, contains('성공할 때마다 한 칸'));
    expect(copy, contains('엄마는 마지막 칸'));
    expect(copy, contains('첫 길부터 바로 목숨'));
    expect(pages.last.title, '목숨은 3개');
    expect(pages.last.description, contains('목숨 3개'));
    expect(pages.last.description, contains('120초'));
    expect(copy, isNot(contains('오리 세 마리를 지키기')));
    expect(copy, contains('홈 이동이나 앱 중단'));
  });
}

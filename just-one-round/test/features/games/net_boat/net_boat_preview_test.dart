import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/net_boat/presentation/net_boat_preview.dart';

void main() {
  test('홈 반복 경계에서 배·그물·점수·시간이 함께 초기화된다', () {
    final beforeReset = NetBoatPreviewFrame.fromCycle(0.99);
    final afterReset = NetBoatPreviewFrame.fromCycle(1.0);

    expect(beforeReset.captured, isTrue);
    expect(beforeReset.score, 2500);
    expect(afterReset.captured, isFalse);
    expect(afterReset.score, 0);
    expect(afterReset.secondsLeft, 166);
    expect(afterReset.net, hasLength(1));
  });

  testWidgets('홈·가이드 프리뷰는 실제 에셋을 로드하고 경계 안에 그린다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 410,
          child: NetBoatPreview(
            scene: NetBoatPreviewScene.home,
            animate: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('net-boat-preview-clip')), findsOneWidget);
    expect(find.byKey(const Key('net-boat-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('조작 가이드 플레이 영상은 두 번의 전체 루프 동안 안정적으로 반복된다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 410,
          child: NetBoatPreview(scene: NetBoatPreviewScene.turn),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 5200));
    expect(find.byKey(const Key('net-boat-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 5200));
    expect(find.byKey(const Key('net-boat-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

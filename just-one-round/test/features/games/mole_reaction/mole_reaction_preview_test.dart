import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/mole_reaction/mole_reaction_hole_clip.dart';
import 'package:just_one_round/features/games/mole_reaction/presentation/mole_reaction_preview.dart';

void main() {
  testWidgets('미리보기의 두더지는 구멍 앞 흙선에서 잘린다', (tester) async {
    const width = 320.0;
    const height = 410.0;

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: MoleReactionPreview(),
          ),
        ),
      ),
    );

    final sprite = find.byKey(const Key('mole-reaction-visible-sprite'));
    expect(sprite, findsOneWidget);
    expect(tester.getSize(sprite).width, closeTo(width * 0.27, 0.01));
    expect(tester.getSize(sprite).height, closeTo(width * 0.27, 0.01));
  });

  test('두더지 클립은 흙 앞면 마지막 픽셀에서 닫힌다', () {
    final bounds = moleReactionMoleClipPath(
      const ui.Rect.fromLTWH(10, 20, 96, 96),
    ).getBounds();

    expect(bounds.left, 10);
    expect(bounds.right, 106);
    expect(bounds.top, 20);
    expect(bounds.bottom, closeTo(92, 0.001));
  });

  testWidgets('모든 설명 장면은 짧은 가이드 슬롯에서도 보드와 패널을 함께 그린다', (tester) async {
    for (final scene in MoleReactionPreviewScene.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 300,
              child: MoleReactionPreview(scene: scene),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('mole-reaction-preview')), findsOneWidget);
      expect(
        find.byKey(const Key('mole-reaction-visible-sprite')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

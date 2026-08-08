import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_presentation.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_preview.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_scene.dart';

void main() {
  test(
    'five guide pages cover input, timing, magic, score, and interruption',
    () {
      final pages = tenPitchSluggerPresentation.guidePages;
      final copy = pages
          .expand((page) => [page.title, page.description, page.detail])
          .join(' ');

      expect(pages, hasLength(5));
      expect(copy, contains('화면 아무 곳이나 탭'));
      expect(copy, contains('공을 던지기 전부터'));
      expect(copy, contains('0.3초마다 계속 탭'));
      expect(copy, contains('방망이 끝'));
      expect(copy, contains('끝까지 못 맞힌 투구만 0m'));
      expect(copy, contains('좁은 12%'));
      expect(copy, contains('HOME RUN!'));
      expect(copy, contains('10구는 도깨비 마구'));
      expect(copy, contains('0.60초'));
      expect(copy, contains('7구부터'));
      expect(copy, contains('최대 40m'));
      expect(copy, contains('10구 중 가장 긴 비거리'));
      expect(copy, contains('제한시간은 없어요'));
      expect(copy, contains('점수 없이 오늘 기회가 소진'));
    },
  );

  test('home animation resets every dependent value at the loop boundary', () {
    final before = TenPitchSluggerPreviewSnapshot.forFrame(59);
    final after = TenPitchSluggerPreviewSnapshot.forFrame(60);

    expect(before.stage, TenPitchSluggerPreviewStage.result);
    expect(before.scoreCm, 11240);
    expect(after.stage, TenPitchSluggerPreviewStage.windup);
    expect(after.scoreCm, 0);
    expect(after.ballProgress, 0);
    expect(after.caption, contains('4 / 10'));
  });

  test('hitter view keeps the pitcher centered and lowers the batter', () {
    const size = Size(360, 640);
    final release = TenPitchSluggerScene.releaseFor(size);
    final contact = TenPitchSluggerScene.contactFor(size);
    final strikeZone = TenPitchSluggerScene.strikeZoneFor(size);
    final pitcher = TenPitchSluggerScene.pitcherBoundsFor(size);
    final batter = TenPitchSluggerScene.batterBoundsFor(size);
    final batterSprite = TenPitchSluggerScene.batterSpriteBoundsFor(size);
    final homePlate = TenPitchSluggerScene.homePlateCenterFor(size);

    expect(release.dx, size.width / 2);
    expect(pitcher.center.dx, size.width / 2);
    expect(release.dy, lessThan(strikeZone.top));
    expect(strikeZone.contains(contact), isTrue);
    expect(contact.dx, strikeZone.center.dx);
    expect(batter.right, lessThan(strikeZone.left));
    expect(batter.bottom, lessThanOrEqualTo(size.height));
    expect(batterSprite.top, 338);
    expect(batterSprite.left, -33);
    expect(contact.dx, 182);
    expect(contact.dy, 474);
    expect(homePlate.dy, closeTo(546, 0.2));
    expect(contact.dy, lessThan(homePlate.dy));
  });

  test('field geometry shares one perspective projection', () {
    final plate = TenPitchSluggerScene.homePlateLogicalPointsForTest();
    final leftBox = TenPitchSluggerScene.leftBatterBoxLogicalPointsForTest();
    final rightBox = TenPitchSluggerScene.rightBatterBoxLogicalPointsForTest();
    final leftFoul = TenPitchSluggerScene.leftFoulLineLogicalPointsForTest();
    final rightFoul = TenPitchSluggerScene.rightFoulLineLogicalPointsForTest();
    final mound = TenPitchSluggerScene.moundLogicalBoundsForTest();
    final rubber = TenPitchSluggerScene.pitchingRubberLogicalBoundsForTest();

    expect(plate[0].dx, closeTo(158.6, 0.3));
    expect(plate[1].dx, closeTo(201.4, 0.3));
    expect(plate[0].dy, closeTo(529.2, 0.3));
    expect(plate[3], const Offset(180, 565));
    expect(plate[2].dx - plate[4].dx, closeTo(45.4, 0.5));

    // The player-scale visual boxes contain the authored batter stance while
    // preserving the regulation six-foot length and shared field projection.
    expect(leftBox[0].dx, closeTo(57.7, 0.5));
    expect(leftBox[1].dx, closeTo(153.3, 0.5));
    expect(leftBox[0].dy, closeTo(519.4, 0.5));
    expect(leftBox[2].dy, closeTo(630, 0.5));
    expect(leftBox[3].dx, closeTo(5.7, 0.5));
    expect(rightBox[0].dx + leftBox[0].dx, closeTo(360, 0.1));
    expect(rightBox[3].dx + leftBox[3].dx, closeTo(360, 0.1));
    expect(TenPitchSluggerScene.chalkThicknessLogicalPixelsForTest(), 4);

    // The stylized foul guides start at each box's far-edge midpoint, fan
    // outward, and terminate below the authored grass/dirt boundary.
    expect(leftFoul[0].dx, closeTo(105.5, 0.5));
    expect(leftFoul[0].dy, closeTo(leftBox[0].dy, 0.1));
    expect(leftFoul[1], const Offset(0, 454));
    expect(rightFoul[0].dx + leftFoul[0].dx, closeTo(360, 0.1));
    expect(rightFoul[1], const Offset(360, 454));

    // The regulation 18-foot circle and 24-inch rubber are projected at their
    // official 59-foot and 60-foot-6-inch distances from home.
    final moundCenter = TenPitchSluggerScene.fieldToLogicalForTest(0, 59 * 12);
    expect(moundCenter.dx, 180);
    expect(moundCenter.dy, closeTo(328, 0.1));
    expect(mound.center.dx, 180);
    expect(mound.center.dy, closeTo(329, 0.2));
    expect(mound.width, closeTo(86.6, 0.5));
    expect(mound.height, closeTo(16.6, 0.5));
    expect(rubber.center.dx, 180);
    expect(rubber.center.dy, closeTo(326.2, 0.5));
    expect(rubber.width, closeTo(9.4, 0.5));

    // Perspective must make the near edge wider and farther from the plate
    // than the far edge; the old hand-authored boxes had this relationship
    // reversed.
    final farWidth = leftBox[1].dx - leftBox[0].dx;
    final nearWidth = leftBox[2].dx - leftBox[3].dx;
    expect(nearWidth, greaterThan(farWidth));
    expect(565 - leftBox[0].dy, lessThan(leftBox[2].dy - 565));
  });

  testWidgets('all staged guide scenes fit the guide viewport', (tester) async {
    for (final scene in TenPitchSluggerPreviewScene.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 360,
              height: 268,
              child: TenPitchSluggerPreview(scene: scene, animate: false),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: scene.name);
    }
  });

  testWidgets('home preview advances through two complete coherent cycles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 360,
          height: 460,
          child: TenPitchSluggerPreview(
            scene: TenPitchSluggerPreviewScene.home,
          ),
        ),
      ),
    );

    expect(find.text('0.0m'), findsOneWidget);
    for (var frame = 0; frame < 59; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('112.4m'), findsOneWidget);
    expect(find.text('HOME RUN!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('0.0m'), findsOneWidget);
    expect(find.text('HOME RUN!'), findsNothing);
    for (var frame = 0; frame < 59; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('112.4m'), findsOneWidget);
    expect(find.text('HOME RUN!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

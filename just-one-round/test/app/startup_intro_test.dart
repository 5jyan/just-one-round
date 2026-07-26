import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/startup_intro.dart';

void main() {
  testWidgets('딱과 한 판만을 순서대로 보여주고 햅틱을 재생한다', (tester) async {
    var firstImpactCount = 0;
    var secondImpactCount = 0;
    var homeTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StartupIntro(
          firstImpact: () async => firstImpactCount++,
          secondImpact: () async => secondImpactCount++,
          child: GestureDetector(
            key: const Key('home-content'),
            behavior: HitTestBehavior.opaque,
            onTap: () => homeTapCount++,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('startup-intro')), findsOneWidget);
    expect(find.text('딱!'), findsOneWidget);
    expect(find.text('한 판만!'), findsOneWidget);
    expect(firstImpactCount, 0);
    expect(secondImpactCount, 0);
    await tester.tap(
      find.byKey(const Key('home-content')),
      warnIfMissed: false,
    );
    expect(homeTapCount, 0);

    await tester.pump(const Duration(milliseconds: 81));
    expect(firstImpactCount, 1);
    expect(secondImpactCount, 0);

    await tester.pump(const Duration(milliseconds: 500));
    expect(secondImpactCount, 0);

    await tester.pump(const Duration(milliseconds: 150));
    expect(secondImpactCount, 1);

    await tester.pump(const Duration(milliseconds: 190));
    await tester.pump();
    expect(find.byKey(const Key('startup-intro')), findsNothing);
    expect(find.byKey(const Key('home-content')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-content')));
    expect(homeTapCount, 1);
  });

  testWidgets('홈 데이터가 준비될 때까지 최종 로고 화면을 유지한다', (tester) async {
    var ready = false;

    Widget buildIntro() => MaterialApp(
      home: StartupIntro(
        ready: ready,
        child: const ColoredBox(key: Key('home-content'), color: Colors.black),
      ),
    );

    await tester.pumpWidget(buildIntro());
    await tester.pump(const Duration(milliseconds: 921));
    await tester.pump();

    expect(find.byKey(const Key('startup-intro')), findsOneWidget);
    expect(find.byKey(const Key('startup-intro-loading')), findsOneWidget);
    expect(find.byKey(const Key('home-content')), findsOneWidget);

    ready = true;
    await tester.pumpWidget(buildIntro());
    await tester.pump();

    expect(find.byKey(const Key('startup-intro')), findsNothing);
  });

  testWidgets('모션 감소 설정에서는 충격 애니메이션과 햅틱을 생략한다', (tester) async {
    var impactCount = 0;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: StartupIntro(
            firstImpact: () async => impactCount++,
            secondImpact: () async => impactCount++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('startup-intro')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 261));
    await tester.pump();

    expect(impactCount, 0);
    expect(find.byKey(const Key('startup-intro')), findsNothing);
  });
}

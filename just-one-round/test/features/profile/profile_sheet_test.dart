import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/features/profile/presentation/profile_sheet.dart';

void main() {
  testWidgets('프로필에서 경제 정보와 계정 설정을 확인할 수 있다', (tester) async {
    ProfileAction? selectedAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selectedAction = await showProfileSheet(
                  context,
                  nickname: '별하나',
                  economy: PlayerEconomy.fromTotals(
                    coins: 125,
                    experiencePoints: 225,
                  ),
                  kakaoConfigured: true,
                  kakaoLinked: false,
                  isAnonymousAccount: true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('프로필'), findsOneWidget);
    expect(find.text('별하나'), findsOneWidget);
    expect(find.text('125'), findsOneWidget);
    expect(find.text('225'), findsOneWidget);
    expect(find.byKey(const Key('profile-exp-progress')), findsOneWidget);
    expect(
      find.byKey(const Key('profile-nickname-color-info')),
      findsOneWidget,
    );
    expect(find.textContaining('LV.5 노랑'), findsOneWidget);
    expect(
      find.byKey(const Key('profile-nickname-color-action')),
      findsNothing,
    );
    expect(find.byKey(const Key('profile-nickname-action')), findsOneWidget);
    expect(find.byKey(const Key('profile-kakao-action')), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-kakao-action')));
    await tester.pumpAndSettle();

    expect(selectedAction, ProfileAction.linkKakao);
  });
}

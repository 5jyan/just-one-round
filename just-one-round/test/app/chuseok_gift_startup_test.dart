import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/core/events/chuseok_gift.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';

void main() {
  testWidgets('unclaimed Chuseok gift appears once and completes after claim', (
    tester,
  ) async {
    final repository = _ChuseokGiftRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.statusCalls, 1);
    expect(find.byKey(const Key('chuseok-gift-dialog')), findsOneWidget);
    expect(find.text('즐거운 추석 되세요!'), findsOneWidget);
    expect(find.text('도전권 1장'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chuseok-gift-claim')));
    await tester.pumpAndSettle();

    expect(repository.claimCalls, 1);
    expect(find.text('추석 선물을 받았어요!'), findsOneWidget);
    expect(find.text('추석 선물로 도전권 1장을 받았어요.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chuseok-gift-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chuseok-gift-dialog')), findsNothing);
  });

  testWidgets('a failed claim keeps the popup retryable', (tester) async {
    final repository = _ChuseokGiftRepository(failClaim: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chuseok-gift-claim')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chuseok-gift-dialog')), findsOneWidget);
    expect(find.textContaining('인터넷 연결을 확인'), findsOneWidget);
    expect(find.byKey(const Key('chuseok-gift-claim')), findsOneWidget);

    repository.failClaim = false;
    await tester.tap(find.byKey(const Key('chuseok-gift-claim')));
    await tester.pumpAndSettle();
    expect(repository.claimCalls, 2);
    expect(find.text('추석 선물을 받았어요!'), findsOneWidget);
  });

  testWidgets('a claimed account does not show the popup on another startup', (
    tester,
  ) async {
    final repository = _ChuseokGiftRepository(claimed: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.statusCalls, 1);
    expect(find.byKey(const Key('chuseok-gift-dialog')), findsNothing);
  });
}

class _ChuseokGiftRepository extends PreviewDailyGameRepository {
  _ChuseokGiftRepository({this.claimed = false, this.failClaim = false});

  bool claimed;
  bool failClaim;
  var statusCalls = 0;
  var claimCalls = 0;

  @override
  Future<ChuseokGiftStatus> fetchChuseokGiftStatus() async {
    statusCalls += 1;
    return ChuseokGiftStatus(eligible: true, claimed: claimed);
  }

  @override
  Future<ChuseokGiftClaim> claimChuseokGift() async {
    claimCalls += 1;
    if (failClaim) throw StateError('offline');
    claimed = true;
    return const ChuseokGiftClaim(
      eligible: true,
      claimed: true,
      granted: true,
      ticketsGranted: 1,
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/core/auth/kakao_auth_service.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_session.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/features/shop/domain/shop_purchase.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:postgrest/postgrest.dart';

void main() {
  testWidgets('첫 화면은 무료 연습권 한 장과 무료 도전을 표시한다', (tester) async {
    final repository = _TicketRepository(_ticketState(tickets: 1));
    final adService = _CountingAdService();

    await _pumpTicketState(
      tester,
      repository.state,
      repository: repository,
      adService: adService,
    );

    expect(find.text('연습하기'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('practice-button')),
        matching: find.byIcon(Icons.confirmation_number_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('practice-ticket-badge')), findsOneWidget);
    expect(find.byKey(const Key('challenge-ticket-badge')), findsNothing);
    expect(find.byKey(const Key('challenge-opportunity-badge')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('practice-ticket-inline')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('practice-ticket-inline')),
              matching: find.byIcon(Icons.confirmation_number_rounded),
            ),
          )
          .color,
      AppColors.primary,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('practice-ticket-inline')),
              matching: find.text('1'),
            ),
          )
          .style
          ?.color,
      AppColors.text,
    );
    expect(find.text('오늘의 도전!'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('challenge-button')),
        matching: find.byIcon(Icons.sports_score_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('티켓 받기 +2'), findsNothing);
    expect(find.textContaining('연습권 1장 · 오늘의 도전 1회'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('practice-ticket-badge'))).dy,
      lessThan(
        tester.getBottomRight(find.byKey(const Key('today-game-title'))).dy,
      ),
    );
  });

  testWidgets('연습권·도전권 배지는 아이콘과 수량 스타일을 통일한다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(tickets: 2, storeChallengeTickets: 3),
    );
    await _pumpTicketState(tester, repository.state, repository: repository);

    const badgeSpecs = [
      (
        badgeKey: 'practice-ticket-inline',
        iconBoxKey: 'practice-ticket-icon-box',
        icon: Icons.confirmation_number_rounded,
        count: '2',
      ),
      (
        badgeKey: 'challenge-ticket-badge',
        iconBoxKey: 'challenge-ticket-icon-box',
        icon: Icons.sports_score_rounded,
        count: '3',
      ),
    ];
    TextStyle? firstCountStyle;

    for (final spec in badgeSpecs) {
      final badge = find.byKey(Key(spec.badgeKey));
      final icon = find.descendant(of: badge, matching: find.byIcon(spec.icon));
      final count = find.descendant(of: badge, matching: find.text(spec.count));
      final iconBox = find.byKey(Key(spec.iconBoxKey));

      expect(badge, findsOneWidget);
      expect(icon, findsOneWidget);
      expect(iconBox, findsOneWidget);
      expect(count, findsOneWidget);
      expect(tester.getSize(badge).height, closeTo(25, 0.01));
      expect(tester.getSize(iconBox), const Size(24, 24));
      expect(tester.widget<Icon>(icon).size, 20);

      final countStyle = tester.widget<Text>(count).style;
      expect(countStyle, isNotNull);
      if (firstCountStyle == null) {
        firstCountStyle = countStyle;
      } else {
        expect(countStyle, firstCountStyle);
      }
      expect(countStyle?.fontFamily, 'Galmuri');
      expect(countStyle?.fontSize, 13);
      expect(countStyle?.fontWeight, FontWeight.w900);
      expect(countStyle?.height, 1);
    }
  });

  testWidgets('좁은 화면에서도 게임명 행 오른쪽 티켓 배지가 잘리지 않는다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final repository = _TicketRepository(_ticketState(tickets: 22));
    await _pumpTicketState(tester, repository.state, repository: repository);
    await tester.ensureVisible(find.byKey(const Key('practice-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today-game-title')), findsOneWidget);
    expect(find.byKey(const Key('practice-ticket-badge')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('practice-ticket-inline')),
        matching: find.text('22'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('challenge-opportunity-badge')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('일일 기회가 없어도 보유한 상점 티켓을 게임명 행에 표시한다', (tester) async {
    final state = _ticketState(
      tickets: 0,
      practiceAvailable: false,
      challengeAvailable: false,
      deviceDailyLimitReached: true,
      storePracticeTickets: 9,
      storeChallengeTickets: 8,
    );
    await _pumpTicketState(tester, state);

    expect(
      find.descendant(
        of: find.byKey(const Key('practice-ticket-inline')),
        matching: find.text('9'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('challenge-ticket-badge')),
        matching: find.text('8'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('challenge-opportunity-badge')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('ticket-inventory'))).dy,
      lessThan(
        tester.getBottomRight(find.byKey(const Key('today-game-title'))).dy,
      ),
    );
  });

  testWidgets('연습을 시작하면 티켓 한 장이 빠지는 이펙트를 보여준다', (tester) async {
    final repository = _TicketRepository(_ticketState(tickets: 1));
    await _pumpTicketState(tester, repository.state, repository: repository);

    final practiceButton = find.byKey(const Key('practice-button'));
    await tester.ensureVisible(practiceButton);
    await tester.tap(practiceButton);
    for (
      var frame = 0;
      frame < 20 &&
          find.byKey(const Key('practice-ticket-delta')).evaluate().isEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.byKey(const Key('practice-ticket-delta')), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(
        of: find.byKey(const Key('practice-ticket-inline')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('practice-ticket-inline')),
              matching: find.text('0'),
            ),
          )
          .style
          ?.color,
      AppColors.textMuted,
    );
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('연습권 감소 이펙트는 발급 응답을 기다리지 않고 시작한다', (tester) async {
    final repository = _TicketRepository(_ticketState(tickets: 1));
    await _pumpTicketState(tester, repository.state, repository: repository);
    final fetchGate = Completer<void>();
    repository.fetchGate = fetchGate;

    final practiceButton = find.byKey(const Key('practice-button'));
    await tester.ensureVisible(practiceButton);
    await tester.tap(practiceButton);
    await tester.pump();

    expect(find.byKey(const Key('practice-ticket-delta')), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);

    fetchGate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('중단된 연습 재진입은 이미 예약된 티켓을 다시 차감하지 않는다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(tickets: 1, practicePending: true),
    );
    await _pumpTicketState(tester, repository.state, repository: repository);

    final practiceButton = find.byKey(const Key('practice-button'));
    await tester.ensureVisible(practiceButton);
    await tester.tap(practiceButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('practice-ticket-delta')), findsNothing);
    expect(repository.dailyPracticeClaims, 1);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('무료 연습권을 쓰면 광고 없이 연습을 시작한다', (tester) async {
    final repository = _TicketRepository(_ticketState(tickets: 1));
    final adService = _CountingAdService();
    await _pumpTicketState(
      tester,
      repository.state,
      repository: repository,
      adService: adService,
    );

    final practiceButton = find.byKey(const Key('practice-button'));
    await tester.ensureVisible(practiceButton);
    await tester.tap(practiceButton);
    await tester.pumpAndSettle();

    expect(repository.dailyPracticeClaims, 1);
    expect(adService.showCalls, 0);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('연습 여부와 관계없이 공식 도전은 광고 없이 시작한다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 1,
        tickets: 0,
        practiceAvailable: false,
        practiceRewardAvailable: true,
      ),
    );
    final adService = _CountingAdService();
    await _pumpTicketState(
      tester,
      repository.state,
      repository: repository,
      adService: adService,
    );

    await tester.ensureVisible(find.text('오늘의 도전!'));
    await tester.tap(find.text('오늘의 도전!'));
    await tester.pumpAndSettle();

    expect(repository.dailyChallengeClaims, 1);
    expect(repository.rankedAdPrepareCalls, 0);
    expect(adService.showCalls, 0);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('광고 완료는 게임을 시작하지 않고 연습권 두 장만 지급한다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 1,
        tickets: 0,
        practiceAvailable: false,
        practiceRewardAvailable: true,
      ),
    )..rewardPendingOnce = true;
    final adService = _CountingAdService();
    await _pumpTicketState(
      tester,
      repository.state,
      repository: repository,
      adService: adService,
    );

    final rewardButton = find.byKey(const Key('practice-button'));
    await tester.ensureVisible(rewardButton);
    await tester.tap(rewardButton);
    await tester.pumpAndSettle();

    expect(repository.practiceAdPrepareCalls, 1);
    expect(repository.practiceTicketClaims, 2);
    expect(adService.showCalls, 1);
    expect(repository.dailyPracticeClaims, 0);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('연습권 2장을 받았어요!'), findsOneWidget);
  });

  testWidgets('광고로 받은 연습권도 별도 광고 없이 한 장씩 사용한다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 1,
        tickets: 2,
        practiceTicketCapacity: 3,
        practiceRewardEarned: true,
      ),
    );
    final adService = _CountingAdService();
    await _pumpTicketState(
      tester,
      repository.state,
      repository: repository,
      adService: adService,
    );

    final practiceButton = find.byKey(const Key('practice-button'));
    await tester.ensureVisible(practiceButton);
    await tester.tap(practiceButton);
    await tester.pumpAndSettle();

    expect(repository.dailyPracticeClaims, 1);
    expect(repository.practiceAdPrepareCalls, 0);
    expect(adService.showCalls, 0);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('이전 광고 2장을 다 쓰면 광고 충전 버튼이 다시 열린다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 3,
        tickets: 0,
        practiceAvailable: false,
        practiceRewardAvailable: true,
        practiceRewardEarned: true,
      ),
    );
    final adService = _CountingAdService();
    await _pumpTicketState(
      tester,
      repository.state,
      repository: repository,
      adService: adService,
    );

    expect(find.text('티켓 받기 +2'), findsOneWidget);
  });

  testWidgets('이미 도전했다면 오늘의 도전을 다시 시작할 수 없다', (tester) async {
    await _pumpTicketState(
      tester,
      _ticketState(tickets: 1, challengeAvailable: false),
    );

    await tester.ensureVisible(find.text('오늘의 도전!'));
    await tester.tap(find.text('오늘의 도전!'));
    await tester.pump();

    expect(find.byType(GameScreen), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('play-action-status'))).data,
      '오늘은 더 이상 도전할 수 없어요.',
    );
  });

  testWidgets('오늘의 도전 후 진짜 딱 한판만은 팝업 없이 광고로 시작한다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 1,
        tickets: 0,
        practiceAvailable: false,
        extraChallengeAvailable: true,
        adChallengeAvailable: true,
      ),
    )..rankedRewardPendingOnce = true;
    final adService = _CountingAdService();
    await _pumpTicketState(
      tester,
      repository.state,
      repository: repository,
      adService: adService,
    );

    expect(find.text('진짜 딱 한판만!'), findsOneWidget);
    expect(
      find.byKey(const Key('extra-challenge-choice-dialog')),
      findsNothing,
    );
    await tester.ensureVisible(find.byKey(const Key('challenge-button')));
    await tester.tap(find.byKey(const Key('challenge-button')));
    await tester.pumpAndSettle();

    expect(repository.rankedAdPrepareCalls, 1);
    expect(adService.showCalls, 1);
    expect(repository.challengeTicketClaims, 0);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('도전권이 있어도 별도 도전권 버튼을 노출하지 않는다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 1,
        tickets: 0,
        practiceAvailable: false,
        extraChallengeAvailable: true,
        adChallengeAvailable: true,
        storeChallengeTickets: 1,
        challengeTicketAvailable: false,
      ),
    );
    await _pumpTicketState(tester, repository.state, repository: repository);

    expect(
      find.byKey(const Key('extra-challenge-ticket-button')),
      findsNothing,
    );
  });

  testWidgets('광고 추가 도전 후 도전권 버튼으로 전환된다', (tester) async {
    await _pumpTicketState(
      tester,
      _ticketState(
        playCount: 2,
        tickets: 0,
        practiceAvailable: false,
        challengeAvailable: true,
        adChallengeAvailable: false,
        extraChallengeAvailable: true,
        challengeTicketAvailable: true,
        rankedAdAttemptUsed: true,
        storeChallengeTickets: 1,
      ),
    );

    expect(find.text('도전권으로 도전!'), findsOneWidget);
    expect(find.text('진짜 딱 한판만!'), findsNothing);
    expect(
      tester
          .widget<PixelButton>(find.byKey(const Key('challenge-button')))
          .onPressed,
      isNotNull,
    );
    expect(
      find.byKey(const Key('extra-challenge-ticket-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('challenge-opportunity-badge')), findsNothing);
  });

  testWidgets('도전권 버튼은 티켓 이펙트와 게임 로딩을 동시에 시작한다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 2,
        tickets: 0,
        practiceAvailable: false,
        challengeAvailable: true,
        adChallengeAvailable: false,
        extraChallengeAvailable: true,
        challengeTicketAvailable: true,
        rankedAdAttemptUsed: true,
        storeChallengeTickets: 1,
      ),
    );
    final adService = _CountingAdService();
    await _pumpTicketState(
      tester,
      repository.state,
      repository: repository,
      adService: adService,
    );

    final challengeButton = find.byKey(const Key('challenge-button'));
    await tester.ensureVisible(challengeButton);
    await tester.tap(challengeButton);
    await tester.pump();

    expect(repository.challengeTicketClaims, 1);
    expect(repository.rankedAdPrepareCalls, 0);
    expect(adService.showCalls, 0);
    expect(find.byKey(const Key('challenge-ticket-delta')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('도전권 감소 이펙트는 발급 응답을 기다리지 않고 시작한다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 2,
        tickets: 0,
        practiceAvailable: false,
        challengeAvailable: true,
        adChallengeAvailable: false,
        extraChallengeAvailable: true,
        challengeTicketAvailable: true,
        rankedAdAttemptUsed: true,
        storeChallengeTickets: 1,
      ),
    );
    await _pumpTicketState(tester, repository.state, repository: repository);
    final fetchGate = Completer<void>();
    repository.fetchGate = fetchGate;

    final challengeButton = find.byKey(const Key('challenge-button'));
    await tester.ensureVisible(challengeButton);
    await tester.tap(challengeButton);
    await tester.pump();

    expect(find.byKey(const Key('challenge-ticket-delta')), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);

    fetchGate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('도전권이 0장이면 전환된 도전권 버튼을 비활성화한다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 2,
        tickets: 0,
        practiceAvailable: false,
        challengeAvailable: true,
        adChallengeAvailable: false,
        extraChallengeAvailable: true,
        challengeTicketAvailable: false,
        rankedAdAttemptUsed: true,
        storeChallengeTickets: 0,
      ),
    );
    await _pumpTicketState(tester, repository.state, repository: repository);

    final challengeButton = find.byKey(const Key('challenge-button'));
    expect(find.text('도전권으로 도전!'), findsOneWidget);
    expect(tester.widget<PixelButton>(challengeButton).onPressed, isNull);

    final semanticsHandle = tester.ensureSemantics();
    final semantics = tester.getSemantics(challengeButton);
    expect(semantics.label, '도전권으로 도전!');
    expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(semantics.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(semantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
    semanticsHandle.dispose();

    await tester.ensureVisible(challengeButton);
    await tester.tap(challengeButton);
    await tester.pump();

    expect(repository.dailyChallengeClaims, 0);
    expect(repository.challengeTicketClaims, 0);
    expect(repository.rankedAdPrepareCalls, 0);
    expect(find.byType(GameScreen), findsNothing);
  });

  testWidgets('상점에서 코인으로 연습권을 구매한다', (tester) async {
    final state = _ticketState(
      tickets: 1,
      economy: PlayerEconomy.fromTotals(coins: 100, experiencePoints: 0),
    );
    final repository = _TicketRepository(state);
    await _pumpTicketState(tester, state, repository: repository);

    await tester.tap(find.byKey(const Key('shop-button')));
    await tester.pumpAndSettle();
    expect(find.text('코인 상점'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('shop-coin-balance')),
        matching: find.text('100'),
      ),
      findsOneWidget,
    );
    expect(find.text('연습할 때 사용'), findsOneWidget);
    expect(find.text('연습 한 판에 1장을 써요. 날짜가 바뀌어도 남아요.'), findsNothing);

    final item = find.byKey(const Key('shop-practice-ticket'));
    await tester.tap(
      find.descendant(of: item, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shop-purchase-confirmation')), findsOneWidget);
    expect(find.text('연습권 1장을 100 C에 구매해요.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shop-purchase-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shop-purchase-confirmation')), findsNothing);
    expect(
      find.descendant(of: item, matching: find.text('보유 0장')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: item, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shop-purchase-confirmation')), findsOneWidget);
    await tester.tap(find.byKey(const Key('shop-purchase-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.byKey(const Key('shop-owned-count-particle-0')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);
    expect(find.text('보유 1장'), findsOneWidget);
    expect(find.text('연습권 1장을 샀어요!'), findsNothing);
    expect(find.byKey(const Key('shop-purchase-celebration')), findsNothing);
  });

  testWidgets('상점에서 500코인으로 닉네임 변경권을 구매한다', (tester) async {
    final state = _ticketState(
      tickets: 1,
      economy: PlayerEconomy.fromTotals(coins: 500, experiencePoints: 0),
    );
    final repository = _TicketRepository(state);
    await _pumpTicketState(tester, state, repository: repository);

    await tester.tap(find.byKey(const Key('shop-button')));
    await tester.pumpAndSettle();

    final item = find.byKey(const Key('shop-nickname-change-ticket'));
    expect(item, findsOneWidget);
    expect(find.text('닉네임 변경권 1장'), findsOneWidget);
    await tester.tap(
      find.descendant(of: item, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();
    expect(find.text('닉네임 변경권 1장을 500 C에 구매해요.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shop-purchase-confirm')));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const Key('shop-nickname-change-after-purchase')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('shop-nickname-change-after-purchase-later')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: item, matching: find.text('보유 1장')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('shop-coin-balance')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('닉네임 변경권 구매 후 바로 변경을 선택하면 닉네임 편집기를 연다', (tester) async {
    final state = _ticketState(
      tickets: 1,
      economy: PlayerEconomy.fromTotals(coins: 500, experiencePoints: 0),
    );
    final repository = _TicketRepository(state);
    await _pumpTicketState(tester, state, repository: repository);

    await tester.tap(find.byKey(const Key('shop-button')));
    await tester.pumpAndSettle();
    final item = find.byKey(const Key('shop-nickname-change-ticket'));
    await tester.tap(
      find.descendant(of: item, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shop-purchase-confirm')));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byKey(const Key('shop-nickname-change-after-purchase')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('shop-nickname-change-after-purchase-now')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nickname-field')), findsOneWidget);
    expect(find.text('랭킹 닉네임'), findsOneWidget);
    expect(find.text('테스터'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('nickname-field')), '새닉네임');
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('nickname-change-confirmation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('nickname-change-ticket-required')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('nickname-change-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('구매 응답이 끊겨도 같은 요청 ID로 자동 재시도한다', (tester) async {
    final state = _ticketState(
      tickets: 1,
      economy: PlayerEconomy.fromTotals(coins: 500, experiencePoints: 0),
    );
    final repository = _TicketRepository(state)
      ..failFirstShopPurchaseTransiently = true;
    await _pumpTicketState(tester, state, repository: repository);

    await tester.tap(find.byKey(const Key('shop-button')));
    await tester.pumpAndSettle();
    final item = find.byKey(const Key('shop-nickname-change-ticket'));
    await tester.tap(
      find.descendant(of: item, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shop-purchase-confirm')));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const Key('shop-nickname-change-after-purchase')),
      findsOneWidget,
    );
    expect(repository.purchaseRequestIds, hasLength(2));
    expect(repository.purchaseRequestIds.toSet(), hasLength(1));
    await tester.tap(
      find.byKey(const Key('shop-nickname-change-after-purchase-later')),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('프로필에서 닉네임 변경을 취소하면 저장하지 않는다', (tester) async {
    final state = _ticketState(tickets: 1, storeNicknameChangeTickets: 1);
    final repository = _TicketRepository(state);
    await _pumpTicketState(tester, state, repository: repository);

    await _openProfileNicknameEditor(tester);
    await tester.enterText(find.byKey(const Key('nickname-field')), '새닉네임');
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nickname-change-confirmation')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('nickname-change-cancel')));
    await tester.pumpAndSettle();

    expect(repository.savedNicknames, isEmpty);
    expect(find.byKey(const Key('nickname-field')), findsNothing);
  });

  testWidgets('프로필에서 닉네임 변경을 확인하면 저장을 시도한다', (tester) async {
    final state = _ticketState(tickets: 1, storeNicknameChangeTickets: 1);
    final repository = _TicketRepository(state);
    await _pumpTicketState(tester, state, repository: repository);

    await _openProfileNicknameEditor(tester);
    await tester.enterText(find.byKey(const Key('nickname-field')), '새닉네임');
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nickname-change-confirm')));
    await tester.pumpAndSettle();

    expect(repository.savedNicknames, ['새닉네임']);
    expect(find.text('닉네임이 저장됐어요.'), findsOneWidget);
  });

  testWidgets('변경권이 없으면 닉네임 저장 전에 상점 안내를 표시한다', (tester) async {
    final state = _ticketState(tickets: 1);
    final repository = _TicketRepository(state);
    await _pumpTicketState(tester, state, repository: repository);

    await _openProfileNicknameEditor(tester);
    await tester.enterText(find.byKey(const Key('nickname-field')), '새닉네임');
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nickname-change-ticket-required')),
      findsOneWidget,
    );
    expect(find.text('닉네임 변경권이 필요해요'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('nickname-change-ticket-required-shop')),
    );
    await tester.pumpAndSettle();
    expect(find.text('코인 상점'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shop-close')));
    await tester.pumpAndSettle();

    expect(repository.savedNicknames, isEmpty);
  });

  testWidgets('같은 닉네임을 다시 저장할 때는 변경권 확인을 생략한다', (tester) async {
    final state = _ticketState(tickets: 1);
    final repository = _TicketRepository(state);
    await _pumpTicketState(tester, state, repository: repository);

    await _openProfileNicknameEditor(tester);
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nickname-change-confirmation')), findsNothing);
    expect(repository.savedNicknames, ['테스터']);
    expect(find.text('닉네임이 저장됐어요.'), findsOneWidget);
  });

  testWidgets('중복 닉네임 오류 뒤 재시도하면 변경권 확인을 다시 거친다', (tester) async {
    final state = _ticketState(tickets: 1, storeNicknameChangeTickets: 1);
    final repository = _TicketRepository(state)
      ..setNicknameError = const PostgrestException(
        message: 'nickname already taken',
      );
    await _pumpTicketState(tester, state, repository: repository);

    await _openProfileNicknameEditor(tester);
    await tester.enterText(find.byKey(const Key('nickname-field')), '중복닉네임');
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nickname-change-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('이미 사용 중인 닉네임이에요. 다른 닉네임을 입력해 주세요.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();

    repository.setNicknameError = null;
    await tester.enterText(find.byKey(const Key('nickname-field')), '다른닉네임');
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('nickname-change-confirmation')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('nickname-change-confirm')));
    await tester.pumpAndSettle();

    expect(repository.savedNicknames, ['다른닉네임']);
  });

  testWidgets('상점의 도전권과 색상권 구매·선택을 확인 팝업으로 확정한다', (tester) async {
    final state = _ticketState(
      tickets: 1,
      economy: PlayerEconomy.fromTotals(coins: 1000, experiencePoints: 0),
    );
    final repository = _TicketRepository(state);
    await _pumpTicketState(tester, state, repository: repository);

    await tester.tap(find.byKey(const Key('shop-button')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('shop-nickname-color-ticket')),
        matching: find.textContaining('보유'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('shop-challenge-ticket')),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shop-purchase-confirmation')), findsOneWidget);
    expect(find.text('도전권 1장을 250 C에 구매해요.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shop-purchase-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('shop-challenge-ticket')),
        matching: find.text('보유 1장'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shop-purchase-celebration')), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('shop-nickname-color-ticket')),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('nickname-color-choice-sheet')),
      findsOneWidget,
    );
    expect(find.text('테스터'), findsNWidgets(5));
    expect(find.byKey(const Key('shop-purchase-celebration')), findsNothing);

    await tester.tap(find.byKey(const Key('nickname-color-choice-coral')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nickname-color-choice-coral')), findsNothing);
    expect(
      find.byKey(const Key('nickname-color-confirmation')),
      findsOneWidget,
    );
    expect(find.text('색상을 적용할까요?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nickname-color-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('다시 바꾸려면 구매'), findsOneWidget);
  });

  testWidgets('상점에는 코인 광고 보상을 표시하지 않는다', (tester) async {
    final state = _ticketState(
      tickets: 1,
      coinAdAvailable: true,
      economy: PlayerEconomy.fromTotals(coins: 100, experiencePoints: 0),
    );
    final repository = _TicketRepository(state);
    final adService = _CountingAdService();
    await _pumpTicketState(
      tester,
      state,
      repository: repository,
      adService: adService,
    );

    await tester.tap(find.byKey(const Key('shop-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shop-coin-ad')), findsNothing);
    expect(find.text('광고 보고 코인 받기'), findsNothing);
    expect(adService.showCalls, 0);
  });

  testWidgets('무료 연습 발급 재시도는 같은 요청 ID를 사용한다', (tester) async {
    final repository = _TicketRepository(_ticketState(tickets: 1))
      ..failFirstPracticeClaimTransiently = true;
    await _pumpTicketState(tester, repository.state, repository: repository);

    final practiceButton = find.byKey(const Key('practice-button'));
    await tester.ensureVisible(practiceButton);
    await tester.tap(practiceButton);
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();

    expect(repository.practiceRequestIds, hasLength(2));
    expect(repository.practiceRequestIds.toSet(), hasLength(1));
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('연습 후 홈에서 다시 시작하면 새 요청 ID로 다음 연습권을 쓴다', (tester) async {
    final repository = _TicketRepository(
      _ticketState(
        playCount: 1,
        tickets: 2,
        practiceTicketCapacity: 3,
        practiceRewardEarned: true,
      ),
    )..decrementTicketsOnPracticeClaim = true;
    await _pumpTicketState(tester, repository.state, repository: repository);

    final practiceButton = find.byKey(const Key('practice-button'));
    await tester.ensureVisible(practiceButton);
    await tester.tap(practiceButton);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-game-exit-button')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(practiceButton);
    await tester.tap(practiceButton);
    await tester.pumpAndSettle();

    expect(repository.practiceRequestIds, hasLength(2));
    expect(repository.practiceRequestIds.toSet(), hasLength(2));
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('기기 일일 제한 상태는 플레이와 광고 보상을 모두 막는다', (tester) async {
    final state = _ticketState(
      tickets: 0,
      challengeAvailable: false,
      practiceAvailable: false,
      deviceDailyLimitReached: true,
    );
    await _pumpTicketState(tester, state);

    expect(find.text('연습하기'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('practice-ticket-inline')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(find.text('오늘의 도전!'), findsOneWidget);
    expect(find.text('티켓 받기 +2'), findsNothing);
    expect(find.textContaining('이 기기의 무료 플레이'), findsOneWidget);
  });
}

Future<void> _openProfileNicknameEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('설정'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('profile-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('profile-nickname-action')));
  await tester.pumpAndSettle();
}

Future<void> _pumpTicketState(
  WidgetTester tester,
  TodayState state, {
  _TicketRepository? repository,
  _CountingAdService? adService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dailyGameRepositoryProvider.overrideWithValue(
          repository ?? _TicketRepository(state),
        ),
        rewardedAdServiceProvider.overrideWithValue(
          adService ?? _CountingAdService(),
        ),
        kakaoAuthServiceProvider.overrideWithValue(
          const _LinkedKakaoAuthService(),
        ),
      ],
      child: const JustOneRoundApp(),
    ),
  );
  await tester.pumpAndSettle();
}

TodayState _ticketState({
  int playCount = 0,
  required int tickets,
  int practiceTicketCapacity = 1,
  bool challengeAvailable = true,
  bool? practiceAvailable,
  bool practiceRewardAvailable = false,
  bool practiceRewardEarned = false,
  bool practicePending = false,
  bool deviceDailyLimitReached = false,
  bool challengeRequiresAd = false,
  bool? adChallengeAvailable,
  bool? extraChallengeAvailable,
  bool? challengeTicketAvailable,
  bool rankedAdAttemptUsed = false,
  int storePracticeTickets = 0,
  int storeChallengeTickets = 0,
  int storeNicknameChangeTickets = 0,
  bool coinAdAvailable = false,
  PlayerEconomy economy = const PlayerEconomy.zero(),
}) => TodayState(
  playDate: DateTime(2026, 8, 15),
  game: const TodayGame(
    id: 'dung_dodge_v2',
    version: 1,
    displayName: '똥피하기',
    description: '테스트',
    durationSeconds: 300,
  ),
  attempts: const [],
  adAttemptAvailable: false,
  testMode: false,
  result: null,
  nickname: '테스터',
  dailyClaimed: playCount > 0,
  playCount: playCount,
  challengeAvailable: challengeAvailable,
  practiceAvailable: practiceAvailable ?? tickets > 0,
  practiceTicketCapacity: practiceTicketCapacity,
  practiceTicketsRemaining: tickets,
  practiceRewardAvailable: practiceRewardAvailable,
  practiceRewardEarned: practiceRewardEarned,
  practicePending: practicePending,
  challengeRequiresAd: challengeRequiresAd,
  adChallengeAvailable:
      adChallengeAvailable ?? extraChallengeAvailable ?? challengeRequiresAd,
  extraChallengeAvailable: extraChallengeAvailable ?? challengeRequiresAd,
  challengeTicketAvailable:
      challengeTicketAvailable ??
      (rankedAdAttemptUsed && storeChallengeTickets > 0),
  practiceRequiresAd: false,
  nextPlayRequiresAd: false,
  deviceDailyLimitReached: deviceDailyLimitReached,
  rankedAdAttemptUsed: rankedAdAttemptUsed,
  storePracticeTickets: storePracticeTickets,
  storeChallengeTickets: storeChallengeTickets,
  storeNicknameChangeTickets: storeNicknameChangeTickets,
  coinAdAvailable: coinAdAvailable,
  economy: economy,
);

class _TicketRepository extends PreviewDailyGameRepository {
  _TicketRepository(this.state) : super(initialEconomy: state.economy);

  TodayState state;
  var dailyPracticeClaims = 0;
  var dailyChallengeClaims = 0;
  var rankedAdPrepareCalls = 0;
  var practiceAdPrepareCalls = 0;
  var practiceTicketClaims = 0;
  var rewardPendingOnce = false;
  var rankedRewardPendingOnce = false;
  var rankedRewardClaims = 0;
  var challengeTicketClaims = 0;
  var coinAdPrepareCalls = 0;
  var coinRewardClaims = 0;
  var coinRewardPendingOnce = false;
  var failFirstPracticeClaimTransiently = false;
  var failFirstShopPurchaseTransiently = false;
  var decrementTicketsOnPracticeClaim = false;
  final savedNicknames = <String>[];
  Object? setNicknameError;
  Completer<void>? fetchGate;
  final practiceRequestIds = <String>[];
  final purchaseRequestIds = <String>[];
  var shopPurchaseCalls = 0;

  @override
  Future<TodayState> fetchToday() async {
    final gate = fetchGate;
    fetchGate = null;
    if (gate != null) await gate.future;
    return state;
  }

  @override
  Future<PlayAttempt> claimDailyAttempt(DateTime expectedPlayDate) async {
    dailyChallengeClaims++;
    return super.claimDailyAttempt(expectedPlayDate);
  }

  @override
  Future<RewardedAdSession> prepareRewardedAd(DateTime expectedPlayDate) async {
    rankedAdPrepareCalls++;
    return super.prepareRewardedAd(expectedPlayDate);
  }

  @override
  Future<PlayAttempt> claimRewardedAttempt(String rewardSessionId) async {
    rankedRewardClaims++;
    if (rankedRewardPendingOnce && rankedRewardClaims == 1) {
      throw const PostgrestException(message: 'reward verification pending');
    }
    return super.claimRewardedAttempt(rewardSessionId);
  }

  @override
  Future<PlayAttempt> claimChallengeTicketAttempt(
    DateTime expectedPlayDate,
  ) async {
    challengeTicketClaims++;
    return super.claimChallengeTicketAttempt(expectedPlayDate);
  }

  @override
  Future<PlayAttempt> claimDailyPractice(
    DateTime expectedPlayDate, {
    required String requestId,
    DateTime? gameDate,
  }) async {
    dailyPracticeClaims++;
    practiceRequestIds.add(requestId);
    if (failFirstPracticeClaimTransiently && dailyPracticeClaims == 1) {
      throw const SocketException('connection reset');
    }
    if (decrementTicketsOnPracticeClaim) {
      final remaining = (state.practiceTicketsRemaining - 1).clamp(0, 999);
      state = _ticketState(
        playCount: (state.playCount ?? 0) + 1,
        tickets: remaining,
        practiceTicketCapacity: state.practiceTicketCapacity,
        challengeAvailable: state.challengeAvailable ?? false,
        practiceRewardAvailable: remaining == 0,
        practiceRewardEarned: state.practiceRewardEarned,
      );
    }
    return PlayAttempt(
      id: 'practice-daily-session-$dailyPracticeClaims',
      ordinal: dailyPracticeClaims,
      status: 'practice',
      grantType: 'practice_daily',
      gameId: state.game?.id,
      gameVersion: state.game?.version,
      gameDurationSeconds: state.game?.durationSeconds,
      playDate: state.playDate,
      practiceOrdinal: dailyPracticeClaims,
      clientRequestId: requestId,
    );
  }

  @override
  Future<RewardedAdSession> preparePracticeAd(DateTime expectedPlayDate) async {
    practiceAdPrepareCalls++;
    return super.preparePracticeAd(expectedPlayDate);
  }

  @override
  Future<int> claimPracticeTicketReward(String rewardSessionId) async {
    practiceTicketClaims++;
    if (rewardPendingOnce && practiceTicketClaims == 1) {
      throw const PostgrestException(message: 'reward verification pending');
    }
    return 2;
  }

  @override
  Future<void> setNickname(String nickname) async {
    final error = setNicknameError;
    if (error != null) throw error;
    savedNicknames.add(nickname);
  }

  @override
  Future<ShopPurchaseResult> purchaseShopItem({
    required String itemId,
    required String requestId,
  }) async {
    shopPurchaseCalls++;
    purchaseRequestIds.add(requestId);
    if (failFirstShopPurchaseTransiently && shopPurchaseCalls == 1) {
      throw const SocketException('connection reset');
    }
    return super.purchaseShopItem(itemId: itemId, requestId: requestId);
  }

  @override
  Future<RewardedAdSession> prepareCoinAd(DateTime expectedPlayDate) async {
    coinAdPrepareCalls++;
    return super.prepareCoinAd(expectedPlayDate);
  }

  @override
  Future<CoinAdRewardResult> claimCoinAdReward(String rewardSessionId) async {
    coinRewardClaims++;
    if (coinRewardPendingOnce && coinRewardClaims == 1) {
      throw const PostgrestException(message: 'reward verification pending');
    }
    return super.claimCoinAdReward(rewardSessionId);
  }
}

class _CountingAdService extends FakeRewardedAdService {
  var showCalls = 0;

  @override
  Future<RewardedAdOutcome> show({
    required String userId,
    required String verificationSessionId,
  }) async {
    showCalls++;
    return super.show(
      userId: userId,
      verificationSessionId: verificationSessionId,
    );
  }
}

class _LinkedKakaoAuthService implements KakaoAuthService {
  const _LinkedKakaoAuthService();

  @override
  bool get isConfigured => true;

  @override
  bool get isLinked => true;

  @override
  Future<KakaoAccountLinkResult> linkAccount() async =>
      KakaoAccountLinkResult.alreadyLinked;
}

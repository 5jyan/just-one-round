import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/profile/domain/nickname_color.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';

void main() {
  test('레벨 경계마다 닉네임 색상을 해금한다', () {
    expect(NicknameColors.forLevel(4), AppColors.text);
    expect(NicknameColors.forLevel(5), const Color(0xFFFFF15A));
    expect(NicknameColors.forLevel(9), const Color(0xFFFFF15A));
    expect(NicknameColors.forLevel(10), const Color(0xFF36F58A));
    expect(NicknameColors.forLevel(14), const Color(0xFF36F58A));
    expect(NicknameColors.forLevel(15), const Color(0xFF5894FF));
    expect(NicknameColors.forLevel(19), const Color(0xFF5894FF));
    expect(NicknameColors.forLevel(20), const Color(0xFFB477FF));
    expect(NicknameColors.forLevel(24), const Color(0xFFB477FF));
    expect(NicknameColors.forLevel(25), const Color(0xFFFF4FA7));
    expect(NicknameColors.forLevel(29), const Color(0xFFFF4FA7));
    expect(NicknameColors.forLevel(30), const Color(0xFFFFD23F));
    expect(NicknameColors.forLevel(99), const Color(0xFFFFD23F));

    expect(NicknameColors.labelForLevel(4), '기본');
    expect(NicknameColors.labelForLevel(5), '노랑');
    expect(NicknameColors.labelForLevel(10), '그린');
    expect(NicknameColors.labelForLevel(15), '블루');
    expect(NicknameColors.labelForLevel(20), '퍼플');
    expect(NicknameColors.labelForLevel(25), '핑크');
    expect(NicknameColors.labelForLevel(30), '골드');
  });

  test('western duel 레거시 토큰용 coral 색상은 계속 해석한다', () {
    expect(NicknameColors.resolve('coral'), const Color(0xFFFF8A80));
    expect(NicknameColors.resolve('yellow'), const Color(0xFFFFF15A));
    expect(NicknameColors.resolve('mint'), const Color(0xFF36F58A));
    // cyan is retained only for historical snapshots.
    expect(NicknameColors.resolve('cyan'), const Color(0xFF20DFFF));
    expect(NicknameColors.resolve('sky'), const Color(0xFF5894FF));
    expect(NicknameColors.resolve('violet'), const Color(0xFFB477FF));
    expect(NicknameColors.resolve('pink'), const Color(0xFFFF4FA7));
    expect(NicknameColors.resolve('gold'), const Color(0xFFFFD23F));
    expect(NicknameColors.resolve('unknown'), AppColors.text);
  });

  test('미리보기에서도 폐기한 색상권 구매와 선물을 거부한다', () async {
    final repository = PreviewDailyGameRepository();

    await expectLater(
      repository.purchaseShopItem(
        itemId: 'nickname_color_ticket',
        requestId: 'retired-color-purchase',
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.giftShopItem(
        targetUserId: 'target-user',
        itemId: 'nickname_color_ticket',
      ),
      throwsA(isA<StateError>()),
    );
  });
}

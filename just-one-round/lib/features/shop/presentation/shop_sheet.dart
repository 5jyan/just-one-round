import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/features/profile/domain/nickname_color.dart';
import 'package:just_one_round/features/profile/presentation/nickname_color_choice_list.dart';
import 'package:just_one_round/features/shop/domain/shop_purchase.dart';
import 'package:just_one_round/shared/widgets/coin_mark.dart';
import 'package:just_one_round/shared/widgets/pixel_action_dialog.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

class ShopSheetResult {
  const ShopSheetResult({
    required this.purchased,
    this.editNickname = false,
    this.nicknameChangeTickets,
  });

  final bool purchased;
  final bool editNickname;
  final int? nicknameChangeTickets;
}

Future<ShopSheetResult?> showShopSheet(
  BuildContext context, {
  required PlayerEconomy economy,
  required String nickname,
  required String nicknameColor,
  required int practiceTickets,
  required int challengeTickets,
  required int nicknameColorTickets,
  required int nicknameChangeTickets,
  required Future<ShopPurchaseResult> Function(String itemId) onPurchase,
  required Future<ShopPurchaseResult> Function(String color)
  onPurchaseNicknameColor,
  required Future<void> Function(String color) onSetNicknameColor,
}) => showModalBottomSheet<ShopSheetResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _ShopSheet(
    economy: economy,
    nickname: nickname,
    nicknameColor: nicknameColor,
    practiceTickets: practiceTickets,
    challengeTickets: challengeTickets,
    nicknameColorTickets: nicknameColorTickets,
    nicknameChangeTickets: nicknameChangeTickets,
    onPurchase: onPurchase,
    onPurchaseNicknameColor: onPurchaseNicknameColor,
    onSetNicknameColor: onSetNicknameColor,
  ),
);

class _ShopSheet extends StatefulWidget {
  const _ShopSheet({
    required this.economy,
    required this.nickname,
    required this.nicknameColor,
    required this.practiceTickets,
    required this.challengeTickets,
    required this.nicknameColorTickets,
    required this.nicknameChangeTickets,
    required this.onPurchase,
    required this.onPurchaseNicknameColor,
    required this.onSetNicknameColor,
  });

  final PlayerEconomy economy;
  final String nickname;
  final String nicknameColor;
  final int practiceTickets;
  final int challengeTickets;
  final int nicknameColorTickets;
  final int nicknameChangeTickets;
  final Future<ShopPurchaseResult> Function(String itemId) onPurchase;
  final Future<ShopPurchaseResult> Function(String color)
  onPurchaseNicknameColor;
  final Future<void> Function(String color) onSetNicknameColor;

  @override
  State<_ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<_ShopSheet> {
  late var _economy = widget.economy;
  late var _practiceTickets = widget.practiceTickets;
  late var _challengeTickets = widget.challengeTickets;
  late var _nicknameColorTickets = widget.nicknameColorTickets;
  late var _nicknameChangeTickets = widget.nicknameChangeTickets;
  late var _nicknameColor = widget.nicknameColor;
  String? _buyingItem;
  String? _message;
  var _purchased = false;

  ShopSheetResult _result({bool editNickname = false}) => ShopSheetResult(
    purchased: _purchased,
    editNickname: editNickname,
    nicknameChangeTickets: _nicknameChangeTickets,
  );

  String _itemLabel(String itemId) => switch (itemId) {
    'practice_ticket' => '연습권 1장',
    'challenge_ticket' => '도전권 1장',
    'nickname_color_ticket' => '닉네임 색상권 1장',
    'nickname_change_ticket' => '닉네임 변경권 1장',
    _ => '아이템 1장',
  };

  int _itemPrice(String itemId) => switch (itemId) {
    'practice_ticket' => ShopCatalog.practiceTicketPrice,
    'challenge_ticket' => ShopCatalog.challengeTicketPrice,
    'nickname_color_ticket' => ShopCatalog.nicknameColorTicketPrice,
    'nickname_change_ticket' => ShopCatalog.nicknameChangeTicketPrice,
    _ => 0,
  };

  Future<bool> _confirmPurchase(String itemId) async {
    if (_buyingItem != null) return false;
    setState(() {
      _buyingItem = 'confirming_$itemId';
      _message = null;
    });
    final confirmed = await showPixelConfirmationDialog(
      context,
      title: '구매할까요?',
      message: '${_itemLabel(itemId)}을 ${_itemPrice(itemId)} C에 구매해요.',
      confirmLabel: '구매하기',
      dialogKey: const Key('shop-purchase-confirmation'),
      titleKey: const Key('shop-purchase-confirmation-title'),
      messageKey: const Key('shop-purchase-confirmation-message'),
      cancelKey: const Key('shop-purchase-cancel'),
      confirmKey: const Key('shop-purchase-confirm'),
    );
    if (!mounted) return false;
    setState(() => _buyingItem = null);
    return confirmed == true;
  }

  Future<bool> _confirmNicknameColor(
    String color, {
    required bool purchaseMode,
  }) async {
    if (_buyingItem != null) return false;
    setState(() {
      _buyingItem = 'confirming_nickname_color';
      _message = null;
    });
    final label = NicknameColors.label(color);
    final confirmed = await showPixelConfirmationDialog(
      context,
      title: '색상을 적용할까요?',
      message: purchaseMode
          ? '닉네임을 $label 색상으로 바꾸고 ${ShopCatalog.nicknameColorTicketPrice} C를 결제해요.'
          : '닉네임을 $label 색상으로 바꾸고 색상권 1장을 사용해요.',
      confirmLabel: purchaseMode ? '구매 후 적용' : '적용하기',
      dialogKey: const Key('nickname-color-confirmation'),
      titleKey: const Key('nickname-color-confirmation-title'),
      messageKey: const Key('nickname-color-confirmation-message'),
      cancelKey: const Key('nickname-color-cancel'),
      confirmKey: const Key('nickname-color-confirm'),
    );
    if (!mounted) return false;
    setState(() => _buyingItem = null);
    return confirmed == true;
  }

  Future<void> _buy(String itemId) async {
    if (_buyingItem != null) return;
    if (!await _confirmPurchase(itemId) || !mounted) return;
    setState(() {
      _buyingItem = itemId;
      _message = null;
    });
    try {
      final result = await widget.onPurchase(itemId);
      if (!mounted) return;
      setState(() {
        _economy = result.economy;
        _practiceTickets = result.practiceTickets;
        _challengeTickets = result.challengeTickets;
        _nicknameColorTickets = result.nicknameColorTickets;
        _nicknameChangeTickets = result.nicknameChangeTickets;
        _purchased = true;
        _message = null;
      });
      unawaited(HapticFeedback.mediumImpact());
      if (itemId == 'nickname_change_ticket') {
        final editNow = await showPixelConfirmationDialog(
          context,
          title: '변경권을 샀어요!',
          message: '지금 닉네임을 바꿀까요? 변경권은 나중에도 사용할 수 있어요.',
          confirmLabel: '바로 변경',
          cancelLabel: '나중에',
          dialogKey: const Key('shop-nickname-change-after-purchase'),
          titleKey: const Key('shop-nickname-change-after-purchase-title'),
          messageKey: const Key('shop-nickname-change-after-purchase-message'),
          cancelKey: const Key('shop-nickname-change-after-purchase-later'),
          confirmKey: const Key('shop-nickname-change-after-purchase-now'),
        );
        if (!mounted) return;
        if (editNow == true) {
          Navigator.of(context).pop(_result(editNickname: true));
          return;
        }
      }
    } catch (error) {
      if (!mounted) return;
      final insufficient = error.toString().contains('insufficient coin');
      setState(() {
        _message = insufficient ? '코인이 부족해요.' : '구매하지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    } finally {
      if (mounted) setState(() => _buyingItem = null);
    }
  }

  Future<void> _selectNicknameColor(String color) async {
    if (_buyingItem != null ||
        _nicknameColorTickets <= 0 ||
        color == _nicknameColor) {
      return;
    }
    setState(() {
      _buyingItem = 'nickname_color_select';
      _message = null;
    });
    try {
      await widget.onSetNicknameColor(color);
      if (!mounted) return;
      setState(() {
        _nicknameColor = color;
        _nicknameColorTickets--;
        _purchased = true;
        _message = null;
      });
      unawaited(HapticFeedback.mediumImpact());
    } catch (_) {
      if (mounted) {
        setState(() => _message = '색상을 적용하지 못했어요. 색상권을 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _buyingItem = null);
    }
  }

  Future<void> _openNicknameColorChooser() async {
    if (_buyingItem != null) return;
    final purchaseMode = _nicknameColorTickets <= 0;
    final color = await showNicknameColorChoiceSheet(
      context,
      nickname: widget.nickname,
      selectedColor: _nicknameColor,
      purchaseMode: purchaseMode,
      price: ShopCatalog.nicknameColorTicketPrice,
    );
    if (!mounted || color == null || color == _nicknameColor) return;
    if (purchaseMode) {
      if (await _confirmNicknameColor(color, purchaseMode: true) && mounted) {
        await _purchaseNicknameColor(color);
      }
    } else {
      if (await _confirmNicknameColor(color, purchaseMode: false) && mounted) {
        await _selectNicknameColor(color);
      }
    }
  }

  Future<void> _purchaseNicknameColor(String color) async {
    if (_buyingItem != null) return;
    setState(() {
      _buyingItem = 'nickname_color_ticket';
      _message = null;
    });
    try {
      final result = await widget.onPurchaseNicknameColor(color);
      if (!mounted) return;
      setState(() {
        _economy = result.economy;
        _practiceTickets = result.practiceTickets;
        _challengeTickets = result.challengeTickets;
        _nicknameColorTickets = result.nicknameColorTickets;
        _nicknameChangeTickets = result.nicknameChangeTickets;
        _nicknameColor = color;
        _purchased = true;
        _message = null;
      });
      unawaited(HapticFeedback.mediumImpact());
    } catch (error) {
      if (!mounted) return;
      final insufficient = error.toString().contains('insufficient coin');
      setState(() {
        _message = insufficient
            ? '코인이 부족해요.'
            : '색상을 적용하지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    } finally {
      if (mounted) setState(() => _buyingItem = null);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: PixelPanel(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: WordSafeText(
                      '코인 상점',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _Wallet(coins: _economy.coins),
                  IconButton(
                    key: const Key('shop-close'),
                    onPressed: () => Navigator.of(context).pop(_result()),
                    icon: const Icon(Icons.close, color: AppColors.text),
                    tooltip: '닫기',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ShopItem(
                key: const Key('shop-practice-ticket'),
                icon: Icons.confirmation_number_rounded,
                title: '연습권 1장',
                description: '연습할 때 사용',
                owned: _practiceTickets,
                price: ShopCatalog.practiceTicketPrice,
                busy: _buyingItem == 'practice_ticket',
                enabled:
                    _buyingItem == null &&
                    _economy.coins >= ShopCatalog.practiceTicketPrice,
                onBuy: () => _buy('practice_ticket'),
              ),
              const SizedBox(height: 10),
              _ShopItem(
                key: const Key('shop-challenge-ticket'),
                icon: Icons.sports_score_rounded,
                title: '도전권 1장',
                description: '추가 도전에 사용',
                owned: _challengeTickets,
                price: ShopCatalog.challengeTicketPrice,
                busy: _buyingItem == 'challenge_ticket',
                enabled:
                    _buyingItem == null &&
                    _economy.coins >= ShopCatalog.challengeTicketPrice,
                onBuy: () => _buy('challenge_ticket'),
              ),
              const SizedBox(height: 10),
              _ShopItem(
                key: const Key('shop-nickname-change-ticket'),
                icon: Icons.edit_outlined,
                title: '닉네임 변경권 1장',
                description: '닉네임을 바꿀 때 사용',
                owned: _nicknameChangeTickets,
                price: ShopCatalog.nicknameChangeTicketPrice,
                busy: _buyingItem == 'nickname_change_ticket',
                enabled:
                    _buyingItem == null &&
                    _economy.coins >= ShopCatalog.nicknameChangeTicketPrice,
                onBuy: () => _buy('nickname_change_ticket'),
              ),
              const SizedBox(height: 10),
              _NicknameColorItem(
                key: const Key('shop-nickname-color-ticket'),
                selectedColor: _nicknameColor,
                colorTickets: _nicknameColorTickets,
                price: ShopCatalog.nicknameColorTicketPrice,
                busy:
                    _buyingItem == 'nickname_color_ticket' ||
                    _buyingItem == 'nickname_color_select',
                enabled:
                    _buyingItem == null &&
                    (_nicknameColorTickets > 0 ||
                        _economy.coins >= ShopCatalog.nicknameColorTicketPrice),
                onChoose: () => unawaited(_openNicknameColorChooser()),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                WordSafeText(
                  _message!,
                  key: const Key('shop-message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.reward,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const WordSafeText(
                '구매한 티켓은 소멸되지 않고 다음 날에도 이월돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Wallet extends StatefulWidget {
  const _Wallet({required this.coins});

  final int coins;

  @override
  State<_Wallet> createState() => _WalletState();
}

class _WalletState extends State<_Wallet> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late var _fromCoins = widget.coins;
  late var _targetCoins = widget.coins;
  var _delta = 0;
  var _showGain = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 720),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _showGain = false);
          }
        });
  }

  @override
  void didUpdateWidget(covariant _Wallet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coins == oldWidget.coins) return;
    _fromCoins = oldWidget.coins;
    _targetCoins = widget.coins;
    _delta = widget.coins - oldWidget.coins;
    _showGain = _delta > 0;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final progress = Curves.easeOutCubic.transform(_controller.value);
      final visibleCoins =
          _fromCoins + ((_targetCoins - _fromCoins) * progress).round();
      final pulseProgress = _showGain
          ? (1 - ((progress * 2) - 1).abs()).clamp(0.0, 1.0).toDouble()
          : 0.0;
      const particleOffsets = [
        Offset(-24, -8),
        Offset(24, -8),
        Offset(-20, 10),
        Offset(20, 10),
      ];

      return Stack(
        key: const Key('shop-coin-balance-effect'),
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (_showGain)
            for (var index = 0; index < particleOffsets.length; index++)
              Transform.translate(
                offset: Offset(
                  particleOffsets[index].dx * progress,
                  particleOffsets[index].dy * progress,
                ),
                child: Opacity(
                  opacity: (1 - progress).clamp(0.0, 1.0).toDouble(),
                  child: Transform.scale(
                    scale: 1 + (1 - progress) * 0.35,
                    child: Icon(
                      key: Key('shop-coin-balance-particle-$index'),
                      index.isEven ? Icons.auto_awesome : Icons.circle,
                      color: index.isEven
                          ? AppColors.primary
                          : AppColors.reward,
                      size: index.isEven ? 11 : 6,
                    ),
                  ),
                ),
              ),
          if (_showGain)
            Positioned(
              top: -24,
              right: -4,
              child: Opacity(
                opacity: (1 - progress).clamp(0.0, 1.0).toDouble(),
                child: Transform.translate(
                  offset: Offset(0, -18 * progress),
                  child: WordSafeText(
                    '+$_delta C',
                    key: const Key('shop-coin-balance-gain'),
                    style: const TextStyle(
                      color: AppColors.reward,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          Transform.scale(
            scale: 1 + (0.08 * pulseProgress),
            child: Container(
              key: const Key('shop-coin-balance'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.backgroundDeep,
                border: Border.all(color: AppColors.primary),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CoinMark(
                    color: AppColors.primary,
                    inkColor: AppColors.backgroundDeep,
                    size: 17,
                  ),
                  const SizedBox(width: 4),
                  WordSafeText(
                    '$visibleCoins',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _OwnedCountEffect extends StatefulWidget {
  const _OwnedCountEffect({required this.owned});

  final int owned;

  @override
  State<_OwnedCountEffect> createState() => _OwnedCountEffectState();
}

class _OwnedCountEffectState extends State<_OwnedCountEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _particlesVisible = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 560),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _particlesVisible = false);
          }
        });
  }

  @override
  void didUpdateWidget(covariant _OwnedCountEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.owned != oldWidget.owned) {
      setState(() => _particlesVisible = true);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween<double>(begin: 0.84, end: 1).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: WordSafeText(
        '보유 ${widget.owned}장',
        key: ValueKey(widget.owned),
        style: const TextStyle(
          color: AppColors.reward,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
    builder: (context, child) {
      final progress = Curves.easeOutCubic.transform(_controller.value);
      final opacity = (1 - progress).clamp(0.0, 1.0).toDouble();
      const particleOffsets = [
        Offset(-22, -8),
        Offset(22, -8),
        Offset(-18, 10),
        Offset(18, 10),
      ];

      return Stack(
        key: const Key('shop-owned-count-effect'),
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (_particlesVisible)
            for (var index = 0; index < particleOffsets.length; index++)
              Transform.translate(
                offset: Offset(
                  particleOffsets[index].dx * progress,
                  particleOffsets[index].dy * progress,
                ),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: 1 + (1 - progress) * 0.35,
                    child: Icon(
                      key: Key('shop-owned-count-particle-$index'),
                      index.isEven ? Icons.auto_awesome : Icons.circle,
                      color: index.isEven
                          ? AppColors.primary
                          : AppColors.reward,
                      size: index.isEven ? 11 : 6,
                    ),
                  ),
                ),
              ),
          child!,
        ],
      );
    },
  );
}

class _NicknameColorItem extends StatelessWidget {
  const _NicknameColorItem({
    required this.selectedColor,
    required this.colorTickets,
    required this.price,
    required this.busy,
    required this.enabled,
    required this.onChoose,
    super.key,
  });

  final String selectedColor;
  final int colorTickets;
  final int price;
  final bool busy;
  final bool enabled;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final hasColorChoice = colorTickets > 0;
    final description = hasColorChoice
        ? '색상권 1장으로 내 닉네임 색상을 선택'
        : selectedColor == 'default'
        ? '버튼을 눌러 내 닉네임 색상을 선택'
        : '${NicknameColors.label(selectedColor)} 적용 중 · 다시 바꾸려면 구매';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundDeep,
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.palette_outlined,
              color: AppColors.primary,
              size: 34,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WordSafeText(
                  hasColorChoice ? '닉네임 색상 고르기' : '닉네임 색상권',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                WordSafeText(
                  description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: enabled ? onChoose : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.backgroundDeep,
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : hasColorChoice
                ? const WordSafeText('색상 고르기')
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CoinMark(
                        color: AppColors.backgroundDeep,
                        inkColor: AppColors.primary,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      WordSafeText('$price'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ShopItem extends StatelessWidget {
  const _ShopItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.owned,
    required this.price,
    required this.busy,
    required this.enabled,
    required this.onBuy,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final int owned;
  final int price;
  final bool busy;
  final bool enabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.backgroundDeep,
      border: Border.all(color: AppColors.border, width: 2),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WordSafeText(
                title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              WordSafeText(
                description,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 5),
              _OwnedCountEffect(owned: owned),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: enabled ? onBuy : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.backgroundDeep,
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CoinMark(
                      color: AppColors.backgroundDeep,
                      inkColor: AppColors.primary,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    WordSafeText('$price'),
                  ],
                ),
        ),
      ],
    ),
  );
}

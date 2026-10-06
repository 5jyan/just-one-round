import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/profile/domain/nickname_color.dart';
import 'package:just_one_round/shared/widgets/coin_mark.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

Future<String?> showNicknameColorChoiceSheet(
  BuildContext context, {
  required String nickname,
  required String selectedColor,
  required bool purchaseMode,
  required int price,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _NicknameColorChoiceSheet(
    nickname: nickname,
    selectedColor: selectedColor,
    purchaseMode: purchaseMode,
    price: price,
  ),
);

class _NicknameColorChoiceSheet extends StatelessWidget {
  const _NicknameColorChoiceSheet({
    required this.nickname,
    required this.selectedColor,
    required this.purchaseMode,
    required this.price,
  });

  final String nickname;
  final String selectedColor;
  final bool purchaseMode;
  final int price;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: PixelPanel(
          key: const Key('nickname-color-choice-sheet'),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: WordSafeText(
                      '닉네임 색상 고르기',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('nickname-color-choice-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.text),
                    tooltip: '닫기',
                  ),
                ],
              ),
              WordSafeText(
                purchaseMode
                    ? '색상을 고르면 $price C를 사용해요.'
                    : '보유한 색상권 1장으로 색상을 바꿔요.',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (purchaseMode) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CoinMark(
                      color: AppColors.primary,
                      inkColor: AppColors.backgroundDeep,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    WordSafeText(
                      '$price C 결제 후 바로 적용',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              NicknameColorChoiceList(
                nickname: nickname,
                selectedColor: selectedColor,
                enabled: true,
                onSelected: (color) => Navigator.of(context).pop(color),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class NicknameColorChoiceList extends StatelessWidget {
  const NicknameColorChoiceList({
    required this.nickname,
    required this.selectedColor,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final String nickname;
  final String selectedColor;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final displayName = nickname.trim().isEmpty ? '내 닉네임' : nickname.trim();

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final token in NicknameColors.selectableTokens)
          MergeSemantics(
            child: Semantics(
              label: '${NicknameColors.label(token)} 색상, $displayName',
              selected: selectedColor == token,
              button: true,
              child: ChoiceChip(
                key: ValueKey('nickname-color-choice-$token'),
                selected: selectedColor == token,
                showCheckmark: false,
                avatar: CircleAvatar(
                  radius: 8,
                  backgroundColor: NicknameColors.resolve(token),
                ),
                label: WordSafeText(displayName),
                labelStyle: TextStyle(
                  color: NicknameColors.resolve(token),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
                backgroundColor: AppColors.backgroundDeep,
                selectedColor: NicknameColors.resolve(
                  token,
                ).withValues(alpha: 0.18),
                side: BorderSide(
                  color: selectedColor == token
                      ? NicknameColors.resolve(token)
                      : AppColors.border,
                  width: 1.5,
                ),
                onSelected: enabled && selectedColor != token
                    ? (_) => onSelected(token)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/features/profile/domain/nickname_color.dart';
import 'package:just_one_round/features/referral/domain/referral.dart';
import 'package:just_one_round/shared/widgets/coin_mark.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

enum ProfileAction { editNickname, nicknameColor, linkKakao, inviteFriends }

Future<ProfileAction?> showProfileSheet(
  BuildContext context, {
  required String? nickname,
  required PlayerEconomy economy,
  required bool kakaoConfigured,
  required bool kakaoLinked,
  required bool isAnonymousAccount,
  String nicknameColor = 'default',
  int nicknameChangeTickets = 0,
  ReferralStatus referralStatus = const ReferralStatus.empty(),
}) {
  return showModalBottomSheet<ProfileAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ProfileSheet(
      nickname: nickname,
      economy: economy,
      kakaoConfigured: kakaoConfigured,
      kakaoLinked: kakaoLinked,
      isAnonymousAccount: isAnonymousAccount,
      nicknameColor: nicknameColor,
      nicknameChangeTickets: nicknameChangeTickets,
      referralStatus: referralStatus,
    ),
  );
}

class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet({
    required this.nickname,
    required this.economy,
    required this.kakaoConfigured,
    required this.kakaoLinked,
    required this.isAnonymousAccount,
    required this.nicknameColor,
    required this.nicknameChangeTickets,
    required this.referralStatus,
  });

  final String? nickname;
  final PlayerEconomy economy;
  final bool kakaoConfigured;
  final bool kakaoLinked;
  final bool isAnonymousAccount;
  final String nicknameColor;
  final int nicknameChangeTickets;
  final ReferralStatus referralStatus;

  @override
  Widget build(BuildContext context) {
    final displayName = nickname?.trim().isNotEmpty == true
        ? nickname!.trim()
        : '닉네임 미설정';
    final accountLabel = kakaoLinked
        ? '카카오 계정 연결됨'
        : isAnonymousAccount
        ? '익명 계정'
        : '일반 계정';
    final hasCustomNickname =
        nickname?.trim().isNotEmpty == true &&
        !RegExp(r'^신원미상#[0-9]+$').hasMatch(nickname!.trim());

    return SingleChildScrollView(
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
                        '프로필',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('profile-close'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: AppColors.text),
                      tooltip: '닫기',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        border: Border.all(color: AppColors.text, width: 2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppColors.backgroundDeep,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WordSafeText(
                            displayName,
                            key: const Key('profile-display-name'),
                            style: TextStyle(
                              color: NicknameColors.resolve(nicknameColor),
                              fontFamily: 'Galmuri',
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          WordSafeText(
                            accountLabel,
                            key: const Key('profile-account-status'),
                            style: TextStyle(
                              color: kakaoLinked || !isAnonymousAccount
                                  ? AppColors.reward
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _EconomyCard(economy: economy),
                const SizedBox(height: 14),
                _ProfileActionTile(
                  key: const Key('profile-nickname-action'),
                  icon: Icons.badge_outlined,
                  title: '닉네임 설정',
                  subtitle: hasCustomNickname
                      ? nicknameChangeTickets > 0
                            ? '랭킹에 표시되는 이름을 바꿔요. 변경권 ${nicknameChangeTickets.toString()}장 보유'
                            : '랭킹에 표시되는 이름을 바꿔요. 변경권이 필요해요.'
                      : '랭킹에 표시할 이름을 정해 주세요.',
                  onTap: () =>
                      Navigator.of(context).pop(ProfileAction.editNickname),
                ),
                const SizedBox(height: 8),
                _ProfileActionTile(
                  key: const Key('profile-nickname-color-action'),
                  icon: Icons.palette_outlined,
                  title: '닉네임 색상',
                  subtitle:
                      '${NicknameColors.label(nicknameColor)} 적용 중 · 변경은 색상권 필요',
                  onTap: () =>
                      Navigator.of(context).pop(ProfileAction.nicknameColor),
                ),
                const SizedBox(height: 8),
                _ProfileActionTile(
                  key: const Key('profile-kakao-action'),
                  icon: Icons.login,
                  title: kakaoLinked ? '카카오 계정 연결됨' : '카카오 계정 연결',
                  subtitle: kakaoLinked
                      ? '기기 변경 후에도 기록을 이어갈 수 있어요.'
                      : kakaoConfigured
                      ? '기기를 바꿔도 기록을 이어가려면 연결해 주세요.'
                      : '앱 키 설정 후 사용할 수 있어요.',
                  accent: kakaoLinked ? AppColors.reward : AppColors.primary,
                  onTap: () =>
                      Navigator.of(context).pop(ProfileAction.linkKakao),
                ),
                const SizedBox(height: 8),
                _ProfileActionTile(
                  key: const Key('profile-referral-action'),
                  icon: Icons.group_add_outlined,
                  title: '친구 초대하고 도전권 받기',
                  subtitle: referralStatus.invitedCount == 0
                      ? '친구가 첫 연습 또는 도전을 시작하면 도전권 1장을 받아요.'
                      : '완료 ${referralStatus.completedCount}명 · 대기 ${referralStatus.pendingCount}명',
                  accent: AppColors.reward,
                  onTap: () =>
                      Navigator.of(context).pop(ProfileAction.inviteFriends),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EconomyCard extends StatelessWidget {
  const _EconomyCard({required this.economy});

  final PlayerEconomy economy;

  @override
  Widget build(BuildContext context) {
    final levelStart = (economy.level - 1) * (economy.level - 1) * 100;
    final levelEnd = economy.level * economy.level * 100;
    final progress =
        ((economy.experiencePoints - levelStart) /
                max(1, levelEnd - levelStart))
            .clamp(0.0, 1.0)
            .toDouble();

    return Container(
      key: const Key('profile-economy-card'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      decoration: BoxDecoration(
        color: AppColors.backgroundDeep,
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ProfileMetric(
                  icon: const CoinMark(
                    color: AppColors.primary,
                    inkColor: AppColors.backgroundDeep,
                    size: 18,
                  ),
                  value: '${economy.coins}',
                  label: 'COINS',
                  color: AppColors.primary,
                ),
              ),
              Container(width: 1, height: 38, color: AppColors.surfaceLight),
              Expanded(
                child: _ProfileMetric(
                  icon: const Icon(Icons.auto_awesome_outlined),
                  value: '${economy.experiencePoints}',
                  label: 'EXP',
                  color: AppColors.reward,
                ),
              ),
              Container(width: 1, height: 38, color: AppColors.surfaceLight),
              Expanded(
                child: _ProfileMetric(
                  icon: const Icon(Icons.arrow_upward_rounded),
                  value: 'LV.${economy.level}',
                  label: 'LEVEL',
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const WordSafeText(
                '다음 레벨 진행도',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              WordSafeText(
                '${economy.experienceToNextLevel} EXP 남음',
                style: const TextStyle(
                  color: AppColors.reward,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.zero,
            child: LinearProgressIndicator(
              key: const Key('profile-exp-progress'),
              minHeight: 8,
              value: progress,
              backgroundColor: AppColors.surfaceLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.reward),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final Widget icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      IconTheme(
        data: IconThemeData(color: color, size: 18),
        child: icon,
      ),
      const SizedBox(height: 3),
      WordSafeText(
        value,
        style: TextStyle(
          color: color,
          fontFamily: 'Galmuri',
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 2),
      WordSafeText(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    ],
  );
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = AppColors.text,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.backgroundDeep,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WordSafeText(
                    title,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  WordSafeText(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    ),
  );
}

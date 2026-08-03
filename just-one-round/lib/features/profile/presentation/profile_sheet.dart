import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';

enum ProfileAction { editNickname, linkKakao }

Future<ProfileAction?> showProfileSheet(
  BuildContext context, {
  required String? nickname,
  required PlayerEconomy economy,
  required bool kakaoConfigured,
  required bool kakaoLinked,
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
    ),
  );
}

class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet({
    required this.nickname,
    required this.economy,
    required this.kakaoConfigured,
    required this.kakaoLinked,
  });

  final String? nickname;
  final PlayerEconomy economy;
  final bool kakaoConfigured;
  final bool kakaoLinked;

  @override
  Widget build(BuildContext context) {
    final displayName = nickname?.trim().isNotEmpty == true
        ? nickname!.trim()
        : '닉네임 미설정';
    final accountLabel = kakaoLinked ? '카카오 계정 연결됨' : '익명 계정';

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
                      child: Text(
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
                          Text(
                            displayName,
                            key: const Key('profile-display-name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontFamily: 'Galmuri',
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            accountLabel,
                            key: const Key('profile-account-status'),
                            style: TextStyle(
                              color: kakaoLinked
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
                  subtitle: nickname?.trim().isNotEmpty == true
                      ? '랭킹에 표시되는 이름을 바꿔요.'
                      : '랭킹에 표시할 이름을 정해 주세요.',
                  onTap: () =>
                      Navigator.of(context).pop(ProfileAction.editNickname),
                ),
                const SizedBox(height: 8),
                _ProfileActionTile(
                  key: const Key('profile-kakao-action'),
                  icon: Icons.login,
                  title: kakaoLinked ? '카카오 계정 연결됨' : '카카오 계정 연결',
                  subtitle: kakaoLinked
                      ? '기기 변경 후에도 기록을 이어갈 수 있어요.'
                      : kakaoConfigured
                      ? '추가 플레이와 기록 보존을 위해 연결해 주세요.'
                      : '앱 키 설정 후 사용할 수 있어요.',
                  accent: kakaoLinked ? AppColors.reward : AppColors.primary,
                  onTap: () =>
                      Navigator.of(context).pop(ProfileAction.linkKakao),
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
                  icon: Icons.monetization_on_outlined,
                  value: '${economy.coins}',
                  label: 'COINS',
                  color: AppColors.primary,
                ),
              ),
              Container(width: 1, height: 38, color: AppColors.surfaceLight),
              Expanded(
                child: _ProfileMetric(
                  icon: Icons.auto_awesome_outlined,
                  value: '${economy.experiencePoints}',
                  label: 'EXP',
                  color: AppColors.reward,
                ),
              ),
              Container(width: 1, height: 38, color: AppColors.surfaceLight),
              Expanded(
                child: _ProfileMetric(
                  icon: Icons.arrow_upward_rounded,
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
              const Text(
                '다음 레벨 진행도',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
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

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 3),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontFamily: 'Galmuri',
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 2),
      Text(
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
                  Text(
                    title,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
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

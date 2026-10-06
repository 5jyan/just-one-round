import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

class CriticalOtaRestartScreen extends StatelessWidget {
  const CriticalOtaRestartScreen({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Material(
      key: const Key('critical-ota-restart-screen'),
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.primary, width: 3),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.primaryShadow,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _UpdateIcon(),
                      const SizedBox(height: 24),
                      const WordSafeText(
                        '앱을 종료한 뒤\n다시 열어주세요',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Galmuri',
                          color: AppColors.text,
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      WordSafeText(
                        message,
                        key: const Key('critical-ota-restart-message'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundDeep,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.surfaceLight),
                        ),
                        child: const WordSafeText(
                          '새 업데이트는 다음 실행부터 적용돼요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _UpdateIcon extends StatelessWidget {
  const _UpdateIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 82,
    height: 82,
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.text, width: 3),
      boxShadow: const [
        BoxShadow(color: AppColors.primaryShadow, offset: Offset(0, 6)),
      ],
    ),
    child: const Icon(
      Icons.system_update_alt_rounded,
      color: AppColors.backgroundDeep,
      size: 46,
    ),
  );
}

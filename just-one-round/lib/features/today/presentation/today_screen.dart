import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _PixelGridBackground()),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Header(),
                      const SizedBox(height: 32),
                      PixelPanel(
                        child: Column(
                          children: [
                            const _GamePreview(),
                            const SizedBox(height: 24),
                            Text(
                              '별빛 피하기',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '장애물을 피하고 별을 모아\n오늘의 최고 기록에 도전하세요.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 20),
                            const _GameMeta(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      PixelButton(
                        label: '오늘의 한 판 시작',
                        icon: Icons.play_arrow_rounded,
                        onPressed: () => context.go('/play'),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '아직 플레이하지 않았어요 · 기회 1회',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('딱한판만', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 6),
              Text(
                '${_monthName(DateTime.now().month)} ${DateTime.now().day} · 오늘의 게임',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '설정',
          onPressed: () {},
          icon: const Icon(Icons.settings_outlined, color: AppColors.text),
        ),
      ],
    );
  }
}

String _monthName(int month) {
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return months[month - 1];
}

class _GamePreview extends StatelessWidget {
  const _GamePreview();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.backgroundDeep,
          border: Border.all(color: AppColors.surfaceLight, width: 2),
        ),
        child: const Stack(
          children: [
            Positioned(left: 30, top: 24, child: _PixelStar(size: 18)),
            Positioned(right: 38, top: 44, child: _PixelStar(size: 12)),
            Positioned(left: 84, bottom: 24, child: _PixelStar(size: 10)),
            Center(
              child: Icon(
                Icons.rocket_launch_rounded,
                color: AppColors.reward,
                size: 62,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelStar extends StatelessWidget {
  const _PixelStar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.star, size: size, color: AppColors.primary);
  }
}

class _GameMeta extends StatelessWidget {
  const _GameMeta();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MetaItem(icon: Icons.timer_outlined, label: '60초'),
        SizedBox(width: 24),
        _MetaItem(icon: Icons.touch_app_outlined, label: '한 손'),
        SizedBox(width: 24),
        _MetaItem(icon: Icons.public, label: '전체 순위'),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.reward, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PixelGridBackground extends StatelessWidget {
  const _PixelGridBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.surface.withValues(alpha: 0.28);
    const gap = 24.0;

    for (var x = 0.0; x < size.width; x += gap) {
      for (var y = 0.0; y < size.height; y += gap) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

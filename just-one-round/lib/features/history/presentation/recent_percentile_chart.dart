import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/history/domain/play_history_statistics.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

class RecentPercentileChart extends StatelessWidget {
  const RecentPercentileChart({
    required this.history,
    required this.referencePlayDate,
    super.key,
  });

  final List<PlayHistoryEntry> history;
  final DateTime referencePlayDate;

  @override
  Widget build(BuildContext context) {
    final buckets = recentPercentileBuckets(history, referencePlayDate);
    final hasRecordedResult = buckets.any(
      (bucket) => bucket.topPercent != null,
    );

    return PixelPanel(
      key: const Key('recent-performance-chart'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WordSafeText(
            '최근 7일 통계',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const WordSafeText(
            '상위 비율이 낮을수록 좋아요',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 8),
          if (hasRecordedResult)
            Semantics(
              key: const Key('recent-performance-chart-semantics'),
              container: true,
              label: _chartSemanticsLabel(buckets),
              child: SizedBox(
                key: const Key('recent-performance-chart-canvas'),
                height: 184,
                child: CustomPaint(
                  painter: RecentPercentileChartPainter(buckets),
                ),
              ),
            )
          else
            const WordSafeText(
              '최근 7일간 기록이 없어요.',
              key: Key('recent-performance-chart-empty'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class RecentPercentileChartPainter extends CustomPainter {
  RecentPercentileChartPainter(this.buckets);

  final List<RecentPercentileBucket> buckets;

  @override
  void paint(Canvas canvas, Size size) {
    const chartLeft = 36.0;
    const chartRightInset = 4.0;
    const chartTop = 20.0;
    const chartBottomInset = 31.0;
    final chartRight = size.width - chartRightInset;
    final chartBottom = size.height - chartBottomInset;
    if (chartRight <= chartLeft || chartBottom <= chartTop) return;

    final chartWidth = chartRight - chartLeft;
    final chartHeight = chartBottom - chartTop;
    final gridPaint = Paint()
      ..color = AppColors.surfaceLight
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = AppColors.reward
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()
      ..color = AppColors.reward
      ..style = PaintingStyle.fill;

    for (final percent in const [1, 50, 100]) {
      final y = _yForPercent(percent, chartTop, chartHeight);
      canvas.drawLine(Offset(chartLeft, y), Offset(chartRight, y), gridPaint);
      _drawText(
        canvas,
        '$percent%',
        const TextStyle(
          color: AppColors.textMuted,
          fontSize: 9,
          fontFamily: 'Galmuri',
        ),
        x: 0,
        y: y - 6,
        maxWidth: chartLeft - 6,
        alignRight: true,
      );
    }

    Offset? previousPoint;
    for (var index = 0; index < buckets.length; index++) {
      final bucket = buckets[index];
      final x = _xForIndex(index, buckets.length, chartLeft, chartWidth);
      final percent = bucket.topPercent;
      if (percent != null) {
        final point = Offset(x, _yForPercent(percent, chartTop, chartHeight));
        if (previousPoint != null) {
          canvas.drawLine(previousPoint, point, linePaint);
        }
        canvas.drawCircle(point, 3.5, pointPaint);
        _drawText(
          canvas,
          '$percent%',
          const TextStyle(
            color: AppColors.reward,
            fontSize: 10,
            fontFamily: 'Galmuri',
            fontWeight: FontWeight.w700,
          ),
          x: x,
          y: point.dy - 17,
          maxWidth: size.width,
        );
        previousPoint = point;
      } else {
        // A missing day must not create a false zero or bridge two points.
        previousPoint = null;
      }

      _drawText(
        canvas,
        '${bucket.date.month}/${bucket.date.day}',
        const TextStyle(color: AppColors.textMuted, fontSize: 9),
        x: x,
        y: chartBottom + 8,
        maxWidth: size.width,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RecentPercentileChartPainter oldDelegate) =>
      oldDelegate.buckets != buckets;
}

double _xForIndex(int index, int count, double left, double width) {
  if (count <= 1) return left + width / 2;
  return left + width * index / (count - 1);
}

double _yForPercent(int percent, double top, double height) {
  final clampedPercent = percent.clamp(1, 100).toDouble();
  return top + height * (clampedPercent - 1) / 99;
}

void _drawText(
  Canvas canvas,
  String text,
  TextStyle style, {
  required double x,
  required double y,
  required double maxWidth,
  bool alignRight = false,
}) {
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final rawX = alignRight
      ? x + maxWidth - textPainter.width
      : x - textPainter.width / 2;
  final maxX = (maxWidth - textPainter.width).clamp(0.0, double.infinity);
  final dx = rawX.clamp(0.0, maxX).toDouble();
  final dy = y.clamp(0.0, double.infinity).toDouble();
  textPainter.paint(canvas, Offset(dx, dy));
}

String _chartSemanticsLabel(List<RecentPercentileBucket> buckets) {
  final details = buckets
      .map((bucket) {
        final date = '${bucket.date.month}/${bucket.date.day}';
        final percent = bucket.topPercent;
        return percent == null ? '$date 기록 없음' : '$date 상위 $percent%';
      })
      .join(', ');
  return '최근 7일 통계. $details';
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/prism_typography.dart';

/// Hex prism step indicator — animated check when complete (Phase 2).
class PrismSlotStep extends StatelessWidget {
  final int stepNumber;
  final bool complete;

  const PrismSlotStep({
    super.key,
    required this.stepNumber,
    required this.complete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return ScaleTransition(
            scale: Tween<double>(begin: 0.65, end: 1).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: complete
            ? CustomPaint(
                key: const ValueKey('done'),
                painter: _HexPrismPainter(filled: true),
                child: const Center(
                  child: Icon(Icons.check_rounded, size: 18, color: Colors.white),
                ),
              )
            : CustomPaint(
                key: ValueKey('open-$stepNumber'),
                painter: _HexPrismPainter(filled: false),
                child: Center(
                  child: Text(
                    '$stepNumber',
                    style: PrismTypography.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _HexPrismPainter extends CustomPainter {
  final bool filled;

  _HexPrismPainter({required this.filled});

  @override
  void paint(Canvas canvas, Size size) {
    final path = _hexPath(size);
    if (filled) {
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.success.withValues(alpha: 0.95),
            AppColors.success.withValues(alpha: 0.65),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size);
      canvas.drawPath(path, paint);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.success.withValues(alpha: 0.9),
      );
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.outline,
      );
    }
  }

  Path _hexPath(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(size.width, size.height) / 2 - 1.5;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (i * 60 - 90) * math.pi / 180;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HexPrismPainter oldDelegate) =>
      oldDelegate.filled != filled;
}

import 'package:flutter/material.dart';
import '../../../core/models/track_a_result.dart';
import '../../../shared/theme/prism_tokens.dart';
import '../../../shared/theme/prism_typography.dart';

class ConfidenceBadge extends StatelessWidget {
  final ConfidenceLevel level;

  const ConfidenceBadge({
    super.key,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, _, label) = _getBadgeStyles();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: crystalBorderRadius(),
        border: Border.all(
          color: color.withValues(alpha: 0.38),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: PrismTypography.publicSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, Color, String) _getBadgeStyles() {
    switch (level) {
      case ConfidenceLevel.high:
        return (
          Icons.check_circle,
          const Color(0xFF059669),
          const Color(0xFFD1FAE5),
          'High confidence',
        );
      case ConfidenceLevel.medium:
        return (
          Icons.warning_amber,
          const Color(0xFFB45309),
          const Color(0xFFFEF3C7),
          'Review recommended',
        );
      case ConfidenceLevel.low:
        return (
          Icons.error_outline,
          const Color(0xFFDC2626),
          const Color(0xFFFEE2E2),
          'Please verify',
        );
      case ConfidenceLevel.uncertain:
        return (
          Icons.help_outline,
          const Color(0xFF64748B),
          const Color(0xFFF1F5F9),
          'Uncertain',
        );
    }
  }
}

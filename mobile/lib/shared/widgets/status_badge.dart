import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/prism_typography.dart';

/// Status badge types for the CivicLens app
enum StatusType {
  satisfied,
  questionable,
  missing,
  highConfidence,
  mediumConfidence,
  lowConfidence,
}

/// A reusable status badge component
class StatusBadge extends StatelessWidget {
  final StatusType type;
  final String? label;
  final bool showIcon;

  const StatusBadge({
    super.key,
    required this.type,
    this.label,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, bgColor, defaultLabel) = _getBadgeStyles();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label ?? defaultLabel,
            style: PrismTypography.publicSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, Color, String) _getBadgeStyles() {
    switch (type) {
      case StatusType.satisfied:
        return (
          Icons.check,
          const Color(0xFF059669),
          AppColors.lightGreen,
          'Satisfied',
        );
      case StatusType.questionable:
        return (
          Icons.help_outline,
          const Color(0xFFB45309),
          AppColors.lightAmber,
          'Questionable',
        );
      case StatusType.missing:
        return (
          Icons.remove,
          AppColors.neutral,
          AppColors.surfaceContainerLow,
          'Missing',
        );
      case StatusType.highConfidence:
        return (
          Icons.check_circle,
          const Color(0xFF059669),
          const Color(0xFFD1FAE5),
          'High confidence',
        );
      case StatusType.mediumConfidence:
        return (
          Icons.warning_amber,
          const Color(0xFFB45309),
          const Color(0xFFFEF3C7),
          'Review recommended',
        );
      case StatusType.lowConfidence:
        return (
          Icons.error_outline,
          const Color(0xFFDC2626),
          const Color(0xFFFEE2E2),
          'Please verify',
        );
    }
  }
}

import 'package:flutter/material.dart';
import '../../../core/models/track_a_result.dart';

class ConfidenceBadge extends StatelessWidget {
  final ConfidenceLevel level;

  const ConfidenceBadge({
    super.key,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, bgColor, label) = _getBadgeStyles();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
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

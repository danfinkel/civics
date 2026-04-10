import 'package:flutter/material.dart';
import '../../theme/prism_tokens.dart';
import '../../theme/prism_typography.dart';

/// Prism "crystal" status badge (gradient + asymmetric corners).
class CrystalStatusBadge extends StatelessWidget {
  final Color statusColor;
  final IconData icon;
  final String label;

  const CrystalStatusBadge({
    super.key,
    required this.statusColor,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: 0.15),
            statusColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: crystalBorderRadius(),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: PrismTypography.publicSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}

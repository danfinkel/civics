import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/prism_tokens.dart';
import '../../../shared/theme/prism_typography.dart';

/// High-visibility warning when two documents fall in the same residency category.
class TrackBDuplicateCategoryBanner extends StatelessWidget {
  final String message;

  const TrackBDuplicateCategoryBanner({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(PrismRadii.md),
        border: Border.all(color: AppColors.warning, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.warning.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warning,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: PrismTypography.publicSans(
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF78350F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

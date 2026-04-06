import 'package:flutter/material.dart';
import '../../../core/models/track_b_result.dart';
import '../../../shared/theme/app_theme.dart';
import 'confidence_badge.dart';

class RequirementRow extends StatelessWidget {
  final RequirementResult requirement;

  const RequirementRow({
    super.key,
    required this.requirement,
  });

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusBg, statusText) = _getStatusStyles();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(
          color: const Color(0xFFC3C6CF).withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  requirement.requirement,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStatusIcon(),
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Matched document
          Text(
            requirement.matchedDocument == 'MISSING'
                ? 'No document provided'
                : requirement.matchedDocument,
            style: TextStyle(
              fontSize: 14,
              color: requirement.matchedDocument == 'MISSING'
                  ? AppColors.error
                  : AppColors.neutral,
            ),
          ),
          // Evidence/notes if present
          if (requirement.evidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              requirement.evidence,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.neutral,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (requirement.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              requirement.notes,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.warning,
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Confidence badge
          ConfidenceBadge(level: requirement.confidence),
        ],
      ),
    );
  }

  (Color, Color, String) _getStatusStyles() {
    switch (requirement.status) {
      case RequirementStatus.satisfied:
        return (
          AppColors.success,
          AppColors.lightGreen,
          'Satisfied',
        );
      case RequirementStatus.questionable:
        return (
          const Color(0xFF92400E),
          AppColors.lightAmber,
          'Questionable',
        );
      case RequirementStatus.missing:
        return (
          AppColors.neutral,
          AppColors.surfaceContainerLow,
          'Missing',
        );
    }
  }

  IconData _getStatusIcon() {
    switch (requirement.status) {
      case RequirementStatus.satisfied:
        return Icons.check;
      case RequirementStatus.questionable:
        return Icons.help_outline;
      case RequirementStatus.missing:
        return Icons.remove;
    }
  }
}

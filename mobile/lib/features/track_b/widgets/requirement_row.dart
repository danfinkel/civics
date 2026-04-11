import 'package:flutter/material.dart';
import '../../../core/models/track_b_result.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/prism_tokens.dart';
import '../../../shared/theme/prism_typography.dart';
import '../../../core/utils/eval_mode.dart';
import '../../../core/utils/label_formatter.dart';
import '../../../shared/widgets/prism/crystal_status_badge.dart';
import 'confidence_badge.dart';

class RequirementRow extends StatelessWidget {
  final RequirementResult requirement;

  const RequirementRow({
    super.key,
    required this.requirement,
  });

  String _subtitle() {
    if (requirement.matchedDocument == 'MISSING') {
      return LabelFormatter.assessmentLabel('missing');
    }
    if (kEvalMode) {
      final ev = requirement.evidence.trim();
      if (ev.isNotEmpty) {
        final oneLine = ev.split(RegExp(r'\s+')).join(' ');
        if (oneLine.length <= 100) return oneLine;
        return '${oneLine.substring(0, 100).trim()}…';
      }
    }
    return requirement.matchedDocument;
  }

  @override
  Widget build(BuildContext context) {
    final (statusColor, _, statusText) = _getStatusStyles();
    final theme = Theme.of(context).textTheme;
    final subtitle = _subtitle();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: prismCardDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PrismRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusDisc(status: requirement.status),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            LabelFormatter.requirementLabel(
                              requirement.requirement,
                            ),
                            style: PrismTypography.spaceGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (requirement.status == RequirementStatus.satisfied)
                          _SatisfiedChip()
                        else
                          CrystalStatusBadge(
                            statusColor: statusColor,
                            icon: _getStatusIcon(),
                            label: statusText,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.bodyMedium?.copyWith(
                        color: requirement.matchedDocument == 'MISSING'
                            ? AppColors.error
                            : AppColors.neutral,
                        height: 1.35,
                      ),
                    ),
                    if (kEvalMode && requirement.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        requirement.notes,
                        style: theme.labelSmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                    if (kEvalMode) ...[
                      const SizedBox(height: 10),
                      ConfidenceBadge(level: requirement.confidence),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (Color, Color, String) _getStatusStyles() {
    final label =
        LabelFormatter.requirementStatusLabel(requirement.status.name);
    switch (requirement.status) {
      case RequirementStatus.satisfied:
        return (
          AppColors.success,
          AppColors.lightGreen,
          label,
        );
      case RequirementStatus.questionable:
        return (
          const Color(0xFF92400E),
          AppColors.lightAmber,
          label,
        );
      case RequirementStatus.missing:
        return (
          AppColors.neutral,
          AppColors.surfaceContainerLow,
          label,
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

class _StatusDisc extends StatelessWidget {
  final RequirementStatus status;

  const _StatusDisc({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, icon, iconColor) = switch (status) {
      RequirementStatus.satisfied => (
          AppColors.primary,
          Icons.check_rounded,
          Colors.white,
        ),
      RequirementStatus.questionable => (
          const Color(0xFFD97706),
          Icons.help_outline_rounded,
          Colors.white,
        ),
      RequirementStatus.missing => (
          AppColors.neutral.withValues(alpha: 0.35),
          Icons.remove_rounded,
          Colors.white,
        ),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: 22, color: iconColor),
    );
  }
}

class _SatisfiedChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'MET',
        style: PrismTypography.publicSans(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: Colors.white,
        ),
      ),
    );
  }
}

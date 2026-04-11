import 'package:flutter/material.dart';
import '../../../core/models/track_a_result.dart';
import '../../../core/models/track_b_result.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/prism_tokens.dart';
import '../../../core/utils/eval_mode.dart';

/// Stitch-style stat row: compliance (from model output) + last analysis time.
class PacketStatusStatCards extends StatelessWidget {
  final TrackBResult result;
  final DateTime? completedAt;

  const PacketStatusStatCards({
    super.key,
    required this.result,
    required this.completedAt,
  });

  static String _formatCompletedAt(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = d.hour;
    final minute = d.minute.toString().padLeft(2, '0');
    final isPm = hour >= 12;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h12:$minute ${isPm ? 'PM' : 'AM'} · ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static (String headline, String detail) _complianceCopy(TrackBResult r) {
    final total = r.requirements.length;
    final sat = r.satisfiedCount;
    final detail = total == 0
        ? 'No requirements yet'
        : '$sat of $total requirements satisfied';

    if (!kEvalMode) {
      return ('Checklist', detail);
    }

    final headline = switch (r.overallConfidence) {
      ConfidenceLevel.high => 'Strong alignment',
      ConfidenceLevel.medium => 'Mostly aligned',
      ConfidenceLevel.low => 'Needs verification',
      ConfidenceLevel.uncertain => 'Needs review',
    };
    return (headline, detail);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final (complianceHeadline, complianceDetail) = _complianceCopy(result);
    final updatedLine = completedAt != null
        ? _formatCompletedAt(completedAt!)
        : '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Compliance',
              headline: complianceHeadline,
              detail: complianceDetail,
              theme: theme,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Last updated',
              headline: updatedLine,
              detail: 'On-device analysis',
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String headline;
  final String detail;
  final TextTheme theme;

  const _StatCard({
    required this.label,
    required this.headline,
    required this.detail,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: prismCardDecoration(context, strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.neutral,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            style: theme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: theme.bodySmall?.copyWith(
              color: AppColors.neutral,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

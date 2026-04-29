import 'package:flutter/material.dart';

import '../../../core/models/track_a_result.dart';
import '../../../core/utils/eval_mode.dart';
import '../../../core/utils/label_formatter.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/prism_typography.dart';
import '../../track_b/widgets/confidence_badge.dart';

const Color _kTrackADeadlineBg = Color(0xFFFFF3F3);
const Color _kTrackADeadlineBorder = Color(0xFFB71C1C);
const Color _kTrackADeadlineText = Color(0xFFB71C1C);
const Color _kTrackAMissingBg = Color(0xFFFFF3F3);
const Color _kTrackAMissingBorder = Color(0xFFB71C1C);

/// Track A results body: deadline first, proof pack, prominent action summary.
class TrackAResultsView extends StatelessWidget {
  final TrackAResult result;
  final VoidCallback onStartOver;
  final VoidCallback onSaveSummary;

  const TrackAResultsView({
    super.key,
    required this.result,
    required this.onStartOver,
    required this.onSaveSummary,
  });

  @override
  Widget build(BuildContext context) {
    final ns = result.noticeSummary;
    final showDeadline =
        ns.deadline.isNotEmpty && !ns.isUncertain;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              if (showDeadline)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _kTrackADeadlineBg,
                    border: Border.all(
                      color: _kTrackADeadlineBorder,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Respond by ${ns.deadline}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _kTrackADeadlineText,
                        ),
                      ),
                      if (ns.requestedCategories.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'The notice asks you to send proof for:',
                          style: PrismTypography.publicSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...ns.requestedCategories.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF555555),
                                    height: 1.35,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    LabelFormatter.requirementLabel(c),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF555555),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          LabelFormatter.noticeConsequenceExpanded(
                            ns.consequence,
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF444444),
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (ns.isUncertain)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.lightRed,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Notice unclear — please contact DTA at (617) 348-8400',
                          style: PrismTypography.publicSans(
                            fontSize: 14,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                'Your Proof Pack',
                style: PrismTypography.spaceGrotesk(fontSize: 20),
              ),
              const SizedBox(height: 16),
              ...result.proofPackDeduplicatedByCategory
                  .map((item) => _ProofPackItemTile(item)),
              const SizedBox(height: 24),
              _ActionSummaryCard(
                summary: result.actionSummary.trim().isNotEmpty
                    ? result.actionSummary
                    : LabelFormatter.synthesizeTrackAActionSummary(result),
              ),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onStartOver,
                  child: const Text('Start Over'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: onSaveSummary,
                  child: const Text('Save Summary'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionSummaryCard extends StatelessWidget {
  final String summary;

  const _ActionSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What to do next',
            style: PrismTypography.spaceGrotesk(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: PrismTypography.publicSans(
              fontSize: 18,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofPackItemTile extends StatelessWidget {
  final ProofPackItem item;

  const _ProofPackItemTile(this.item);

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusBg, statusText) = _assessmentStyles(item.assessment);
    final missing = item.isMissing;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: missing ? _kTrackAMissingBg : AppColors.surfaceContainerLowest,
        border: Border.all(
          color: missing
              ? _kTrackAMissingBorder
              : const Color(0xFFC3C6CF).withValues(alpha: 0.2),
          width: missing ? 2 : 1,
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
                  LabelFormatter.requirementLabel(item.category),
                  style: PrismTypography.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: PrismTypography.publicSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            LabelFormatter.assessmentForTrackA(item.assessment),
            style: PrismTypography.publicSans(
              fontSize: 13,
              color: AppColors.neutral,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          if (!missing)
            Text(
              'Matched in your upload: ${item.matchedDocument}',
              style: PrismTypography.publicSans(
                fontSize: 14,
                color: AppColors.neutral,
              ),
            )
          else
            Text(
              'Add or retake a photo if you have another document for this category.',
              style: PrismTypography.publicSans(
                fontSize: 14,
                color: AppColors.error,
              ),
            ),
          if (item.evidence.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'What we noticed in the text',
              style: PrismTypography.publicSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.evidence,
              style: PrismTypography.publicSans(
                fontSize: 13,
                color: AppColors.neutral,
                height: 1.4,
              ),
            ),
          ],
          if (item.caveats.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.lightAmber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.caveats,
                style: PrismTypography.publicSans(
                  fontSize: 12,
                  color: const Color(0xFF92400E),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          ConfidenceBadge(level: item.confidence),
          if (kEvalMode) ...[
            const SizedBox(height: 6),
            Text(
              'eval: ${item.assessment.name}',
              style: PrismTypography.publicSans(
                fontSize: 10,
                color: AppColors.neutral,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

(Color, Color, String) _assessmentStyles(AssessmentLabel assessment) {
  final chip = LabelFormatter.assessmentChipTrackA(assessment);
  switch (assessment) {
    case AssessmentLabel.likelySatisfies:
      return (AppColors.success, AppColors.lightGreen, chip);
    case AssessmentLabel.likelyDoesNotSatisfy:
      return (
        const Color(0xFF92400E),
        AppColors.lightAmber,
        chip,
      );
    case AssessmentLabel.missing:
      return (AppColors.error, AppColors.lightRed, chip);
    case AssessmentLabel.uncertain:
      return (AppColors.neutral, AppColors.surfaceContainerLow, chip);
  }
}

/// Scaffold + app bar for widget tests and previews.
class TrackAResultsScreen extends StatelessWidget {
  final TrackAResult result;
  final VoidCallback onStartOver;
  final VoidCallback onSaveSummary;

  TrackAResultsScreen({
    super.key,
    required this.result,
    VoidCallback? onStartOver,
    VoidCallback? onSaveSummary,
  })  : onStartOver = onStartOver ?? (() {}),
        onSaveSummary = onSaveSummary ?? (() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('SNAP Document Check'),
      ),
      body: TrackAResultsView(
        result: result,
        onStartOver: onStartOver,
        onSaveSummary: onSaveSummary,
      ),
    );
  }
}

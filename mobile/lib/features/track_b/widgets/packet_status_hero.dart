import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../../../core/models/track_b_result.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/prism_tokens.dart';

/// Prism results hero — Stitch “BPS Registration Center” / packet status header.
class PacketStatusHero extends StatelessWidget {
  final TrackBResult result;

  const PacketStatusHero({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final total = result.requirements.length;
    final ok = result.satisfiedCount;
    final allSatisfied = total > 0 && ok == total;
    final needsReview = total > 0 && !allSatisfied;

    final pill = switch ((total, allSatisfied)) {
      (_, true) => 'APPLICATION VERIFIED',
      (0, _) => 'PACKET STATUS',
      _ => 'REVIEW NEEDED',
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        gradient: prismHeroGradient,
        borderRadius: BorderRadius.circular(PrismRadii.lg),
        boxShadow: PrismShadows.elevated(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PrismRadii.lg),
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              right: -20,
              top: -20,
              child: CircleAvatar(
                radius: 56,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: needsReview
                          ? AppColors.warning
                          : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: needsReview
                            ? const Color(0xFFB45309)
                            : Colors.white.withValues(alpha: 0.35),
                        width: needsReview ? 2 : 1,
                      ),
                      boxShadow: needsReview
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (needsReview) ...[
                          const Icon(
                            Icons.priority_high_rounded,
                            size: 15,
                            color: Color(0xFF422006),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          pill,
                          style: tt.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: needsReview
                                ? const Color(0xFF422006)
                                : Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'BPS Registration Center',
                    style: tt.titleLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    total == 0
                        ? 'On-device review — add documents to see your checklist.'
                        : 'Registration packet — $ok of $total requirements satisfied on this device.',
                    style: tt.bodyMedium?.copyWith(
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/prism_tokens.dart';

const Color _landingAccentAmber = Color(0xFFC49B5F);

/// Stitch-style “lens” hero visual (glass layers + core, no external images).
class PrismLandingLens extends StatelessWidget {
  const PrismLandingLens({super.key});

  @override
  Widget build(BuildContext context) {
    const size = 260.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              color: AppColors.primary.withValues(alpha: 0.03),
            ),
          ),
          Transform.rotate(
            angle: 12 * math.pi / 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: size * 0.78,
                  height: size * 0.78,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: -6 * math.pi / 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: size * 0.68,
                  height: size * 0.68,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(36),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: size * 0.46,
            height: size * 0.46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryContainer,
                  AppColors.primary,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Center(
              child: Container(
                width: size * 0.26,
                height: size * 0.26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _landingAccentAmber.withValues(alpha: 0.35),
                  boxShadow: [
                    BoxShadow(
                      color: _landingAccentAmber.withValues(alpha: 0.28),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.lens,
                  size: 42,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 8,
            child: _FloatingChip(
              icon: Icons.verified_outlined,
              iconColor: _landingAccentAmber,
              label: 'Checklist ready',
            ),
          ),
          Positioned(
            bottom: 18,
            left: 0,
            child: _BenefitChip(),
          ),
        ],
      ),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _FloatingChip({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.ghostBorder.withValues(alpha: 0.5)),
        boxShadow: PrismShadows.elevated(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.02,
                  color: AppColors.primary,
                  fontSize: 10,
                ),
          ),
        ],
      ),
    );
  }
}

class _BenefitChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ghostBorder.withValues(alpha: 0.5)),
        boxShadow: PrismShadows.elevated(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'REQUIREMENTS MET',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  letterSpacing: 0.14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.neutral,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: 0.75,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceContainer,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      _landingAccentAmber,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '4/4',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

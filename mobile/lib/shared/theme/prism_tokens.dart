import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Prism design system — radii, shadows, gradients (`docs/design/prism_migration_spec.md`).
abstract final class PrismRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
}

abstract final class PrismShadows {
  /// Elevated card (spec: primary @ 8%, blur 8, offset (0,2))
  static List<BoxShadow> card(BuildContext context) => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// Track / larger cards (spec: 6%, blur 12, offset (0,4))
  static List<BoxShadow> elevated(BuildContext context) => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> cardPressed(BuildContext context) => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
}

BoxDecoration prismCardDecoration(
  BuildContext context, {
  Color? color,
  double radius = PrismRadii.md,
  bool strong = false,
}) {
  return BoxDecoration(
    color: color ?? AppColors.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: strong
        ? PrismShadows.elevated(context)
        : PrismShadows.card(context),
  );
}

BoxDecoration prismTrackCardDecoration(
  BuildContext context, {
  bool pressed = false,
}) {
  return BoxDecoration(
    color: AppColors.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(PrismRadii.lg),
    boxShadow: pressed
        ? PrismShadows.cardPressed(context)
        : PrismShadows.elevated(context),
  );
}

const LinearGradient prismHeroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    AppColors.primary,
    AppColors.primaryContainer,
  ],
);

/// Crystal / asymmetric radii for badges and slot indicators (migration spec).
BorderRadius crystalBorderRadius() {
  return const BorderRadius.only(
    topLeft: Radius.circular(4),
    topRight: Radius.circular(12),
    bottomLeft: Radius.circular(12),
    bottomRight: Radius.circular(4),
  );
}

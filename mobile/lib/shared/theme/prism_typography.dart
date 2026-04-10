import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

/// Explicit Prism font styles where [ThemeData.textTheme] is not applied
/// (e.g. raw [TextStyle], const widgets). Stitch: Space Grotesk + Public Sans.
abstract final class PrismTypography {
  static TextStyle spaceGrotesk({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? height,
    double letterSpacing = -0.02,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.primary,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle publicSans({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.publicSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.primary,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}

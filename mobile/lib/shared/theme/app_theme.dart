import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFF002444);
  static const Color primaryContainer = Color(0xFF1A3A5C);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Surface Colors
  static const Color surface = Color(0xFFF7F9FB);
  static const Color surfaceContainerLow = Color(0xFFF2F4F6);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainer = Color(0xFFECEEF0);

  // Semantic Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color neutral = Color(0xFF64748B);

  // Background Variations for Status
  static const Color lightGreen = Color(0xFFF0FDF4);
  static const Color lightAmber = Color(0xFFFFFBEB);
  static const Color lightRed = Color(0xFFFFF3F3);
  static const Color lightBlue = Color(0xFFEFF6FF);

  // Outline
  static const Color outline = Color(0xFF73777F);
  static const Color ghostBorder = Color(0xFFC3C6CF);

  /// Disabled primary button (design spec)
  static const Color disabledFill = Color(0xFFE0E3E5);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        surface: AppColors.surface,
        surfaceContainerLowest: AppColors.surfaceContainerLowest,
        surfaceContainerLow: AppColors.surfaceContainerLow,
        surfaceContainer: AppColors.surfaceContainer,
        outline: AppColors.outline,
        error: AppColors.error,
      ),
      // Civic Prism (Stitch): Space Grotesk — display/headlines; Public Sans — body/labels
      textTheme: GoogleFonts.publicSansTextTheme().copyWith(
        headlineLarge: GoogleFonts.spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02,
          color: AppColors.primary,
        ),
        headlineMedium: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.4,
          letterSpacing: -0.02,
          color: AppColors.primary,
        ),
        titleLarge: GoogleFonts.spaceGrotesk(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.02,
          color: AppColors.primary,
        ),
        titleMedium: GoogleFonts.spaceGrotesk(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.02,
          color: AppColors.primary,
        ),
        bodyLarge: GoogleFonts.publicSans(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: AppColors.primary,
        ),
        bodyMedium: GoogleFonts.publicSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: AppColors.primary,
        ),
        labelSmall: GoogleFonts.publicSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: AppColors.neutral,
        ),
        titleSmall: GoogleFonts.spaceGrotesk(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.02,
          color: AppColors.primary,
          height: 1.25,
        ),
        bodySmall: GoogleFonts.publicSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1.35,
          color: AppColors.neutral,
        ),
        labelLarge: GoogleFonts.publicSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: AppColors.primary,
        ),
        labelMedium: GoogleFonts.publicSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.3,
          color: AppColors.primary,
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: GoogleFonts.publicSans(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
        subtitleTextStyle: GoogleFonts.publicSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.neutral,
          height: 1.35,
        ),
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.02,
          color: AppColors.primary,
        ),
        contentTextStyle: GoogleFonts.publicSans(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: AppColors.primary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: GoogleFonts.publicSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.disabledFill,
          disabledForegroundColor: AppColors.neutral,
          minimumSize: const Size(double.infinity, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.publicSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: const BorderSide(color: AppColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.publicSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainerLowest,
        elevation: 0,
        shadowColor: AppColors.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.02,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

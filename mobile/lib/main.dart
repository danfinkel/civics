import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'features/onboarding/model_download_screen.dart';
import 'features/track_a/track_a_screen.dart';
import 'features/track_b/track_b_screen.dart';
import 'features/test/inference_test_screen.dart';
import 'features/test/ocr_test_screen.dart';
import 'shared/navigation/prism_page_routes.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/prism_tokens.dart';
import 'shared/widgets/prism/prism_shimmer.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };

    ErrorWidget.builder = (details) {
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                'ERROR:\n${details.exception}\n\n${details.stack}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ),
        ),
      );
    };

    runApp(const CivicLensApp());
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

class CivicLensApp extends StatelessWidget {
  const CivicLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CivicLens',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AppEntryPoint(),
    );
  }
}

/// Entry point that checks for model download before showing main app
class AppEntryPoint extends StatelessWidget {
  const AppEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ModelDownloadScreen.isModelDownloaded(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.surface,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: PrismShimmer(
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: PrismShadows.card(context),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Starting CivicLens…',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final isDownloaded = snapshot.data ?? false;

        if (isDownloaded) {
          return const HomeScreen();
        } else {
          return const ModelDownloadScreen();
        }
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              GestureDetector(
                onLongPress: () => _showTestMenu(context),
                child: Text(
                  'CivicLens',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.02,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Document help for Massachusetts residents',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.neutral,
                ),
              ),
              const SizedBox(height: 48),
              _PrismTrackCard(
                title: 'SNAP Benefits',
                subtitle: 'Check your recertification documents',
                icon: Icons.restaurant_outlined,
                onTap: () => Navigator.push(
                  context,
                  PrismPageRoutes.push<void>(
                    const TrackAScreen(),
                    name: 'TrackA',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _PrismTrackCard(
                title: 'School Enrollment',
                subtitle: 'Prepare your BPS registration packet',
                icon: Icons.school_outlined,
                onTap: () => Navigator.push(
                  context,
                  PrismPageRoutes.push<void>(
                    const TrackBScreen(),
                    name: 'TrackB',
                  ),
                ),
              ),
              const Spacer(),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: AppColors.neutral,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Your documents stay on your device',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.neutral,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

void _showTestMenu(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('Test Inference'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                PrismPageRoutes.push<void>(
                  const InferenceTestScreen(),
                  name: 'InferenceTest',
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.document_scanner),
            title: const Text('Test B1 Pipeline'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                PrismPageRoutes.push<void>(
                  const OcrTestScreen(),
                  name: 'OcrTest',
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// Prism track card — accent bar, icon, tap scale (`prism_migration_spec.md`).
class _PrismTrackCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _PrismTrackCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_PrismTrackCard> createState() => _PrismTrackCardState();
}

class _PrismTrackCardState extends State<_PrismTrackCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: prismTrackCardDecoration(context, pressed: _pressed),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PrismRadii.lg),
            child: Row(
              children: [
                Container(
                  width: 4,
                  color: AppColors.primary,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(
                          widget.icon,
                          size: 28,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: GoogleFonts.inter(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.02,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.subtitle,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.neutral,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

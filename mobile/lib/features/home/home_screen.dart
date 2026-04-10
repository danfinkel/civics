import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../track_a/track_a_screen.dart';
import '../track_b/model_transparency_screen.dart';
import '../track_b/track_b_screen.dart';
import '../test/inference_test_screen.dart';
import '../test/ocr_test_screen.dart';
import '../../shared/navigation/prism_page_routes.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/prism_tokens.dart';
import 'widgets/prism_landing_lens.dart';

const Color _landingAccentAmber = Color(0xFFC49B5F);

/// Stitch-style landing (hero, lens, capabilities, transparency) + service tiles.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _capabilitiesKey = GlobalKey();
  final GlobalKey _transparencyKey = GlobalKey();
  final GlobalKey _servicesKey = GlobalKey();

  void _ensureVisible(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
    }
  }

  void _openTransparency(BuildContext context) {
    Navigator.push<void>(
      context,
      PrismPageRoutes.push<void>(
        const ModelTransparencyScreen(),
        name: 'ModelTransparency',
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          _LandingTopBar(
            wide: wide,
            onCapabilities: () => _ensureVisible(_capabilitiesKey),
            onTransparency: () => _openTransparency(context),
            onTryDemo: () => _ensureVisible(_servicesKey),
            onLongPressBrand: () => _showTestMenu(context),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DotPatternPainter(),
                  ),
                ),
                Positioned.fill(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide)
                          _HeroWide(theme: theme)
                        else ...[
                          _HeroNarrow(theme: theme),
                          const SizedBox(height: 8),
                          const Center(child: PrismLandingLens()),
                        ],
                        const SizedBox(height: 20),
                        _PrimaryCtas(
                          onGetStarted: () => _ensureVisible(_servicesKey),
                          onHowItWorks: () => _openTransparency(context),
                        ),
                        const SizedBox(height: 20),
                        _TrustLine(theme: theme),
                        const SizedBox(height: 28),
                        const _VerticalDividerDecor(),
                        const SizedBox(height: 24),
                        KeyedSubtree(
                          key: _capabilitiesKey,
                          child: const _CapabilityGrid(),
                        ),
                        const SizedBox(height: 28),
                        KeyedSubtree(
                          key: _transparencyKey,
                          child: _TransparencyCard(
                            onLearnMore: () => _openTransparency(context),
                          ),
                        ),
                        const SizedBox(height: 32),
                        KeyedSubtree(
                          key: _servicesKey,
                          child: _ServicesHeader(theme: theme),
                        ),
                        const SizedBox(height: 14),
                        _StitchTrackCard(
                          title: 'SNAP Benefits',
                          subtitle:
                              'Check recertification documents before you submit',
                          icon: Icons.restaurant_rounded,
                          onTap: () => Navigator.push(
                            context,
                            PrismPageRoutes.push<void>(
                              const TrackAScreen(),
                              name: 'TrackA',
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _StitchTrackCard(
                          title: 'School Enrollment',
                          subtitle:
                              'Build your BPS registration packet on this device',
                          icon: Icons.school_rounded,
                          onTap: () => Navigator.push(
                            context,
                            PrismPageRoutes.push<void>(
                              const TrackBScreen(),
                              name: 'TrackB',
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _FooterNote(theme: theme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingTopBar extends StatelessWidget {
  final bool wide;
  final VoidCallback onCapabilities;
  final VoidCallback onTransparency;
  final VoidCallback onTryDemo;
  final VoidCallback onLongPressBrand;

  const _LandingTopBar({
    required this.wide,
    required this.onCapabilities,
    required this.onTransparency,
    required this.onTryDemo,
    required this.onLongPressBrand,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.94),
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onLongPress: onLongPressBrand,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_balance_rounded,
                          color: AppColors.primaryContainer,
                          size: 24,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'CivicLens',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.02,
                            color: AppColors.primaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (wide) ...[
                  TextButton(
                    onPressed: onCapabilities,
                    child: Text(
                      'Capabilities',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.neutral,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onTransparency,
                    child: Text(
                      'Transparency',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.neutral,
                      ),
                    ),
                  ),
                ] else
                  IconButton(
                    tooltip: 'Menu',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: AppColors.primary.withValues(alpha: 0.7),
                    ),
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (ctx) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.grid_view_rounded),
                                title: const Text('Capabilities'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onCapabilities();
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.info_outline_rounded),
                                title: const Text('Transparency'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onTransparency();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                FilledButton(
                  onPressed: onTryDemo,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Try demo',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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

class _HeroNarrow extends StatelessWidget {
  final TextTheme theme;

  const _HeroNarrow({required this.theme});

  @override
  Widget build(BuildContext context) {
    return _HeroCopy(theme: theme, crossAlign: CrossAxisAlignment.center);
  }
}

class _HeroWide extends StatelessWidget {
  final TextTheme theme;

  const _HeroWide({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: _HeroCopy(theme: theme, crossAlign: CrossAxisAlignment.start),
        ),
        const Expanded(
          flex: 5,
          child: Align(
            alignment: Alignment.topCenter,
            child: PrismLandingLens(),
          ),
        ),
      ],
    );
  }
}

class _HeroCopy extends StatelessWidget {
  final TextTheme theme;
  final CrossAxisAlignment crossAlign;

  const _HeroCopy({
    required this.theme,
    required this.crossAlign,
  });

  @override
  Widget build(BuildContext context) {
    final textAlign =
        crossAlign == CrossAxisAlignment.center ? TextAlign.center : TextAlign.start;
    final w = MediaQuery.sizeOf(context).width;
    final headlineSize = w < 380 ? 26.0 : (w < 520 ? 30.0 : 36.0);
    final headlineStyle = GoogleFonts.spaceGrotesk(
      fontSize: headlineSize,
      fontWeight: FontWeight.w700,
      height: 1.08,
      letterSpacing: -0.02 * headlineSize,
      color: AppColors.primary,
    );
    return Column(
      crossAxisAlignment: crossAlign,
      children: [
        Text(
          'TRANSPARENT CONFIDENCE',
          textAlign: textAlign,
          style: GoogleFonts.publicSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: AppColors.primaryContainer,
          ),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: headlineStyle,
            children: [
              const TextSpan(text: 'Prepare Massachusetts civic documents with '),
              TextSpan(
                text: 'clarity.',
                style: headlineStyle.copyWith(color: _landingAccentAmber),
              ),
            ],
          ),
          textAlign: textAlign,
        ),
        const SizedBox(height: 14),
        Text(
          'CivicLens helps with DTA SNAP notices and Boston Public Schools '
          'registration. Upload photos, get a plain-language checklist, and see '
          'confidence cues—not a decision from DTA or BPS.',
          textAlign: textAlign,
          style: theme.bodyLarge?.copyWith(
            color: AppColors.neutral,
            height: 1.5,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _PrimaryCtas extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onHowItWorks;

  const _PrimaryCtas({
    required this.onGetStarted,
    required this.onHowItWorks,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final row = c.maxWidth >= 400;
        final primary = FilledButton.icon(
          onPressed: onGetStarted,
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          label: Text(
            'Get started',
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
        final secondary = OutlinedButton(
          onPressed: onHowItWorks,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            side: BorderSide(color: AppColors.outline.withValues(alpha: 0.5)),
          ),
          child: Text(
            'How this works',
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        );
        if (row) {
          return Row(
            children: [
              Expanded(child: primary),
              const SizedBox(width: 12),
              Expanded(child: secondary),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            primary,
            const SizedBox(height: 12),
            secondary,
          ],
        );
      },
    );
  }
}

class _TrustLine extends StatelessWidget {
  final TextTheme theme;

  const _TrustLine({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: theme.bodySmall?.copyWith(
          color: AppColors.neutral,
          height: 1.45,
          fontSize: 13,
        ),
        children: [
          TextSpan(
            text: 'On-device review: ',
            style: theme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.neutral,
              height: 1.45,
              fontSize: 13,
            ),
          ),
          TextSpan(
            text:
                'documents stay on this phone when you use local inference. Always confirm requirements with DTA or BPS staff.',
            style: theme.bodySmall?.copyWith(
              color: AppColors.neutral,
              height: 1.45,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDividerDecor extends StatelessWidget {
  const _VerticalDividerDecor();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 1,
        height: 72,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withValues(alpha: 0.22),
              AppColors.primary.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapabilityGrid extends StatelessWidget {
  const _CapabilityGrid();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cards = [
      _LandingFeatureCard(
        icon: Icons.document_scanner_rounded,
        title: 'Uploads & OCR',
        body:
            'PDFs and images. Text is extracted so the model can match your uploads to the checklist.',
      ),
      _LandingFeatureCard(
        icon: Icons.assignment_rounded,
        title: 'SNAP & enrollment',
        body:
            'Track A: DTA notices and proof categories. Track B: BPS packet (age, two residency types, immunizations, optional grade).',
      ),
      _LandingFeatureCard(
        icon: Icons.shield_outlined,
        title: 'Privacy-aware',
        body:
            'Designed for on-device analysis. You control what you photograph and clear slots anytime.',
      ),
    ];
    if (w >= 720) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          cards[i],
        ],
      ],
    );
  }
}

class _LandingFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _LandingFeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: PrismShadows.card(context),
            ),
            child: Icon(icon, size: 26, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.publicSans(
              fontSize: 14,
              height: 1.5,
              color: AppColors.neutral,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransparencyCard extends StatelessWidget {
  final VoidCallback onLearnMore;

  const _TransparencyCard({
    required this.onLearnMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(PrismRadii.lg),
        border: const Border(
          left: BorderSide(color: AppColors.primaryContainer, width: 4),
        ),
        boxShadow: PrismShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transparency',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          _bullet('Confidence colors describe model certainty—not a legal outcome.'),
          _bullet('Blur warnings help you retake photos when text is hard to read.'),
          _bullet('Official decisions still come from agencies; CivicLens is a prep aid.'),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onLearnMore,
            child: Text(
              'Full details',
              style: GoogleFonts.publicSans(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: GoogleFonts.publicSans(
              fontSize: 14,
              height: 1.5,
              color: AppColors.neutral,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.publicSans(
                fontSize: 14,
                height: 1.5,
                color: AppColors.neutral,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicesHeader extends StatelessWidget {
  final TextTheme theme;

  const _ServicesHeader({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHOOSE A SERVICE',
          style: GoogleFonts.publicSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: AppColors.primary.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Start a review',
          style: theme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.03 * 16,
            color: AppColors.primary,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _FooterNote extends StatelessWidget {
  final TextTheme theme;

  const _FooterNote({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      '© ${DateTime.now().year} CivicLens · Massachusetts',
      textAlign: TextAlign.center,
      style: theme.bodySmall?.copyWith(
        color: AppColors.neutral.withValues(alpha: 0.75),
        fontSize: 12,
      ),
    );
  }
}

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 24.0;
    final paint = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    for (var y = 0.0; y < size.height; y += spacing) {
      for (var x = 0.0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 0.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _showTestMenu(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
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

class _StitchTrackCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _StitchTrackCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_StitchTrackCard> createState() => _StitchTrackCardState();
}

class _StitchTrackCardState extends State<_StitchTrackCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: _pressed ? 0.14 : 0.09),
            ),
            boxShadow: _pressed
                ? PrismShadows.cardPressed(context)
                : [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 28,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.02,
                          color: AppColors.primary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle,
                        style: GoogleFonts.publicSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.35,
                          color: AppColors.neutral,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 22,
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

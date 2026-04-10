import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';

/// Stitch loading layout (`docs/design/stitch_loading_page.html`): navy field, grid,
/// glass prism + amber “guiding light”, shimmer bar, bottom wordmark.
class CivicLensSplashScreen extends StatefulWidget {
  const CivicLensSplashScreen({super.key});

  @override
  State<CivicLensSplashScreen> createState() => _CivicLensSplashScreenState();
}

class _CivicLensSplashScreenState extends State<CivicLensSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  static const Color _onPrimaryContainer = Color(0xFF87A4CC);
  static const Color _amberLight = Color(0xFFECBF80);
  static const Color _amberDeep = Color(0xFFC49B5F);
  static const Color _surfaceTintRadial = Color(0x26436084); // ~15% #436084

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Base vertical gradient (primary → container tint → primary)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary,
                  Color(0xCC1A3A5C), // primary-container ~80% for mid band
                  AppColors.primary,
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
          // Geometric dot grid (Stitch: 40px, soft blue dots)
          const CustomPaint(
            painter: _SplashGeometricGridPainter(),
          ),
          // Top radial accent
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.85),
                  radius: 1.15,
                  colors: [
                    _surfaceTintRadial,
                    _surfaceTintRadial.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          // Center: lens construct + progress
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SplashLensConstruct(),
                  const SizedBox(height: 48),
                  _ShimmerProgressBar(
                    animation: _shimmer,
                    amberLight: _amberLight,
                    amberDeep: _amberDeep,
                  ),
                ],
              ),
            ),
          ),
          // Bottom branding
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.account_balance_rounded,
                      color: _amberLight,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'CivicLens',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'YOUR DIGITAL ARCHITECT FOR CIVIC LIFE',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.publicSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.2,
                    color: _onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SplashNoisePainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashGeometricGridPainter extends CustomPainter {
  const _SplashGeometricGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 40.0;
    // Stitch: rgba(163,201,242,0.05) dots on grid; combined opacity ~0.3 in comp
    final dot = Paint()
      ..color = const Color(0xFFA3C9F2).withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;
    for (var y = 0.0; y < size.height; y += spacing) {
      for (var x = 0.0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x + 1, y + 1), 1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SplashNoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.025);
    final rnd = math.Random(42);
    for (var i = 0; i < 280; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SplashLensConstruct extends StatelessWidget {
  const _SplashLensConstruct();

  @override
  Widget build(BuildContext context) {
    const outer = 260.0;
    const core = 200.0;
    const amberSize = 72.0;

    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform.rotate(
            angle: 12 * math.pi / 180,
            child: Transform.scale(
              scale: 0.95,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(48),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    width: outer,
                    height: outer,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(48),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: -6 * math.pi / 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(48),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: outer * 0.92,
                  height: outer * 0.92,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(48),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: core,
            height: core,
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
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.12),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.2),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  right: 14,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFABC9F2).withValues(alpha: 0.08),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFABC9F2).withValues(alpha: 0.15),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: amberSize,
                  height: amberSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [
                        Color(0xFFECBF80),
                        Color(0xFFC49B5F),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFECBF80).withValues(alpha: 0.35),
                        blurRadius: 48,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.light_mode_rounded,
                    size: 36,
                    color: AppColors.primary,
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

class _ShimmerProgressBar extends StatelessWidget {
  final Animation<double> animation;
  final Color amberLight;
  final Color amberDeep;

  const _ShimmerProgressBar({
    required this.animation,
    required this.amberLight,
    required this.amberDeep,
  });

  @override
  Widget build(BuildContext context) {
    const width = 192.0;
    const height = 4.0;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: Colors.white.withValues(alpha: 0.05),
            ),
            AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final t = animation.value;
                return CustomPaint(
                  painter: _ShimmerBarPainter(
                    t: t,
                    amberLight: amberLight,
                    amberDeep: amberDeep,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBarPainter extends CustomPainter {
  final double t;
  final Color amberLight;
  final Color amberDeep;

  _ShimmerBarPainter({
    required this.t,
    required this.amberLight,
    required this.amberDeep,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final band = w * 0.45;
    final x = -band + (w + band * 2) * t;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, 0, band, size.height),
      Radius.circular(size.height / 2),
    );
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          amberLight.withValues(alpha: 0.25),
          amberDeep,
          amberLight.withValues(alpha: 0.25),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(x, 0, band, size.height));
    canvas.drawRRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerBarPainter oldDelegate) =>
      oldDelegate.t != t;
}

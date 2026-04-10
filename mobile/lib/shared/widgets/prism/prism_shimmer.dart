import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Prism loading shimmer — 1.5s linear loop (`prism_migration_spec.md` Phase 2).
///
/// Disabled when [TickerMode] is off (e.g. reduced-motion / test).
class PrismShimmer extends StatefulWidget {
  final Widget child;

  const PrismShimmer({super.key, required this.child});

  @override
  State<PrismShimmer> createState() => _PrismShimmerState();
}

class _PrismShimmerState extends State<PrismShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!TickerMode.valuesOf(context).enabled) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.2 + 2.6 * t, -0.35),
              end: Alignment(0.2 + 2.6 * t, 0.45),
              colors: [
                Colors.transparent,
                AppColors.primary.withValues(alpha: 0.12),
                Colors.transparent,
              ],
              stops: const [0.38, 0.5, 0.62],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

import 'package:flutter/material.dart';

/// Slide + fade transitions for Prism Phase 2 (`prism_migration_spec.md`).
abstract final class PrismPageRoutes {
  static const Duration _pushDuration = Duration(milliseconds: 300);
  static const Duration _fadeDuration = Duration(milliseconds: 280);

  /// Forward push: slight horizontal slide + fade (easeInOut).
  static Route<T> push<T extends Object?>(Widget page, {String? name}) {
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name ?? page.runtimeType.toString()),
      transitionDuration: _pushDuration,
      reverseTransitionDuration: _pushDuration,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
          reverseCurve: Curves.easeInOut,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Replacement (e.g. onboarding → main): fade only.
  static Route<T> fadeReplace<T extends Object?>(Widget page, {String? name}) {
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name ?? page.runtimeType.toString()),
      transitionDuration: _fadeDuration,
      reverseTransitionDuration: _fadeDuration,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
          child: child,
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Animation system for PhotoSpot — purposeful motion that explains state,
/// relationship, and hierarchy.
class AppMotion {
  AppMotion._();

  static const Duration instant = Duration(milliseconds: 120);
  static const Duration quick = Duration(milliseconds: 220);
  static const Duration layout = Duration(milliseconds: 340);

  static const Curve easeOut = Curves.easeOutCubic;

  /// Page route: slide up slightly with a fade. Used for every pushed screen.
  static PageRouteBuilder<T> slideUp<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: easeOut,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: layout,
      reverseTransitionDuration: quick,
    );
  }

  /// Bottom-sheet style route for task flows (submit).
  static PageRouteBuilder<T> slideUpModal<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutQuart)).animate(animation),
          child: child,
        );
      },
      transitionDuration: layout,
      reverseTransitionDuration: quick,
    );
  }

  /// Stagger delay for list items, capped so long lists never feel slow.
  static Duration staggerDelay(int index) {
    return Duration(milliseconds: (index * 45).clamp(0, 240));
  }
}

/// Reveals a widget with a staggered slide-up + fade on first build.
class RevealItem extends StatefulWidget {
  const RevealItem({
    super.key,
    required this.index,
    required this.total,
    required this.child,
  });

  final int index;
  final int total;
  final Widget child;

  @override
  State<RevealItem> createState() => _RevealItemState();
}

class _RevealItemState extends State<RevealItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slide;
  late final Animation<double> _fade;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.layout,
    );
    _slide = Tween<double>(begin: 0.06, end: 0.0)
        .chain(CurveTween(curve: AppMotion.easeOut))
        .animate(_controller);
    _fade = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: AppMotion.easeOut))
        .animate(_controller);

    _delayTimer = Timer(AppMotion.staggerDelay(widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slide.value * 24),
          child: Opacity(opacity: _fade.value, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// A tappable surface with scale feedback, haptics, and semantics.
class PressButton extends StatefulWidget {
  const PressButton({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onTap;
  final String? semanticLabel;
  final bool enabled;

  @override
  State<PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<PressButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.instant,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .chain(CurveTween(curve: AppMotion.easeOut))
        .animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.enabled) _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: () => _controller.reverse(),
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: widget.child,
        ),
      ),
    );
  }
}

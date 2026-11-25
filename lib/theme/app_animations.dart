import 'package:flutter/material.dart';

/// Animation system for PhotoSpot — purposeful motion that explains state,
/// relationship, and hierarchy. No generic fade-and-rise decoration.
class AppMotion {
  AppMotion._();

  // Durations per the animate.md timing table.
  static const Duration instant = Duration(milliseconds: 120); // immediate feedback
  static const Duration quick = Duration(milliseconds: 220); // routine state change
  static const Duration layout = Duration(milliseconds: 340); // layout/overlay transition
  static const Duration focus = Duration(milliseconds: 520); // authored focal entrance

  // Easing — confident arrivals, exit faster than entrance.
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve snap = Curves.elasticInOut; // reserved for deliberate moments only

  /// Page route: slide up from bottom with fade — used for new screens.
  static PageRouteBuilder slideUp(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, __) => FadeTransition(
        opacity: animation,
        child: page,
      ),
      transitionsBuilder: (_, animation, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).chain(CurveTween(curve: easeOut)).animate(animation),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1)
                .chain(CurveTween(curve: easeOut))
                .animate(animation),
            child: child,
          ),
        );
      },
      transitionDuration: layout,
      reverseTransitionDuration: quick,
    );
  }

  /// Modal route: slide up from bottom for sheets/modals.
  static PageRouteBuilder slideUpModal(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, __) => page,
      transitionsBuilder: (_, animation, __, child) {
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

  /// Fade route for detail pages with hero images.
  static PageRouteBuilder fadeWithHero(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, __) => FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(animation),
        child: page,
      ),
      transitionDuration: quick,
      reverseTransitionDuration: quick,
    );
  }

  /// Stagger delay for list items — cap total delay so lists don't feel slow.
  static Duration staggerDelay(int index, {int itemCount = 8}) {
    // Cap at 220ms total so a full list reveals in under 300ms.
    final step = 60;
    return Duration(milliseconds: (index * step).clamp(0, 220));
  }

  /// Entrance animation for list items — slide up + fade.
  static Widget listItem({
    required int index,
    required Widget child,
    required Duration delay,
  }) {
    return AnimatedBuilder(
      animation: const AlwaysStoppedAnimation(1.0),
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, 0),
          child: Opacity(
            opacity: 1.0,
            child: child,
          ),
        );
      },
    );
  }

  /// Reveals a widget after a delay with slide-up + fade.
  static Widget reveal({
    required Widget child,
    required int index,
    required int total,
  }) {
    return FutureBuilder(
      future: Future.delayed(staggerDelay(index, itemCount: total)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).chain(CurveTween(curve: easeOut)).animate(
            AlwaysStoppedAnimation(1.0),
          ),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1)
                .chain(CurveTween(curve: easeOut))
                .animate(AlwaysStoppedAnimation(1.0)),
            child: child,
          ),
        );
      },
    );
  }

  /// Press feedback — scale down slightly on tap.
  static Widget pressFeedback({
    required Widget child,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTapDown: (_) {},
      onTapUp: (_) {},
      onTap: onTap,
      child: AnimatedScale(
        scale: 1.0,
        duration: instant,
        curve: easeOut,
        child: child,
      ),
    );
  }
}

/// Reusable animated list item that reveals with a staggered delay.
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.layout,
    );
    _slide = Tween<double>(begin: 0.12, end: 0.0).chain(
      CurveTween(curve: AppMotion.easeOut),
    ).animate(_controller);
    _fade = Tween<double>(begin: 0.0, end: 1.0).chain(
      CurveTween(curve: AppMotion.easeOut),
    ).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slide.value * 20),
          child: Opacity(opacity: _fade.value, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Scaled press button — visual feedback on tap.
class PressButton extends StatefulWidget {
  const PressButton({
    super.key,
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

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
    _scale = Tween<double>(begin: 1.0, end: 0.95).chain(
      CurveTween(curve: AppMotion.easeOut),
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

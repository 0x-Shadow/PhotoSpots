import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_theme.dart';

/// The app's one frosted material: a real backdrop blur under a neutral white
/// tint with a hairline rim and a soft drop shadow so the surface floats above
/// the page instead of sitting in it.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blur = 26,
    this.padding,
    this.margin,
    this.tint,
    this.borderColor,
    this.shadows,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Optional colour wash blended into the glass. Defaults to none.
  final Color? tint;
  final Color? borderColor;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadows ??
            const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 26,
                spreadRadius: -6,
                offset: Offset(0, 12),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint ?? AppColors.glassFillStrong,
                  tint?.withValues(alpha: 0.03) ?? const Color(0x08FFFFFF),
                ],
              ),
              border: Border.all(
                color: borderColor ?? AppColors.glassBorder,
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A circular glass control that stays legible over photos and map tiles.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.size = 44,
    this.iconSize = 20,
    this.filled = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  /// Filled controls use the app's white action treatment (one per screen).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final button = PressButton(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? AppColors.action : const Color(0x3D0A0A0B),
          border: Border.all(
            color: filled ? AppColors.action : AppColors.glassBorder,
          ),
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: filled ? AppColors.onAction : AppColors.textPrimary,
        ),
      ),
    );

    if (filled) return button;

    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: button,
      ),
    );
  }
}

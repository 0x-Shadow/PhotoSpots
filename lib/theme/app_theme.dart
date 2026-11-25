import 'package:flutter/material.dart';

/// "findr." reference world — near-black ground, raised dark cards,
/// pure white type, hairline borders, white pill actions.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0A0A0B);
  static const surface = Color(0xFF161618);
  static const surfaceElevated = Color(0xFF1D1D20);
  static const hairline = Color(0x1AFFFFFF);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8E8E93);
  static const textFaint = Color(0xFF5B5B60);

  static const action = Color(0xFFFFFFFF);
  static const onAction = Color(0xFF0A0A0B);
  static const accent = Color(0xFFFFA94D);

  static const star = Color(0xFFFFB84D);
  static const trending = Color(0xFFFF6B4A);
  static const like = Color(0xFFFF4D6D);
  static const danger = Color(0xFFFF453A);
  static const accentSoft = Color(0x33FFA94D);

  static const mapBackground = Color(0xFF0A0A0B);

  static const catDate = Color(0xFFFF4D6D);
  static const catFriends = Color(0xFF7C6CFF);
  static const catSunset = Color(0xFFFF9F0A);
  static const catPhoto = Color(0xFF4DA3FF);
  static const catRelax = Color(0xFF34C759);
  static const catNight = Color(0xFFAF7BFF);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: false);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.action,
        onPrimary: AppColors.onAction,
        secondary: AppColors.star,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
      ),
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xF2161618),
        hintStyle: const TextStyle(
            color: AppColors.textFaint, fontSize: 15, fontFamily: 'Inter'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      headlineMedium: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 34,
        height: 1.06,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: AppColors.textPrimary,
      ),
      titleLarge: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: AppColors.textPrimary,
      ),
      titleMedium: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
      ),
      bodyLarge: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 15.5,
        height: 1.6,
        color: AppColors.textSecondary,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: AppColors.textSecondary,
      ),
      labelLarge: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class AppLayout {
  AppLayout._();
  static const radiusCard = 20.0;
  static const pagePad = EdgeInsets.symmetric(horizontal: 20);
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.foreground,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hairline),
          ),
          child: Icon(icon,
              size: size * 0.46, color: foreground ?? AppColors.textPrimary),
        ),
      ),
    );
  }
}

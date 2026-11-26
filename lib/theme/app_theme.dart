import 'package:flutter/material.dart';

import 'app_animations.dart';

/// "findr." reference world — near-black ground, raised dark cards,
/// pure white type, hairline borders, white pill actions.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0A0A0B);
  static const surface = Color(0xFF161618);
  static const surfaceElevated = Color(0xFF1D1D20);
  static const hairline = Color(0x1AFFFFFF);
  static const scrim = Color(0xF2161618);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8E8E93);
  static const textFaint = Color(0xFF5B5B60);

  static const action = Color(0xFFFFFFFF);
  static const onAction = Color(0xFF0A0A0B);
  static const accent = Color(0xFF0A84FF);
  static const accentSoft = Color(0x1F0A84FF);

  static const star = Color(0xFFFFB84D);
  static const trending = Color(0xFFFF6B4A);
  static const like = Color(0xFFFF4D6D);
  static const danger = Color(0xFFFF453A);
  static const success = Color(0xFF34C759);

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
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: AppColors.textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.scrim,
        hintStyle: const TextStyle(
          color: AppColors.textFaint,
          fontSize: 15,
          fontFamily: 'Inter',
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'Inter',
          fontSize: 13.5,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.textPrimary,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.textPrimary,
        selectionColor: Color(0x33FFFFFF),
        selectionHandleColor: AppColors.textPrimary,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: const AppPageTransitionsBuilder(),
          TargetPlatform.iOS: const AppPageTransitionsBuilder(),
          TargetPlatform.macOS: const AppPageTransitionsBuilder(),
          TargetPlatform.windows: const AppPageTransitionsBuilder(),
          TargetPlatform.linux: const AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: const AppPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      displaySmall: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 44,
        height: 1.04,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.8,
        color: AppColors.textPrimary,
      ),
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
      titleSmall: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
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
      bodySmall: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 12.5,
        height: 1.45,
        color: AppColors.textSecondary,
      ),
      labelMedium: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
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
  static const minTapTarget = 48.0;
}

/// The app's one push transition: a small lift and fade, identical on every
/// platform. Replaces FadeUpwards so navigation reads the same on iOS and
/// Android.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> page,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: AppMotion.easeOut),
        ),
        child: child,
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/theme/app_animations.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:photospot/theme/app_typography.dart';

void main() {
  test('accent is cool blue; amber is ratings only', () {
    expect(AppColors.accent, const Color(0xFF328AFF));
    expect(AppColors.accentSoft, const Color(0x29328AFF));
    expect(AppColors.star, const Color(0xFFFFB84D));
  });

  test('every platform uses the shared page transition', () {
    final builders = AppTheme.dark.pageTransitionsTheme.builders;
    for (final platform in TargetPlatform.values) {
      expect(
        builders[platform],
        isA<AppPageTransitionsBuilder>(),
        reason: '${platform.name} should use the shared transition',
      );
    }
  });

  testWidgets('typography roles resolve from the theme', (tester) async {
    late TextStyle headline;
    late TextStyle label;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) {
            headline = AppTypography.headline(context);
            label = AppTypography.label(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(headline.fontSize, 34);
    expect(headline.fontFamily, 'Inter');
    expect(headline.fontWeight, FontWeight.w800);
    expect(label.fontFamily, 'Inter');
  });

  test('stagger is capped without needing an item count', () {
    expect(AppMotion.staggerDelay(0), Duration.zero);
    expect(AppMotion.staggerDelay(4), const Duration(milliseconds: 180));
    expect(AppMotion.staggerDelay(99), const Duration(milliseconds: 240));
  });
}

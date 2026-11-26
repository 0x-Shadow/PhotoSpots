import 'package:flutter/material.dart';

/// Named roles for the type scale. Thin accessors over `ThemeData.textTheme`
/// so screens never hand-write `fontFamily: 'Inter'` or a raw font size.
class AppTypography {
  AppTypography._();

  /// Hero numbers and one-line announcements.
  static TextStyle display(BuildContext context) =>
      Theme.of(context).textTheme.displaySmall!;

  /// Screen titles and large headings.
  static TextStyle headline(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium!;

  /// Section titles and card headings.
  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!;

  /// Primary prose.
  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!;

  /// Metadata, subtitles and captions.
  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!;

  /// Buttons, chips and control labels.
  static TextStyle label(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!;
}

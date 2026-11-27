import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../theme/app_theme.dart';

/// Renders a spot photo from memory (locally submitted) or the network.
class SpotImage extends StatelessWidget {
  const SpotImage({
    super.key,
    required this.photo,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.iconSize = 22,
    this.cacheWidth,
  });

  final SpotPhoto photo;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double iconSize;

  /// Decode width in pixels. Without it a 30px map pin decodes the full
  /// multi-megapixel photo, which is the main cost of a busy map.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final decodeWidth = cacheWidth ??
        (width == null
            ? null
            : (width! * MediaQuery.devicePixelRatioOf(context)).round());
    final placeholder = Image.asset(
      'assets/images/spot_placeholder.jpg',
      fit: fit,
      width: width,
      height: height,
      cacheWidth: decodeWidth,
      errorBuilder: (_, _, _) => Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
        child: Icon(
          Icons.landscape_rounded,
          color: AppColors.textFaint,
          size: iconSize,
        ),
      ),
    );

    final bytes = photo.bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    }

    return Image.network(
      photo.url,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: decodeWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

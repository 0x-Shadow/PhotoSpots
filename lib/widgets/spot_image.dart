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
  });

  final SpotPhoto photo;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: AppColors.surfaceElevated,
      child: Icon(
        Icons.landscape_rounded,
        color: AppColors.textFaint,
        size: iconSize,
      ),
    );

    final bytes = photo.bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, _, _) => placeholder,
      );
    }

    return Image.network(
      photo.url,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

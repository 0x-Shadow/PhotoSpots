import 'package:flutter/material.dart';

import '../services/photo_format.dart';
import '../theme/app_theme.dart';

/// A lightweight spherical 360° photo viewer.
///
/// Shows an equirectangular 360° capture (DJI Mini 4K, Insta360, DJI 360 all
/// write 2:1 equirectangular JPEGs) and lets people look around by dragging
/// horizontally. No heavy 3D dependency — it pans the equirectangular image
/// with wrap-around, so it stays fast and crisp on any phone size or screen.
class Photo360Viewer extends StatefulWidget {
  const Photo360Viewer({
    super.key,
    required this.image,
    this.width,
    this.height,
    this.onReset,
    this.onTap,
  });

  final ImageProvider image;
  final double? width;
  final double? height;
  final VoidCallback? onReset;
  final VoidCallback? onTap;

  @override
  State<Photo360Viewer> createState() => _Photo360ViewerState();
}

class _Photo360ViewerState extends State<Photo360Viewer> {
  double _pan = 0.0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final size = _viewerSize(context);
    final viewWidth = size.width;
    final viewHeight = size.height;

    return SizedBox(
      width: viewWidth,
      height: viewHeight,
      child: GestureDetector(
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) {
          setState(() {
            _pan += details.delta.dx;
            if (viewWidth > 0 && _pan >= viewWidth) {
              _pan -= viewWidth;
            }
            if (_pan < 0) _pan = 0;
          });
        },
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onDoubleTap: () {
          setState(() => _pan = 0.0);
          widget.onReset?.call();
        },
        onTap: widget.onTap,
        child: Stack(
          children: [
            ClipRect(
              child: SizedBox.expand(
                child: Stack(
                  children: [
                    Positioned(
                      left: -_pan,
                      top: 0,
                      width: viewWidth * 2,
                      height: viewHeight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _image(viewWidth, viewHeight),
                          _image(viewWidth, viewHeight),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!_dragging)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_camera_rounded,
                        color: AppColors.success,
                        size: 12,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '360° · drag to look around',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _image(double width, double height) {
    return SizedBox(
      width: width,
      height: height,
      child: Image(
        image: widget.image,
        fit: BoxFit.cover,
        width: width,
        height: height,
      ),
    );
  }

  Size _viewerSize(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final overrideW = widget.width;
    final overrideH = widget.height;
    if (overrideW != null && overrideH != null) {
      return Size(overrideW, overrideH);
    }
    final width = overrideW ?? screen.width;
    var height = overrideH ?? (width / 2);
    final maxHeight = screen.height * 0.62;
    if (height > maxHeight) {
      height = maxHeight;
    }
    return Size(width, height);
  }
}

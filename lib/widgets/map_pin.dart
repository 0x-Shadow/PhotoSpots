import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/categories.dart';
import 'spot_image.dart';

/// Map pin sizes. The tail tip is the anchor, so pins point exactly at their
/// coordinate instead of floating over it.
class MapPinMetrics {
  MapPinMetrics._();

  static const double width = 42;
  static const double height = 54;
  static const double selectedWidth = 58;
  static const double selectedHeight = 74;
}

/// A clean teardrop pin: one path, a soft drop shadow, a white rim, and either
/// a category glyph or the spot's photo in its head.
class SpotPin extends StatelessWidget {
  const SpotPin({
    super.key,
    required this.spot,
    this.selected = false,
    this.showPhoto = false,
  });

  final Spot spot;
  final bool selected;
  final bool showPhoto;

  @override
  Widget build(BuildContext context) {
    final style = pinStyleForSpot(spot);
    final width = selected ? MapPinMetrics.selectedWidth : MapPinMetrics.width;
    final height =
        selected ? MapPinMetrics.selectedHeight : MapPinMetrics.height;
    final head = width * 0.44;
    final center = Offset(width / 2, head + 0.5);

    final glyph = showPhoto
        ? ClipOval(
            child: SpotImage(
              photo: spot.coverPhoto,
              width: head * 1.5,
              height: head * 1.5,
              iconSize: 16,
              cacheWidth: 128,
            ),
          )
        : Icon(
            style.icon,
            color: Colors.white,
            size: head * 0.88,
          );

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _PinPainter(color: style.color, selected: selected),
            ),
          ),
          Positioned(
            left: center.dx - head * 0.76,
            top: center.dy - head * 0.76,
            width: head * 1.52,
            height: head * 1.52,
            child: Center(child: glyph),
          ),
          if (selected)
            Positioned(
              left: center.dx - head - 3,
              top: center.dy - head - 3,
              width: (head + 3) * 2,
              height: (head + 3) * 2,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x59FFFFFF), width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter({required this.color, required this.selected});

  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w * 0.47;
    final cx = w / 2;
    final cy = radius + 1.5;

    final path = Path()
      ..moveTo(cx, h - 1.5)
      ..cubicTo(
        cx - w * 0.10,
        h - h * 0.30,
        cx - radius,
        cy + radius * 0.62,
        cx - radius,
        cy,
      )
      ..arcToPoint(
        Offset(cx + radius, cy),
        radius: Radius.circular(radius),
        clockwise: true,
      )
      ..cubicTo(
        cx + radius,
        cy + radius * 0.62,
        cx + w * 0.10,
        h - h * 0.30,
        cx,
        h - 1.5,
      )
      ..close();

    canvas.drawShadow(path, const Color(0xCC000000), selected ? 9 : 5, false);

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(color, Colors.white, 0.20)!,
          color,
          Color.lerp(color, Colors.black, 0.18)!,
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(path, fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 2.5
        ..color = Colors.white,
    );

    // A quiet specular arc across the head so the pin reads as a rounded solid.
    canvas.save();
    canvas.clipPath(path);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius * 0.86),
      3.5,
      1.35,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.30
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x33FFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PinPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.selected != selected;
}

/// A live location dot with one slow expanding halo. Motion is skipped when the
/// platform asks for reduced animation.
class PulsingLocationDot extends StatefulWidget {
  const PulsingLocationDot({super.key, this.size = 26});

  final double size;

  @override
  State<PulsingLocationDot> createState() => _PulsingLocationDotState();
}

class _PulsingLocationDotState extends State<PulsingLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return Container(
                width: size * (0.55 + 0.45 * t),
                height: size * (0.55 + 0.45 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.26 * (1 - t)),
                ),
              );
            },
          ),
          Container(
            width: size * 0.52,
            height: size * 0.52,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pin used by the publish flow while the user positions a spot. The map
/// centre is the location, so the anchor is the tip.
class PlacementPin extends StatelessWidget {
  const PlacementPin({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 1.0),
      duration: AppMotion.instant,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: const SpotPinPreview(),
    );
  }
}

/// A static preview of the accent pin, used above the map while placing.
class SpotPinPreview extends StatelessWidget {
  const SpotPinPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MapPinMetrics.width,
      height: MapPinMetrics.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _PinPainter(color: AppColors.accent, selected: false),
            ),
          ),
          Positioned(
            left: MapPinMetrics.width / 2 - 9,
            top: MapPinMetrics.width * 0.44 - 9,
            child: const Icon(
              Icons.camera_alt_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact preview of a spot pin, reused by the details summary card.
class SpotPinBadge extends StatelessWidget {
  const SpotPinBadge({super.key, required this.spot});

  final Spot spot;

  @override
  Widget build(BuildContext context) {
    final style = pinStyleForSpot(spot);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: style.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
      ),
      child: Icon(style.icon, color: Colors.white, size: 18),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class GhostIcon extends StatelessWidget {
  final double size;
  final Color color;

  const GhostIcon({this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) {
    // Try SVG asset first, fall back to CustomPaint ghost
    return SvgPicture.asset(
      'assets/icons/ghost.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      placeholderBuilder: (_) => CustomPaint(
        size: Size(size, size),
        painter: GhostPainter(color: color),
      ),
    );
  }
}

class GhostPainter extends CustomPainter {
  final Color color;
  const GhostPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final path = Path()
      // Head (semi-circle top)
      ..moveTo(w * 0.5, h * 0.08)
      ..addArc(
        Rect.fromLTWH(w * 0.1, h * 0.08, w * 0.8, h * 0.55),
        math.pi,
        -math.pi,
      )
      // Right side down
      ..lineTo(w * 0.9, h * 0.88)
      // Wavy bottom - right
      ..cubicTo(w * 0.9, h * 0.75, w * 0.75, h * 0.75, w * 0.75, h * 0.88)
      // Wavy bottom - middle-right
      ..cubicTo(w * 0.75, h * 0.75, w * 0.625, h * 0.75, w * 0.625, h * 0.88)
      // Wavy bottom - middle
      ..cubicTo(w * 0.625, h * 0.75, w * 0.5, h * 0.75, w * 0.5, h * 0.88)
      // Wavy bottom - middle-left
      ..cubicTo(w * 0.5, h * 0.75, w * 0.375, h * 0.75, w * 0.375, h * 0.88)
      // Wavy bottom - left
      ..cubicTo(w * 0.375, h * 0.75, w * 0.25, h * 0.75, w * 0.25, h * 0.88)
      // Left side up
      ..lineTo(w * 0.1, h * 0.88)
      ..close();

    canvas.drawPath(path, paint);

    // Eyes
    final eyePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    final eyeR = w * 0.08;
    canvas.drawCircle(Offset(w * 0.38, h * 0.42), eyeR, eyePaint);
    canvas.drawCircle(Offset(w * 0.62, h * 0.42), eyeR, eyePaint);
  }

  @override
  bool shouldRepaint(covariant GhostPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Model switcher (unchanged from original)
// ---------------------------------------------------------------------------


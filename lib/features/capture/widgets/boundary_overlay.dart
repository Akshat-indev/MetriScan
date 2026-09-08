import 'package:flutter/material.dart';

import '../../../core/services/boundary_detector.dart';

/// Draws the live green magnetic document boundary over the camera preview.
class BoundaryOverlay extends StatelessWidget {
  final BoundaryResult boundary;
  final bool isStable;

  const BoundaryOverlay({
    super.key,
    required this.boundary,
    required this.isStable,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BoundaryPainter(
          corners: boundary.corners,
          isStable: isStable,
          confidence: boundary.confidence,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BoundaryPainter extends CustomPainter {
  final List<Offset> corners; // TL, TR, BR, BL in image pixel space
  final bool isStable;
  final double confidence;

  _BoundaryPainter({
    required this.corners,
    required this.isStable,
    required this.confidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    // We need to map from image pixel space to widget render space.
    // Since we don't have the image dimensions here, we normalise using
    // the bounding box of the corners themselves as a proxy.
    // The preview fills the widget, so this is a reasonable approximation.
    final minX = corners.map((c) => c.dx).reduce((a, b) => a < b ? a : b);
    final maxX = corners.map((c) => c.dx).reduce((a, b) => a > b ? a : b);
    final minY = corners.map((c) => c.dy).reduce((a, b) => a < b ? a : b);
    final maxY = corners.map((c) => c.dy).reduce((a, b) => a > b ? a : b);
    final imgW = maxX - minX == 0 ? 1.0 : maxX; // treat origin as image 0,0
    final imgH = maxY - minY == 0 ? 1.0 : maxY;

    final scaled = corners
        .map((c) => Offset(c.dx / imgW * size.width, c.dy / imgH * size.height))
        .toList();

    final color = isStable
        ? Colors.green.shade400
        : Color.lerp(Colors.orange, Colors.green, confidence) ??
            Colors.orange;

    final edgePaint = Paint()
      ..color = color.withAlpha(200)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withAlpha(25)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(scaled[0].dx, scaled[0].dy)
      ..lineTo(scaled[1].dx, scaled[1].dy)
      ..lineTo(scaled[2].dx, scaled[2].dy)
      ..lineTo(scaled[3].dx, scaled[3].dy)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, edgePaint);

    // Corner handles — magnetic-style dots
    final cornerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const cornerRadius = 6.0;
    for (final pt in scaled) {
      canvas.drawCircle(pt, cornerRadius, cornerPaint);
      // Small L-bracket lines at each corner
      canvas.drawLine(
        pt,
        pt + Offset(pt == scaled[0] || pt == scaled[3] ? 16 : -16, 0),
        edgePaint,
      );
      canvas.drawLine(
        pt,
        pt + Offset(0, pt == scaled[0] || pt == scaled[1] ? 16 : -16),
        edgePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_BoundaryPainter old) =>
      corners != old.corners || isStable != old.isStable;
}

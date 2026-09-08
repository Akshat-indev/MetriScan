import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../constants/rule_definitions.dart';

/// Result of boundary detection on a single camera frame.
class BoundaryResult {
  /// Four corners of the detected document quad [TL, TR, BR, BL] in image-pixel coords.
  final List<Offset> corners;

  /// Detection confidence [0.0 – 1.0].
  final double confidence;

  const BoundaryResult({required this.corners, required this.confidence});

  bool get isStable => confidence > 0.65;
}

/// Detects a rectangular document boundary in a camera frame using
/// OpenCV contour analysis. Smooths results over frames with EMA.
class BoundaryDetector {
  List<Offset>? _smoothedCorners;

  /// Process JPEG [frameBytes] and return the detected document boundary, or null.
  Future<BoundaryResult?> detectFromBytes({
    required Uint8List frameBytes,
    required int frameWidth,
    required int frameHeight,
  }) async {
    final result = await compute(
      _detectInIsolate,
      _DetectArgs(
        bytes: frameBytes,
        width: frameWidth,
        height: frameHeight,
        smoothedCorners: _smoothedCorners,
      ),
    );
    if (result != null) _smoothedCorners = result.corners;
    return result;
  }

  /// Detect boundary from a full-resolution [imageFile] (after capture).
  Future<List<Offset>?> detectFromFile(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    final result = await compute(
      _detectInIsolate,
      _DetectArgs(
        bytes: bytes,
        width: mat.cols,
        height: mat.rows,
        smoothedCorners: null,
      ),
    );
    return result?.corners;
  }

  void reset() => _smoothedCorners = null;
}

class _DetectArgs {
  final Uint8List bytes;
  final int width;
  final int height;
  final List<Offset>? smoothedCorners;
  const _DetectArgs({
    required this.bytes,
    required this.width,
    required this.height,
    required this.smoothedCorners,
  });
}

BoundaryResult? _detectInIsolate(_DetectArgs args) {
  try {
    cv.Mat gray;
    if (args.bytes.length >= args.width * args.height && args.bytes[0] != 0xFF) {
      final yPlane = args.bytes.length == args.width * args.height
          ? args.bytes
          : args.bytes.sublist(0, args.width * args.height);
      gray = cv.Mat.fromList(args.height, args.width, cv.MatType.CV_8UC1, yPlane);
    } else {
      final mat = cv.imdecode(args.bytes, cv.IMREAD_COLOR);
      if (mat.isEmpty) return null;
      gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    }

    // Downscale for massively improved performance (prevents phone heating)
    final double maxDim = args.width > args.height ? args.width.toDouble() : args.height.toDouble();
    final double scale = maxDim > 400 ? 400.0 / maxDim : 1.0;
    
    cv.Mat working;
    if (scale < 1.0) {
      final outW = (args.width * scale).round();
      final outH = (args.height * scale).round();
      working = cv.resize(gray, (outW, outH), interpolation: cv.INTER_AREA);
    } else {
      working = gray;
    }

    final blurred = cv.gaussianBlur(working, (5, 5), 0);
    final edges = cv.canny(blurred, 75, 200);

    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    final dilated = cv.dilate(edges, kernel);

    final (contours, _) = cv.findContours(
      dilated,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );

    if (contours.isEmpty) return null;

    cv.VecPoint? bestContour;
    double bestArea = 0;
    for (var i = 0; i < contours.length; i++) {
      final c = contours[i];
      final area = cv.contourArea(c);
      if (area > bestArea) {
        bestArea = area;
        bestContour = c;
      }
    }
    if (bestContour == null) return null;

    final scaledFrameArea = (args.width * scale) * (args.height * scale);
    if (bestArea < scaledFrameArea * 0.15) return null;

    final peri = cv.arcLength(bestContour, true);
    final approx = cv.approxPolyDP(bestContour, 0.02 * peri, true);

    List<Offset> rawCorners;
    if (approx.length == 4) {
      rawCorners = List.generate(
        4,
        (i) => Offset(approx[i].x / scale, approx[i].y / scale),
      );
    } else {
      final rect = cv.boundingRect(bestContour);
      rawCorners = [
        Offset(rect.x / scale, rect.y / scale),
        Offset((rect.x + rect.width) / scale, rect.y / scale),
        Offset((rect.x + rect.width) / scale, (rect.y + rect.height) / scale),
        Offset(rect.x / scale, (rect.y + rect.height) / scale),
      ];
    }

    final ordered = _orderCorners(rawCorners);
    final conf = (bestArea / scaledFrameArea).clamp(0.0, 1.0);
    return _smooth(ordered, conf, args.smoothedCorners);
  } catch (e) {
    return null;
  }
}

List<Offset> _orderCorners(List<Offset> pts) {
  final sorted = [...pts]..sort((a, b) => a.dy.compareTo(b.dy));
  final top = sorted.sublist(0, 2)..sort((a, b) => a.dx.compareTo(b.dx));
  final bottom = sorted.sublist(2)..sort((a, b) => a.dx.compareTo(b.dx));
  return [top[0], top[1], bottom[1], bottom[0]];
}

BoundaryResult _smooth(
  List<Offset> current,
  double confidence,
  List<Offset>? previous,
) {
  if (previous == null || previous.length != 4) {
    return BoundaryResult(corners: current, confidence: confidence);
  }
  const alpha = kBoundaryEmaAlpha;
  final smoothed = List.generate(
    4,
    (i) => Offset(
      alpha * current[i].dx + (1 - alpha) * previous[i].dx,
      alpha * current[i].dy + (1 - alpha) * previous[i].dy,
    ),
  );
  return BoundaryResult(corners: smoothed, confidence: confidence);
}

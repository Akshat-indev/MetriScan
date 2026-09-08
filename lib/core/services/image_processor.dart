import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Image processing pipeline applied to a captured label photo.
/// Steps: perspective correction → grayscale → CLAHE → unsharp mask.
class ImageProcessor {
  /// Process [inputFile] with optional perspective [corners] (TL,TR,BR,BL).
  Future<String> process({
    required File inputFile,
    List<Offset>? corners,
    required bool detectClipping,
  }) async {
    final bytes = await inputFile.readAsBytes();
    final dir = await getTemporaryDirectory();
    return compute(
      _processInIsolate,
      _ProcessArgs(bytes: bytes, corners: corners, inputPath: inputFile.path, outputDir: dir.path),
    );
  }

  /// Score [imageFile] for sharpness using Laplacian variance.
  Future<double> sharpnessScore(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return compute(_sharpnessInIsolate, bytes);
  }
}

class _ProcessArgs {
  final Uint8List bytes;
  final List<Offset>? corners;
  final String inputPath;
  final String outputDir;
  const _ProcessArgs({
    required this.bytes,
    required this.corners,
    required this.inputPath,
    required this.outputDir,
  });
}

Future<String> _processInIsolate(_ProcessArgs args) async {
  final mat = cv.imdecode(args.bytes, cv.IMREAD_COLOR);

  cv.Mat working;

  // Step 1 — Perspective correction using VecPoint2f
  if (args.corners != null && args.corners!.length == 4) {
    final c = args.corners!;
    final src = cv.VecPoint2f.fromList([
      cv.Point2f(c[0].dx.toFloat(), c[0].dy.toFloat()),
      cv.Point2f(c[1].dx.toFloat(), c[1].dy.toFloat()),
      cv.Point2f(c[2].dx.toFloat(), c[2].dy.toFloat()),
      cv.Point2f(c[3].dx.toFloat(), c[3].dy.toFloat()),
    ]);

    final widthA = _dist(c[2], c[3]);
    final widthB = _dist(c[1], c[0]);
    final outW = math.max(widthA, widthB).round();
    final heightA = _dist(c[1], c[2]);
    final heightB = _dist(c[0], c[3]);
    final outH = math.max(heightA, heightB).round();

    final dst = cv.VecPoint2f.fromList([
      cv.Point2f(0, 0),
      cv.Point2f((outW - 1).toDouble().toFloat(), 0),
      cv.Point2f((outW - 1).toDouble().toFloat(), (outH - 1).toDouble().toFloat()),
      cv.Point2f(0, (outH - 1).toDouble().toFloat()),
    ]);

    final M = cv.getPerspectiveTransform2f(src, dst);
    working = cv.warpPerspective(mat, M, (outW, outH));
  } else {
    working = mat.clone();
  }

  // Step 2 — Scale down if too large (prevents CPU freeze on 12MP+ images)
  final double maxDim = working.rows > working.cols ? working.rows.toDouble() : working.cols.toDouble();
  final double scale = maxDim > 2000.0 ? 2000.0 / maxDim : 1.0;
  
  cv.Mat finalImage;
  if (scale < 1.0) {
    final outW = (working.cols * scale).round();
    final outH = (working.rows * scale).round();
    finalImage = cv.resize(working, (outW, outH), interpolation: cv.INTER_AREA);
  } else {
    finalImage = working;
  }

  // Note: Removed CLAHE and Unsharp Mask because they destroy OCR performance on large text (halos) 
  // and cause extreme lag on mobile CPUs. ML Kit handles raw images best.

  // Encode and save
  final (_, encoded) = cv.imencode('.jpg', finalImage,
      params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]));

  final outPath = p.join(
      args.outputDir, 'processed_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await File(outPath).writeAsBytes(encoded);
  return outPath;
}

double _sharpnessInIsolate(Uint8List bytes) {
  try {
    final mat = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
    
    // Scale down for speed
    final double maxDim = mat.rows > mat.cols ? mat.rows.toDouble() : mat.cols.toDouble();
    final double scale = maxDim > 800.0 ? 800.0 / maxDim : 1.0;
    
    cv.Mat working = mat;
    if (scale < 1.0) {
      final outW = (mat.cols * scale).round();
      final outH = (mat.rows * scale).round();
      working = cv.resize(mat, (outW, outH), interpolation: cv.INTER_AREA);
    }
    
    final lap = cv.laplacian(working, cv.MatType.CV_64F);
    final (_, stddev) = cv.meanStdDev(lap);
    final std = stddev.val1;
    return std * std;
  } catch (_) {
    return 0.0;
  }
}

double _dist(Offset a, Offset b) {
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  return math.sqrt(dx * dx + dy * dy);
}

extension on double {
  double toFloat() => this;
}

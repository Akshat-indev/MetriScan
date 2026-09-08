import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/ocr_block.dart';

/// Wraps Google ML Kit Text Recognizer and converts its output to [OcrBlock]s.
class OcrService {
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// Run OCR on [imageFile] and return all detected text blocks.
  /// [stage] is stored in each block for downstream tracing.
  /// All blocks are returned regardless of confidence.
  Future<List<OcrBlock>> recognise({
    required File imageFile,
    required String stage,
  }) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognised = await _recognizer.processImage(inputImage);

    final blocks = <OcrBlock>[];
    int globalIndex = 0;

    for (final block in recognised.blocks) {
      // Build one OcrBlock per TextLine for finer spatial granularity.
      for (final line in block.lines) {
        final bbox = line.boundingBox;
        final text = line.text.trim();
        if (text.isEmpty) {
          globalIndex++;
          continue;
        }

        // Confidence: average element confidence, fall back to 1.0 if unavailable.
        double conf = 1.0;
        if (line.elements.isNotEmpty) {
          final totalConf = line.elements.fold<double>(
            0.0,
            (sum, e) => sum + (e.confidence ?? 1.0),
          );
          conf = totalConf / line.elements.length;
        }

        final height = bbox.height.toDouble();
        final width = bbox.width.toDouble();

        // Rough font-weight proxy: tall-and-narrow = likely bold.
        final fontWeight =
            (width > 0 && height / (width / text.length) > 0.8)
                ? 'bold'
                : 'normal';

        blocks.add(OcrBlock(
          text: text,
          boundingBox: OcrRect.fromRect(Rect.fromLTWH(
            bbox.left.toDouble(),
            bbox.top.toDouble(),
            bbox.width.toDouble(),
            bbox.height.toDouble(),
          )),
          confidence: conf,
          estimatedFontSizePx: height,
          estimatedFontWeight: fontWeight,
          angleDeg: 0.0, // ML Kit normalises rotation; angle always 0 post-rotation
          stage: stage,
          originalIndex: globalIndex,
        ));
        globalIndex++;
      }
    }

    return blocks;
  }

  /// Run OCR across multiple image files (for back stage multi-photo) and
  /// merge all blocks into a single list.
  Future<List<OcrBlock>> recogniseMultiple({
    required List<File> imageFiles,
    required String stage,
  }) async {
    final allBlocks = <OcrBlock>[];
    for (final file in imageFiles) {
      final blocks = await recognise(imageFile: file, stage: stage);
      allBlocks.addAll(blocks);
    }
    return allBlocks;
  }

  void dispose() => _recognizer.close();
}

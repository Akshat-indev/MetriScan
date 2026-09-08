import 'dart:developer' as developer;

import '../constants/rule_definitions.dart';
import '../models/ocr_block.dart';

class FontSizeResult {
  final bool pass;
  final List<OcrBlock> smallBlocks;
  const FontSizeResult({required this.pass, required this.smallBlocks});
}

/// Estimates whether text blocks meet the minimum legibility threshold.
///
/// NOTE: This is a relative OCR geometry heuristic, NOT a certified legal
/// measurement. Every line in one photo uses the same image-width reference.
/// Blocks below [kMinFontSizeRatio] are flagged as potentially too small.
class FontSizeEstimator {
  FontSizeResult estimate(List<OcrBlock> blocks, double imageWidth) {
    if (blocks.isEmpty || imageWidth <= 0) {
      return const FontSizeResult(pass: true, smallBlocks: []);
    }

    final small = blocks.where((b) {
      final lineHeightPx = b.boundingBox.height;
      final ratio = lineHeightPx / imageWidth;
      developer.log(
        'font-size evidence text="${b.text}" '
        'bbox=[${b.boundingBox.left},${b.boundingBox.top},'
        '${b.boundingBox.width},${b.boundingBox.height}] '
        'source_block_id=${b.originalIndex} '
        'line_height_px=$lineHeightPx image_width=$imageWidth ratio=$ratio '
        'threshold=$kMinFontSizeRatio',
        name: 'metriscan.font_size',
      );
      return ratio < kMinFontSizeRatio && b.text.trim().length > 1;
    }).toList();

    return FontSizeResult(pass: small.isEmpty, smallBlocks: small);
  }
}

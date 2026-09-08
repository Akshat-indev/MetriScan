import 'package:flutter_test/flutter_test.dart';
import 'package:metriscan/core/models/ocr_block.dart';
import 'package:metriscan/core/services/font_size_estimator.dart';

void main() {
  test('ranks OCR lines by their own unmerged bounding-box height', () {
    const blocks = [
      OcrBlock(
        text: 'Product Name',
        boundingBox: OcrRect(left: 10, top: 10, width: 300, height: 80),
        originalIndex: 1,
      ),
      OcrBlock(
        text: 'Ingredients',
        boundingBox: OcrRect(left: 10, top: 120, width: 300, height: 32),
        originalIndex: 2,
      ),
      OcrBlock(
        text: 'Tiny legal text',
        boundingBox: OcrRect(left: 10, top: 180, width: 300, height: 3),
        originalIndex: 3,
      ),
    ];

    final result = FontSizeEstimator().estimate(blocks, 1000);

    expect(blocks[0].boundingBox.height,
        greaterThan(blocks[1].boundingBox.height));
    expect(blocks[1].boundingBox.height,
        greaterThan(blocks[2].boundingBox.height));
    expect(result.smallBlocks.map((block) => block.originalIndex), [3]);
  });
}

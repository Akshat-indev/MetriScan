import 'ocr_block.dart';

class MergedLine {
  final String text;
  final double confidence;
  final List<int> originalIndices;
  final OcrRect boundingBox;

  const MergedLine({
    required this.text,
    required this.confidence,
    required this.originalIndices,
    required this.boundingBox,
  });
}

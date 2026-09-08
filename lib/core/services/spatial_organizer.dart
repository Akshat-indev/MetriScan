import 'dart:ui';
import '../models/ocr_block.dart';
import '../models/merged_line.dart';

/// A spatially-paired label and value block.
class LabelValuePair {
  final OcrBlock keyBlock;
  final OcrBlock? valueBlock;
  final String rawKey;
  final String rawValue;

  const LabelValuePair({
    required this.keyBlock,
    required this.rawKey,
    this.valueBlock,
    this.rawValue = '',
  });
}

/// Re-orders OCR blocks by visual reading order and exposes utilities for
/// spatially pairing labels with their values.
class SpatialOrganizer {
  /// Row-grouping tolerance: blocks within this fraction of [imageHeight]
  /// of each other (by vertical center) are considered the same row.
  static const double _rowToleranceFraction = 0.015;

  /// Maximum horizontal gap fraction between key and value on the same row.
  static const double _sameRowGapFraction = 0.35;

  /// Maximum vertical distance (in block heights) for a value below a key.
  static const double _belowKeyMultiplier = 2.0;

  // ---------------------------------------------------------------------------
  // Main entry point
  // ---------------------------------------------------------------------------

  /// Returns [blocks] sorted into visual reading order (top-to-bottom,
  /// left-to-right within each row).
  List<OcrBlock> sortByReadingOrder(List<OcrBlock> blocks) {
    if (blocks.isEmpty) return [];

    // Sort by vertical center first, then by horizontal center.
    final sorted = [...blocks];
    sorted.sort((a, b) {
      final aDy = a.boundingBox.centerY;
      final bDy = b.boundingBox.centerY;
      if ((aDy - bDy).abs() < 20) {
        return a.boundingBox.centerX.compareTo(b.boundingBox.centerX);
      }
      return aDy.compareTo(bDy);
    });
    return sorted;
  }

  // ---------------------------------------------------------------------------
  // Row grouping
  // ---------------------------------------------------------------------------

  /// Groups [blocks] into rows based on vertical center proximity.
  List<List<OcrBlock>> groupIntoRows(
    List<OcrBlock> blocks, {
    double imageHeight = 1000,
  }) {
    if (blocks.isEmpty) return [];

    final tolerance = imageHeight * _rowToleranceFraction;
    final sorted = sortByReadingOrder(blocks);
    final rows = <List<OcrBlock>>[];
    var currentRow = [sorted.first];
    var rowCenterY = sorted.first.boundingBox.centerY;

    for (var i = 1; i < sorted.length; i++) {
      final block = sorted[i];
      if ((block.boundingBox.centerY - rowCenterY).abs() <= tolerance) {
        currentRow.add(block);
      } else {
        rows.add(currentRow);
        currentRow = [block];
        rowCenterY = block.boundingBox.centerY;
      }
    }
    rows.add(currentRow);
    return rows;
  }

  /// Merges blocks on the same row into single lines/paragraphs.
  List<MergedLine> mergeIntoLines(List<OcrBlock> blocks, {double imageHeight = 1000}) {
    final rows = groupIntoRows(blocks, imageHeight: imageHeight);
    final merged = <MergedLine>[];

    for (final row in rows) {
      if (row.isEmpty) continue;
      
      // Sort row by X coordinate
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      
      final texts = row.map((b) => b.text).join(' ');
      final conf = row.map((b) => b.confidence).reduce((a, b) => a + b) / row.length;
      final indices = row.map((b) => b.originalIndex).toList();
      
      final left = row.first.boundingBox.left;
      final top = row.map((b) => b.boundingBox.top).reduce((a, b) => a < b ? a : b);
      final right = row.last.boundingBox.right;
      final bottom = row.map((b) => b.boundingBox.bottom).reduce((a, b) => a > b ? a : b);
      
      merged.add(MergedLine(
        text: texts,
        confidence: conf,
        originalIndices: indices,
        boundingBox: OcrRect.fromRect(Rect.fromLTRB(left, top, right, bottom)),
      ));
    }
    
    return merged;
  }

  // ---------------------------------------------------------------------------
  // Label → Value spatial pairing
  // ---------------------------------------------------------------------------

  /// Find the value block for [keyBlock] within [allBlocks].
  /// Search order: same row → directly below → adjacent column.
  OcrBlock? findValueFor({
    required OcrBlock keyBlock,
    required List<OcrBlock> allBlocks,
    double imageWidth = 1000,
    double imageHeight = 1000,
  }) {
    final kx = keyBlock.boundingBox.right;
    final ky = keyBlock.boundingBox.centerY;
    final kh = keyBlock.boundingBox.height;

    OcrBlock? best;
    double bestScore = double.infinity;

    for (final block in allBlocks) {
      if (block == keyBlock) continue;
      if (block.text.trim().isEmpty) continue;

      final bLeft = block.boundingBox.left;
      final bCy = block.boundingBox.centerY;

      // 1. Same row, to the right of key
      final sameRow = (bCy - ky).abs() < (kh * 0.8);
      final toRight = bLeft > kx;
      final gap = bLeft - kx;
      if (sameRow && toRight && gap < imageWidth * _sameRowGapFraction) {
        final score = gap;
        if (score < bestScore) {
          bestScore = score;
          best = block;
        }
        continue;
      }

      // 2. Directly below key
      final below = bCy > ky && (bCy - ky) < kh * _belowKeyMultiplier;
      final aligned = (block.boundingBox.centerX - keyBlock.boundingBox.centerX)
              .abs() < imageWidth * 0.25;
      if (below && aligned) {
        final score = (bCy - ky) + 1000; // penalty so same-row preferred
        if (score < bestScore) {
          bestScore = score;
          best = block;
        }
      }
    }

    return best;
  }

  // ---------------------------------------------------------------------------
  // Ingredients section capture
  // ---------------------------------------------------------------------------

  /// Extracts the Ingredients section from [sortedBlocks].
  /// Starts at the block containing an ingredients keyword and collects
  /// subsequent blocks until a section boundary keyword is found.
  String extractIngredients(
    List<OcrBlock> sortedBlocks, {
    required List<String> ingredientsKeywords,
    required List<String> boundaryKeywords,
  }) {
    int startIdx = -1;

    for (var i = 0; i < sortedBlocks.length; i++) {
      final lower = sortedBlocks[i].text.toLowerCase();
      if (ingredientsKeywords.any((kw) => lower.contains(kw))) {
        startIdx = i;
        break;
      }
    }

    if (startIdx == -1) return '';

    final parts = <String>[];
    // Include the trigger block text (stripping the keyword itself later is optional).
    for (var i = startIdx; i < sortedBlocks.length; i++) {
      final lower = sortedBlocks[i].text.toLowerCase();
      // Stop at the next known section header (but not at startIdx itself).
      if (i > startIdx &&
          boundaryKeywords.any((kw) => lower.startsWith(kw))) {
        break;
      }
      parts.add(sortedBlocks[i].text.trim());
    }

    return parts.join(' ');
  }

  // ---------------------------------------------------------------------------
  // Column detection
  // ---------------------------------------------------------------------------

  /// Returns true if [blocks] appear to be laid out in two columns
  /// (significant horizontal gap in the X distribution).
  bool hasTwoColumns(List<OcrBlock> blocks, {double imageWidth = 1000}) {
    if (blocks.length < 4) return false;
    final centers = blocks.map((b) => b.boundingBox.centerX).toList()..sort();
    final mid = imageWidth / 2;
    final leftCount = centers.where((x) => x < mid * 0.7).length;
    final rightCount = centers.where((x) => x > mid * 1.3).length;
    return leftCount >= 2 && rightCount >= 2;
  }
}

import '../../models/field_result.dart';
import '../../models/ocr_block.dart';
import '../spatial_organizer.dart';

/// Extracts front-label fields: product name and company name.
class FrontExtractor {
  final SpatialOrganizer _spatial = SpatialOrganizer();

  List<FieldResult> extract(List<OcrBlock> blocks, double imageWidth) {
    if (blocks.isEmpty) return _allNotFound();

    final sorted = _spatial.sortByReadingOrder(blocks);
    final results = <FieldResult>[];
    final lines = _spatial.mergeIntoLines(sorted);

    if (lines.isEmpty) return _allNotFound();

    // --- Product Name ---
    // Strategy: largest-font block(s) in the top 40% of the image.
    // We look at blocks directly, since font-size matters, but we return the merged line it belongs to.
    final topBlocks = sorted
        .where((b) => b.boundingBox.top < b.boundingBox.height * 3 ||
            b.boundingBox.centerY < _imageHeight(sorted) * 0.4)
        .toList();

    if (topBlocks.isEmpty) {
      results.add(_notFound('product_name', 'Product Name'));
    } else {
      // Pick the tallest font-size group
      topBlocks.sort((a, b) =>
          b.estimatedFontSizePx.compareTo(a.estimatedFontSizePx));
      final maxFontSize = topBlocks.first.estimatedFontSizePx;
      final nameBlocks = topBlocks
          .where((b) => b.estimatedFontSizePx >= maxFontSize * 0.75)
          .toList();

      final indices = nameBlocks.map((b) => b.originalIndex).toSet();
      
      // Find the merged lines that contain these blocks
      final nameLines = lines.where((l) => l.originalIndices.any((idx) => indices.contains(idx))).toList();

      final productName = nameLines.map((l) => l.text.trim()).join(' ');
      final conf = nameLines.isEmpty ? 0.0 : nameLines.map((l) => l.confidence).reduce((a, b) => a + b) / nameLines.length;
      final allIndices = nameLines.expand((l) => l.originalIndices).toList();

      results.add(FieldResult(
        fieldId: 'product_name',
        fieldLabel: 'Product Name',
        status: productName.isNotEmpty ? FieldStatus.found : FieldStatus.notFound,
        matchedText: productName.isNotEmpty ? productName : null,
        normalisedValue: productName.isNotEmpty ? productName : null,
        ocrConfidence: conf,
        matchConfidence: productName.isNotEmpty ? 0.9 : 0.0,
        matchReason: 'Largest font detected in top 40% of label',
        sourceBlockIndices: allIndices,
        stage: 'front',
        fontSizePx: maxFontSize,
      ));
    }

    // --- Company Name ---
    // Strategy: block near product name, 1–5 words, normal/medium font,
    // filtered against single-character/logo tokens.
    final productResult = results.first;
    if (productResult.status == FieldStatus.found && lines.isNotEmpty) {
      // Find blocks with smaller font than product name and 1-5 words
      final maxFont = sorted.map((b) => b.estimatedFontSizePx).reduce(
            (a, b) => a > b ? a : b,
          );

      final candidates = sorted.where((b) {
        final wordCount = b.text.trim().split(RegExp(r'\s+')).length;
        final isSmaller = b.estimatedFontSizePx < maxFont * 0.85;
        final hasWords = wordCount >= 1 && wordCount <= 5;
        // Reject purely symbolic/numeric blocks
        final hasLetters = b.text.contains(RegExp(r'[a-zA-Z]'));
        return isSmaller && hasWords && hasLetters;
      }).toList();

      if (candidates.isEmpty) {
        results.add(_notFound('company_name', 'Company Name'));
      } else {
        // Pick candidate closest to product name blocks (by Y proximity)
        final prodY = productResult.sourceBlockIndices.isNotEmpty
            ? sorted
                .firstWhere(
                    (b) => b.originalIndex == productResult.sourceBlockIndices.first,
                    orElse: () => sorted.first)
                .boundingBox.centerY
            : 0.0;

        candidates.sort((a, b) =>
            (a.boundingBox.centerY - prodY).abs().compareTo((b.boundingBox.centerY - prodY).abs()));

        final companyBlock = candidates.first;
        final companyLine = lines.firstWhere((l) => l.originalIndices.contains(companyBlock.originalIndex), orElse: () => lines.first);
        
        // Clean logo-like symbols (non-letter prefix/suffix chars)
        final cleaned = companyLine.text.replaceAll(RegExp(r'^[^a-zA-Z0-9]+|[^a-zA-Z0-9\s\.]+$'), '').trim();

        results.add(FieldResult(
          fieldId: 'company_name',
          fieldLabel: 'Company Name',
          status: cleaned.isNotEmpty ? FieldStatus.found : FieldStatus.partial,
          matchedText: cleaned.isNotEmpty ? cleaned : companyLine.text,
          normalisedValue: cleaned,
          ocrConfidence: companyLine.confidence,
          matchConfidence: 0.8,
          matchReason: 'Proximity to Product Name (Y=${prodY.toStringAsFixed(1)}) + smaller font',
          sourceBlockIndices: companyLine.originalIndices,
          stage: 'front',
          fontSizePx: companyBlock.estimatedFontSizePx,
        ));
      }
    } else {
      results.add(_notFound('company_name', 'Company Name'));
    }

    return results;
  }

  double _imageHeight(List<OcrBlock> blocks) {
    if (blocks.isEmpty) return 1000;
    return blocks.map((b) => b.boundingBox.bottom).reduce(
          (a, b) => a > b ? a : b,
        );
  }

  FieldResult _notFound(String id, String label) => FieldResult(
        fieldId: id,
        fieldLabel: label,
        status: FieldStatus.notFound,
        violation: '$label not detected on front label.',
        stage: 'front',
      );

  List<FieldResult> _allNotFound() => [
        _notFound('product_name', 'Product Name'),
        _notFound('company_name', 'Company Name'),
      ];
}

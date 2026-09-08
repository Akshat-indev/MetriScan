import '../constants/rule_definitions.dart';
import '../models/field_result.dart';
import '../models/stage_capture.dart';
import '../models/ocr_block.dart';
import '../utils/date_validator.dart';

/// Pass 2 Extractor handles cross-image inference and format-only matching
/// for fields that were not found as co-located key/value pairs in Pass 1.
class Pass2Extractor {
  List<FieldResult> run(List<StageCapture> captures, List<FieldResult> pass1Results) {
    final allBlocks = captures.expand((s) => s.ocrBlocks).toList();
    final updatedResults = List<FieldResult>.from(pass1Results);

    for (int i = 0; i < updatedResults.length; i++) {
      final res = updatedResults[i];
      if (res.isPass) continue; // Already fully found

      FieldResult? inferred;

      switch (res.fieldId) {
        case 'mrp':
          inferred = _inferMrp(allBlocks, res);
          break;
        case 'net_quantity':
          inferred = _inferNetQuantity(allBlocks, res);
          break;
        case 'mfg_date':
          inferred = _inferDate(allBlocks, res, isMfg: true);
          break;
        case 'expiry_date':
          inferred = _inferDate(allBlocks, res, isMfg: false);
          break;
      }

      if (inferred != null) {
        updatedResults[i] = inferred;
      }
    }

    return updatedResults;
  }

  FieldResult? _inferMrp(List<OcrBlock> allBlocks, FieldResult pass1Res) {
    // Look for strict currency format without keyword
    final pureCurrency = RegExp(r'^[₹Rs\.INR\s]*(\d+[.,]\d{2})$', caseSensitive: false);
    
    for (final block in allBlocks) {
      final match = pureCurrency.firstMatch(block.text.trim());
      if (match != null) {
        final val = match.group(1);
        final matchType = pass1Res.status == FieldStatus.partial 
            ? MatchType.crossImageInferred 
            : MatchType.formatOnly;
            
        return FieldResult(
          fieldId: 'mrp',
          fieldLabel: 'MRP',
          status: FieldStatus.found,
          matchedText: block.text,
          normalisedValue: '₹$val',
          ocrConfidence: block.confidence,
          matchConfidence: 0.6, // Lower confidence for Pass 2
          matchReason: 'Pass 2: Found currency format across images',
          sourceBlockIndices: [block.originalIndex],
          stage: 'pass2',
          matchType: matchType,
        );
      }
    }
    return null;
  }

  FieldResult? _inferNetQuantity(List<OcrBlock> allBlocks, FieldResult pass1Res) {
    final pureNetQty = RegExp(r'^(\d+\.?\d*)\s*(g|gm|kg|ml|l|ltr|oz|pcs)\b', caseSensitive: false);
    
    for (final block in allBlocks) {
      final match = pureNetQty.firstMatch(block.text.trim());
      if (match != null) {
        final matchType = pass1Res.status == FieldStatus.partial 
            ? MatchType.crossImageInferred 
            : MatchType.formatOnly;
            
        return FieldResult(
          fieldId: 'net_quantity',
          fieldLabel: 'Net Quantity',
          status: FieldStatus.found,
          matchedText: block.text,
          normalisedValue: match.group(0),
          ocrConfidence: block.confidence,
          matchConfidence: 0.6,
          matchReason: 'Pass 2: Found unit-suffixed format across images',
          sourceBlockIndices: [block.originalIndex],
          stage: 'pass2',
          matchType: matchType,
        );
      }
    }
    return null;
  }

  FieldResult? _inferDate(List<OcrBlock> allBlocks, FieldResult pass1Res, {required bool isMfg}) {
    // Collect all dates from all blocks
    final allDates = <String>[];
    final allMatches = <OcrBlock, String>{};
    
    for (final block in allBlocks) {
      final match = kMfgDateRegex.firstMatch(block.text);
      if (match != null) {
        final val = match.group(0)!;
        final validated = DateValidator.validatedDate(val);
        if (validated != null) {
          allDates.add(validated);
          allMatches[block] = validated;
        }
      }
    }

    if (allDates.isEmpty) return null;

    // Sort dates (naive sort by string assumes DD/MM/YYYY or similar, but for pass 2 it's best effort)
    // Actually, just picking the first found if only 1
    if (allDates.length == 1) {
       // If there's only 1 date, it could be either. We just assign it to whatever we're looking for.
       final b = allMatches.keys.first;
       return FieldResult(
          fieldId: pass1Res.fieldId,
          fieldLabel: pass1Res.fieldLabel,
          status: FieldStatus.found,
          matchedText: b.text,
          normalisedValue: allDates.first,
          ocrConfidence: b.confidence,
          matchConfidence: 0.5,
          matchReason: 'Pass 2: Found lone date format across images',
          sourceBlockIndices: [b.originalIndex],
          stage: 'pass2',
          matchType: pass1Res.status == FieldStatus.partial ? MatchType.crossImageInferred : MatchType.formatOnly,
        );
    }
    
    return null; // Logic for sorting 2 dates can be complex, skip for now.
  }
}

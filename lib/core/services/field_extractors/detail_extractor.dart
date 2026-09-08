import 'dart:developer' as developer;

import '../../constants/rule_definitions.dart';
import '../../models/field_result.dart';
import '../../models/ocr_block.dart';
import '../../models/merged_line.dart';
import '../spatial_organizer.dart';
import '../../utils/text_normalizer.dart';
import '../../utils/date_validator.dart';

/// Extracts detail-label fields: MRP, USP, net quantity, lot number,
/// manufacturing date, and expiry date.
class DetailExtractor {
  final SpatialOrganizer _spatial = SpatialOrganizer();

  List<FieldResult> extract(List<OcrBlock> blocks, double imageWidth) {
    if (blocks.isEmpty) return _allNotFound();

    final sorted = _spatial.sortByReadingOrder(blocks);
    final lines = _spatial.mergeIntoLines(sorted);
    final results = <FieldResult>[];

    developer.log('Detail match order: MRP -> USP -> net quantity -> lot -> dates',
        name: 'DetailExtractor');
    for (final line in lines) {
      developer.log('Checking line for MRP before USP: "${line.text}"',
          name: 'DetailExtractor');
    }
    final mrpResult = _extractMrp(lines, sorted, imageWidth);
    results.add(mrpResult);
    results.add(_extractUsp(lines, sorted, mrpResult, imageWidth));
    results.add(_extractNetQuantity(lines, sorted, imageWidth));
    results.add(_extractLotNumber(lines, sorted, imageWidth));
    results.add(_extractMfgDate(lines, sorted, imageWidth));
    results.add(_extractExpiryDate(lines, sorted, imageWidth, results));

    return results;
  }

  // ---------------------------------------------------------------------------
  // MRP
  // ---------------------------------------------------------------------------

  FieldResult _extractMrp(List<MergedLine> lines, List<OcrBlock> blocks, double imageWidth) {
    // 1. Full line regex
    for (final line in lines) {
      final match = kMrpRegex.firstMatch(line.text);
      if (match != null) {
        final value = match.group(1) ?? '';
        return FieldResult(
          fieldId: 'mrp',
          fieldLabel: 'MRP',
          status: FieldStatus.found,
          matchedText: match.group(0),
          normalisedValue: '₹$value',
          ocrConfidence: line.confidence,
          matchConfidence: 0.95,
          matchReason: 'Regex matched exactly on line: ${line.text}',
          sourceBlockIndices: line.originalIndices,
          stage: 'detail',
        );
      }
    }

    // 2. Block-based fuzzy keyword + spatial value
    for (final block in blocks) {
      final normalized = TextNormalizer.normalizeOcr(block.text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kMrpKeywords);
      if (matchedKw != null) {
        // Try same block
        final idx = block.text.toLowerCase().indexOf(matchedKw[0]);
        if (idx != -1) {
          final remainder = block.text.substring(idx + matchedKw.length);
          final sameBlockMatch = RegExp(r'\d+[.,]?\d*').firstMatch(remainder);
          if (sameBlockMatch != null) {
            return FieldResult(
              fieldId: 'mrp',
              fieldLabel: 'MRP',
              status: FieldStatus.found,
              matchedText: block.text,
              normalisedValue: '₹${sameBlockMatch.group(0)}',
              ocrConfidence: block.confidence,
              matchConfidence: 0.8,
              matchReason: 'Fuzzy keyword "$matchedKw" + number in same block',
              sourceBlockIndices: [block.originalIndex],
              stage: 'detail',
            );
          }
        }

        // Spatial search
        final valueBlock = _spatial.findValueFor(keyBlock: block, allBlocks: blocks, imageWidth: imageWidth);
        if (valueBlock != null) {
          final valMatch = RegExp(r'\d+[.,]?\d*').firstMatch(valueBlock.text);
          if (valMatch != null) {
            return FieldResult(
              fieldId: 'mrp',
              fieldLabel: 'MRP',
              status: FieldStatus.found,
              matchedText: '${block.text} | ${valueBlock.text}',
              normalisedValue: '₹${valMatch.group(0)}',
              ocrConfidence: (block.confidence + valueBlock.confidence) / 2,
              matchConfidence: 0.8,
              matchReason: 'Fuzzy keyword "$matchedKw" + value block found spatially',
              sourceBlockIndices: [block.originalIndex, valueBlock.originalIndex],
              stage: 'detail',
            );
          }
        }
      }
    }

    return const FieldResult(
      fieldId: 'mrp',
      fieldLabel: 'MRP',
      status: FieldStatus.notFound,
      violation: 'MRP not detected. Mandatory under Rule 6.',
      stage: 'detail',
    );
  }

  // ---------------------------------------------------------------------------
  // USP
  // ---------------------------------------------------------------------------

  FieldResult _extractUsp(List<MergedLine> lines, List<OcrBlock> blocks, FieldResult mrpResult, double imageWidth) {
    // 1. Line regex
    for (final line in lines) {
      final match = kUspValueRegex.firstMatch(line.text);
      if (match != null) {
        return FieldResult(
          fieldId: 'usp',
          fieldLabel: 'Unit Sale Price (USP)',
          status: FieldStatus.found,
          matchedText: match.group(0),
          normalisedValue: match.group(0),
          ocrConfidence: line.confidence,
          matchConfidence: 0.9,
          matchReason: 'Regex matched exactly on line: ${line.text}',
          sourceBlockIndices: line.originalIndices,
          stage: 'detail',
        );
      }
    }

    // 2. Spatial search near MRP block
    if (mrpResult.sourceBlockIndices.isNotEmpty) {
      final mrpIdx = mrpResult.sourceBlockIndices.first;
      final mrpBlock = blocks.firstWhere((b) => b.originalIndex == mrpIdx, orElse: () => blocks.first);
      final mrpCy = mrpBlock.boundingBox.centerY;

      // Look in nearby blocks
      final nearby = blocks.where((b) {
        if (b.originalIndex == mrpIdx) return false;
        final dy = (b.boundingBox.centerY - mrpCy).abs();
        return dy < mrpBlock.estimatedFontSizePx * 5;
      }).toList();

      for (final block in nearby) {
        final match = kUspValueRegex.firstMatch(block.text);
        if (match != null) {
          return FieldResult(
            fieldId: 'usp',
            fieldLabel: 'Unit Sale Price (USP)',
            status: FieldStatus.found,
            matchedText: block.text,
            normalisedValue: match.group(0),
            ocrConfidence: block.confidence,
            matchConfidence: 0.85,
            matchReason: 'Regex matched on block near MRP',
            sourceBlockIndices: [block.originalIndex],
            stage: 'detail',
          );
        }
      }
    }

    return const FieldResult(
      fieldId: 'usp',
      fieldLabel: 'Unit Sale Price (USP)',
      status: FieldStatus.notFound,
      stage: 'detail',
    );
  }

  // ---------------------------------------------------------------------------
  // Net Quantity
  // ---------------------------------------------------------------------------

  FieldResult _extractNetQuantity(List<MergedLine> lines, List<OcrBlock> blocks, double imageWidth) {
    // 1. Line regex
    for (final line in lines) {
      final match = kNetQuantityRegex.firstMatch(line.text);
      if (match != null) {
        return FieldResult(
          fieldId: 'net_quantity',
          fieldLabel: 'Net Quantity',
          status: FieldStatus.found,
          matchedText: line.text,
          normalisedValue: match.group(0),
          ocrConfidence: line.confidence,
          matchConfidence: 0.85,
          matchReason: 'Regex matched exactly on line',
          sourceBlockIndices: line.originalIndices,
          stage: 'detail',
        );
      }
    }
    
    // 2. Spatial block search
    for (final block in blocks) {
      final normalized = TextNormalizer.normalizeOcr(block.text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kNetQtyKeywords);
      if (matchedKw != null) {
        final valueBlock = _spatial.findValueFor(keyBlock: block, allBlocks: blocks, imageWidth: imageWidth);
        if (valueBlock != null) {
          final match = RegExp(r'(\d+\.?\d*)\s*(g|gm|gms|kg|ml|l|ltr|litre|litres|oz|pcs|pieces)\b', caseSensitive: false).firstMatch(valueBlock.text);
          if (match != null) {
            return FieldResult(
              fieldId: 'net_quantity',
              fieldLabel: 'Net Quantity',
              status: FieldStatus.found,
              matchedText: '${block.text} | ${valueBlock.text}',
              normalisedValue: match.group(0),
              ocrConfidence: (block.confidence + valueBlock.confidence) / 2,
              matchConfidence: 0.85,
              matchReason: 'Fuzzy keyword "$matchedKw" + spatial value',
              sourceBlockIndices: [block.originalIndex, valueBlock.originalIndex],
              stage: 'detail',
            );
          }
        }
      }
    }

    return const FieldResult(
      fieldId: 'net_quantity',
      fieldLabel: 'Net Quantity',
      status: FieldStatus.notFound,
      violation: 'Net quantity not detected. Mandatory under Rule 6.',
      stage: 'detail',
    );
  }

  // ---------------------------------------------------------------------------
  // Lot Number
  // ---------------------------------------------------------------------------

  FieldResult _extractLotNumber(List<MergedLine> lines, List<OcrBlock> blocks, double imageWidth) {
    // 1. Line based
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final normalized = TextNormalizer.normalizeOcr(line.text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kLotKeywords);
      
      if (matchedKw != null) {
        String candidate = line.text;
        final indices = [...line.originalIndices];
        if (i + 1 < lines.length) {
          candidate += ' ' + lines[i + 1].text;
          indices.addAll(lines[i + 1].originalIndices);
        }

        final idx = candidate.toLowerCase().indexOf(matchedKw[0]);
        final substring = idx >= 0 && idx + matchedKw.length < candidate.length 
            ? candidate.substring(idx + matchedKw.length).trim()
            : candidate;
            
        final match = kLotValueRegex.firstMatch(substring);
        if (match != null) {
          return FieldResult(
            fieldId: 'lot_number',
            fieldLabel: 'Lot Number',
            status: FieldStatus.found,
            matchedText: match.group(0),
            normalisedValue: match.group(0),
            ocrConfidence: line.confidence,
            matchConfidence: 0.9,
            matchReason: 'Fuzzy keyword "$matchedKw" + line pattern',
            sourceBlockIndices: indices,
            stage: 'detail',
          );
        }
      }
    }

    // 2. Spatial block based
    for (final block in blocks) {
      final normalized = TextNormalizer.normalizeOcr(block.text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kLotKeywords);
      if (matchedKw != null) {
        final valueBlock = _spatial.findValueFor(keyBlock: block, allBlocks: blocks, imageWidth: imageWidth);
        if (valueBlock != null) {
          final match = kLotValueRegex.firstMatch(valueBlock.text);
          if (match != null) {
            return FieldResult(
              fieldId: 'lot_number',
              fieldLabel: 'Lot Number',
              status: FieldStatus.found,
              matchedText: '${block.text} | ${valueBlock.text}',
              normalisedValue: match.group(0),
              ocrConfidence: (block.confidence + valueBlock.confidence) / 2,
              matchConfidence: 0.85,
              matchReason: 'Fuzzy keyword "$matchedKw" + spatial value block',
              sourceBlockIndices: [block.originalIndex, valueBlock.originalIndex],
              stage: 'detail',
            );
          }
        }
      }
    }

    return const FieldResult(
      fieldId: 'lot_number',
      fieldLabel: 'Lot Number',
      status: FieldStatus.notFound,
      violation: 'Lot number not detected. Mandatory under Rule 6.',
      stage: 'detail',
    );
  }

  // ---------------------------------------------------------------------------
  // Manufacturing Date
  // ---------------------------------------------------------------------------

  FieldResult _extractMfgDate(List<MergedLine> lines, List<OcrBlock> blocks, double imageWidth) {
    // 1. Line based
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final normalized = TextNormalizer.normalizeOcr(line.text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kMfgDateKeywords);
      
      if (matchedKw != null) {
        String candidate = line.text;
        final indices = [...line.originalIndices];
        if (i + 1 < lines.length) {
          candidate += ' ' + lines[i + 1].text;
          indices.addAll(lines[i + 1].originalIndices);
        }

        final match = kMfgDateRegex.firstMatch(candidate);
        if (match != null) {
          final normDate = _normaliseDate(match.group(0)!);
          if (DateValidator.isValidDateString(normDate)) {
            return FieldResult(
              fieldId: 'mfg_date',
              fieldLabel: 'Manufacturing Date',
              status: FieldStatus.found,
              matchedText: match.group(0),
              normalisedValue: normDate,
              ocrConfidence: line.confidence,
              matchConfidence: 0.9,
              matchReason: 'Fuzzy keyword "$matchedKw" + line pattern',
              sourceBlockIndices: indices,
              stage: 'detail',
            );
          }
        }
      }
    }

    // 2. Spatial block based
    for (final block in blocks) {
      final normalized = TextNormalizer.normalizeOcr(block.text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kMfgDateKeywords);
      if (matchedKw != null) {
        final valueBlock = _spatial.findValueFor(keyBlock: block, allBlocks: blocks, imageWidth: imageWidth);
        if (valueBlock != null) {
          final match = kMfgDateRegex.firstMatch(valueBlock.text);
          if (match != null) {
            final normDate = _normaliseDate(match.group(0)!);
            if (DateValidator.isValidDateString(normDate)) {
              return FieldResult(
                fieldId: 'mfg_date',
                fieldLabel: 'Manufacturing Date',
                status: FieldStatus.found,
                matchedText: '${block.text} | ${valueBlock.text}',
                normalisedValue: normDate,
                ocrConfidence: (block.confidence + valueBlock.confidence) / 2,
                matchConfidence: 0.85,
                matchReason: 'Fuzzy keyword "$matchedKw" + spatial value block',
                sourceBlockIndices: [block.originalIndex, valueBlock.originalIndex],
                stage: 'detail',
              );
            }
          }
        }
      }
    }
    
    return const FieldResult(
      fieldId: 'mfg_date',
      fieldLabel: 'Manufacturing Date',
      status: FieldStatus.notFound,
      violation: 'Manufacturing/packing date not detected. Mandatory under Rule 6.',
      stage: 'detail',
    );
  }

  // ---------------------------------------------------------------------------
  // Expiry Date
  // ---------------------------------------------------------------------------

  FieldResult _extractExpiryDate(List<MergedLine> lines, List<OcrBlock> blocks, double imageWidth, List<FieldResult> existing) {
    final mfgNorm = existing
        .firstWhere((r) => r.fieldId == 'mfg_date',
            orElse: () => const FieldResult(
                  fieldId: 'mfg_date',
                  fieldLabel: '',
                  status: FieldStatus.notFound,
                ))
        .normalisedValue;

    // 1. Line based
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final normalized = TextNormalizer.normalizeOcr(line.text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kExpiryKeywords);
      
      if (matchedKw != null) {
        String candidate = line.text;
        final indices = [...line.originalIndices];
        if (i + 1 < lines.length) {
          candidate += ' ' + lines[i + 1].text;
          indices.addAll(lines[i + 1].originalIndices);
        }

        final match = kExpiryDateRegex.firstMatch(candidate);
        if (match != null) {
          final norm = DateValidator.validatedDate(_normaliseDate(match.group(0)!));
          if (norm == null) continue;
          String? violation;
          if (mfgNorm != null && norm == mfgNorm) {
            violation = 'Expiry date matches manufacturing date — possible extraction error.';
          }
          return FieldResult(
            fieldId: 'expiry_date',
            fieldLabel: 'Expiry / Best Before',
            status: violation != null ? FieldStatus.partial : FieldStatus.found,
            matchedText: match.group(0),
            normalisedValue: norm,
            ocrConfidence: line.confidence,
            matchConfidence: violation != null ? 0.4 : 0.9,
            matchReason: 'Fuzzy keyword "$matchedKw" + line pattern',
            sourceBlockIndices: indices,
            violation: violation,
            stage: 'detail',
          );
        }
      }
    }

    // 2. Spatial block based
    for (final block in blocks) {
      final normalized = TextNormalizer.normalizeOcr(block.text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kExpiryKeywords);
      if (matchedKw != null) {
        final valueBlock = _spatial.findValueFor(keyBlock: block, allBlocks: blocks, imageWidth: imageWidth);
        if (valueBlock != null) {
          final match = kExpiryDateRegex.firstMatch(valueBlock.text);
          if (match != null) {
            final norm = DateValidator.validatedDate(_normaliseDate(match.group(0)!));
            if (norm == null) continue;
            String? violation;
            if (mfgNorm != null && norm == mfgNorm) {
              violation = 'Expiry date matches manufacturing date — possible extraction error.';
            }
            return FieldResult(
              fieldId: 'expiry_date',
              fieldLabel: 'Expiry / Best Before',
              status: violation != null ? FieldStatus.partial : FieldStatus.found,
              matchedText: '${block.text} | ${valueBlock.text}',
              normalisedValue: norm,
              ocrConfidence: (block.confidence + valueBlock.confidence) / 2,
              matchConfidence: violation != null ? 0.4 : 0.85,
              matchReason: 'Fuzzy keyword "$matchedKw" + spatial value block',
              sourceBlockIndices: [block.originalIndex, valueBlock.originalIndex],
              violation: violation,
              stage: 'detail',
            );
          }
        }
      }
    }

    return const FieldResult(
      fieldId: 'expiry_date',
      fieldLabel: 'Expiry / Best Before',
      status: FieldStatus.notFound,
      stage: 'detail',
    );
  }

  // ---------------------------------------------------------------------------
  // Date normalisation (best-effort, not certified)
  // ---------------------------------------------------------------------------

  static const _monthAbbrev = {
    'jan': '01', 'feb': '02', 'mar': '03', 'apr': '04',
    'may': '05', 'jun': '06', 'jul': '07', 'aug': '08',
    'sep': '09', 'oct': '10', 'nov': '11', 'dec': '12',
  };

  String _normaliseDate(String raw) {
    final lower = raw.toLowerCase().trim();

    // "Jan 2026" / "January 2026"
    final monthYear = RegExp(
        r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s,\.]+(\d{4})',
        caseSensitive: false);
    final my = monthYear.firstMatch(lower);
    if (my != null) {
      final m = _monthAbbrev[my.group(1)!.substring(0, 3)] ?? my.group(1)!;
      return '${my.group(2)!}-$m';
    }

    final dmy = RegExp(r'(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{4})')
        .firstMatch(lower);
    if (dmy != null) {
      return '${dmy.group(3)!}-${dmy.group(2)!.padLeft(2, '0')}-${dmy.group(1)!.padLeft(2, '0')}';
    }

    // "MM/YYYY" or "MM-YYYY"
    final mmyyyy = RegExp(r'(\d{1,2})[\/\-\.](\d{4})').firstMatch(lower);
    if (mmyyyy != null) {
      return '${mmyyyy.group(2)!}-${mmyyyy.group(1)!.padLeft(2, '0')}';
    }

    return raw.trim();
  }

  List<FieldResult> _allNotFound() => const [
        FieldResult(fieldId: 'mrp', fieldLabel: 'MRP', status: FieldStatus.notFound, stage: 'detail'),
        FieldResult(fieldId: 'usp', fieldLabel: 'USP', status: FieldStatus.notFound, stage: 'detail'),
        FieldResult(fieldId: 'net_quantity', fieldLabel: 'Net Quantity', status: FieldStatus.notFound, stage: 'detail'),
        FieldResult(fieldId: 'lot_number', fieldLabel: 'Lot Number', status: FieldStatus.notFound, stage: 'detail'),
        FieldResult(fieldId: 'mfg_date', fieldLabel: 'Manufacturing Date', status: FieldStatus.notFound, stage: 'detail'),
        FieldResult(fieldId: 'expiry_date', fieldLabel: 'Expiry / Best Before', status: FieldStatus.notFound, stage: 'detail'),
      ];
}

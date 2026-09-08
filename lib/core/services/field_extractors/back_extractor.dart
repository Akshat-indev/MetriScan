import '../../constants/rule_definitions.dart';
import '../../models/field_result.dart';
import '../../models/ocr_block.dart';
import '../../models/merged_line.dart';
import '../spatial_organizer.dart';
import '../../utils/text_normalizer.dart';

/// Extracts back-label fields: manufacturer, packer, importer, FSSAI,
/// consumer care details, country of origin, and ingredients.
class BackExtractor {
  final SpatialOrganizer _spatial = SpatialOrganizer();

  List<FieldResult> extract(List<OcrBlock> blocks) {
    if (blocks.isEmpty) return _allNotFound();

    final lines = _spatial.mergeIntoLines(blocks);
    final results = <FieldResult>[];

    results.add(_extractKeywordField(
      lines: lines,
      fieldId: 'manufacturer',
      fieldLabel: 'Manufacturer Name & Address',
      keywords: kMfgKeywords,
      takeLinesAfter: 3,
      stage: 'back',
    ));

    results.add(_extractKeywordField(
      lines: lines,
      fieldId: 'packer',
      fieldLabel: 'Packer',
      keywords: kPackerKeywords,
      takeLinesAfter: 2,
      stage: 'back',
    ));

    results.add(_extractKeywordField(
      lines: lines,
      fieldId: 'importer',
      fieldLabel: 'Importer',
      keywords: kImporterKeywords,
      takeLinesAfter: 2,
      stage: 'back',
    ));

    results.add(_extractFssai(lines));
    results.add(_extractConsumerCare(lines));
    results.add(_extractCountryOfOrigin(lines));
    results.add(_extractIngredients(lines));

    return results;
  }

  // ---------------------------------------------------------------------------
  // Manufacturer / Packer / Importer — keyword + subsequent lines
  // ---------------------------------------------------------------------------

  FieldResult _extractKeywordField({
    required List<MergedLine> lines,
    required String fieldId,
    required String fieldLabel,
    required List<String> keywords,
    required int takeLinesAfter,
    required String stage,
    FieldStatus defaultStatus = FieldStatus.notFound,
  }) {
    for (var i = 0; i < lines.length; i++) {
      final normalized = TextNormalizer.normalizeOcr(lines[i].text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, keywords, maxDistance: 2);
      
      if (matchedKw == null) continue;

      // Collect the anchor line + next N lines as the value
      final valueParts = <String>[];
      final indices = <int>[...lines[i].originalIndices];

      // The value might be on the same line after the keyword
      final sameLineValue = _stripKeyword(lines[i].text, keywords);
      if (sameLineValue.isNotEmpty) valueParts.add(sameLineValue);

      for (var j = i + 1; j < lines.length && j <= i + takeLinesAfter; j++) {
        // Stop if next line is another section anchor
        final nextNorm = TextNormalizer.normalizeOcr(lines[j].text);
        final isNewSection = (kMfgKeywords + kPackerKeywords +
                kImporterKeywords + kConsumerCareKeywords + kFssaiKeywords + kSectionBoundaryKeywords)
            .any((kw) => TextNormalizer.fuzzyMatchAny(nextNorm, [kw], maxDistance: 1) != null);
            
        if (isNewSection) break;
        valueParts.add(lines[j].text.trim());
        indices.addAll(lines[j].originalIndices);
      }

      final value = valueParts.join(', ').trim();
      final conf = lines[i].confidence;

      return FieldResult(
        fieldId: fieldId,
        fieldLabel: fieldLabel,
        status: value.isNotEmpty ? FieldStatus.found : FieldStatus.partial,
        matchedText: value.isNotEmpty ? value : lines[i].text,
        normalisedValue: value,
        ocrConfidence: conf,
        matchConfidence: value.isNotEmpty ? 0.9 : 0.4,
        matchReason: 'Fuzzy keyword "$matchedKw" + ${valueParts.length} lines',
        sourceBlockIndices: indices.toSet().toList(),
        stage: stage,
      );
    }

    return FieldResult(
      fieldId: fieldId,
      fieldLabel: fieldLabel,
      status: defaultStatus,
      violation: defaultStatus == FieldStatus.notFound
          ? '$fieldLabel not detected on back label.'
          : null,
      stage: stage,
    );
  }

  // ---------------------------------------------------------------------------
  // FSSAI License
  // ---------------------------------------------------------------------------

  FieldResult _extractFssai(List<MergedLine> lines) {
    for (var i = 0; i < lines.length; i++) {
      final normalized = TextNormalizer.normalizeOcr(lines[i].text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kFssaiKeywords);
      
      if (matchedKw == null) continue;

      // Try to find the 14-digit number in this line or the next line
      String candidate = lines[i].text;
      final indices = <int>[...lines[i].originalIndices];
      
      if (i + 1 < lines.length) {
        candidate += ' ${lines[i + 1].text}';
        indices.addAll(lines[i + 1].originalIndices);
      }

      final match = kFssaiNumberRegex.firstMatch(candidate);
      if (match != null) {
        // Normalize: remove spaces and dots
        final raw = match.group(0)!;
        final normalized = raw.replaceAll(RegExp(r'[\s\.]'), '');
        return FieldResult(
          fieldId: 'fssai_license',
          fieldLabel: 'FSSAI License No.',
          status: FieldStatus.found,
          matchedText: raw,
          normalisedValue: normalized,
          ocrConfidence: lines[i].confidence,
          matchConfidence: 0.95,
          matchReason: 'Fuzzy keyword "$matchedKw" + 14-digit pattern',
          sourceBlockIndices: indices.toSet().toList(),
          stage: 'back',
        );
      }

      // Found keyword but couldn't extract number
      return FieldResult(
        fieldId: 'fssai_license',
        fieldLabel: 'FSSAI License No.',
        status: FieldStatus.partial,
        matchedText: lines[i].text,
        violation: 'FSSAI keyword found but license number not extractable.',
        ocrConfidence: lines[i].confidence,
        matchConfidence: 0.5,
        matchReason: 'Fuzzy keyword "$matchedKw" but no valid license number found',
        sourceBlockIndices: lines[i].originalIndices,
        stage: 'back',
      );
    }

    return const FieldResult(
      fieldId: 'fssai_license',
      fieldLabel: 'FSSAI License No.',
      status: FieldStatus.conditional,
      violation: null, // only mandatory for food products
      stage: 'back',
    );
  }

  // ---------------------------------------------------------------------------
  // Consumer Care
  // ---------------------------------------------------------------------------

  FieldResult _extractConsumerCare(List<MergedLine> lines) {
    final contactParts = <String>[];
    final indices = <int>[];
    bool hasAnchor = false;

    for (final line in lines) {
      final normalized = TextNormalizer.normalizeOcr(line.text);
      final isAnchor = TextNormalizer.fuzzyMatchAny(normalized, kConsumerCareKeywords) != null;
      final hasPhone = kPhoneRegex.hasMatch(line.text);
      final hasEmail = kEmailRegex.hasMatch(line.text);

      if (isAnchor) hasAnchor = true;

      if (isAnchor || hasPhone || hasEmail) {
        contactParts.add(line.text.trim());
        indices.addAll(line.originalIndices);
      }
    }

    if (contactParts.isEmpty) {
      return const FieldResult(
        fieldId: 'consumer_care',
        fieldLabel: 'Consumer Care Details',
        status: FieldStatus.notFound,
        violation: 'Consumer care contact details not detected.',
        stage: 'back',
      );
    }

    return FieldResult(
      fieldId: 'consumer_care',
      fieldLabel: 'Consumer Care Details',
      status: hasAnchor ? FieldStatus.found : FieldStatus.partial,
      matchedText: contactParts.join(' | '),
      normalisedValue: contactParts.join(' | '),
      ocrConfidence: 0.8, // Approximation for merged blocks
      matchConfidence: hasAnchor ? 0.9 : 0.6,
      matchReason: 'Found ${contactParts.length} contact detail lines (has anchor: $hasAnchor)',
      sourceBlockIndices: indices.toSet().toList(),
      stage: 'back',
    );
  }

  // ---------------------------------------------------------------------------
  // Country of Origin
  // ---------------------------------------------------------------------------

  FieldResult _extractCountryOfOrigin(List<MergedLine> lines) {
    for (final line in lines) {
      final normalized = TextNormalizer.normalizeOcr(line.text);
      final matchedKw = TextNormalizer.fuzzyMatchAny(normalized, kCountryKeywords);
      
      if (matchedKw != null) {
        final val = _stripKeyword(line.text, kCountryKeywords);
        return FieldResult(
          fieldId: 'country_of_origin',
          fieldLabel: 'Country of Origin',
          status: FieldStatus.found,
          matchedText: line.text,
          normalisedValue: val.isNotEmpty ? val : 'Found (unparsed)',
          ocrConfidence: line.confidence,
          matchConfidence: 0.9,
          matchReason: 'Fuzzy keyword "$matchedKw"',
          sourceBlockIndices: line.originalIndices,
          stage: 'back',
        );
      }
    }

    return const FieldResult(
      fieldId: 'country_of_origin',
      fieldLabel: 'Country of Origin',
      status: FieldStatus.conditional, // Only for imported
      stage: 'back',
    );
  }

  // ---------------------------------------------------------------------------
  // Ingredients (Warning / Presence)
  // ---------------------------------------------------------------------------

  FieldResult _extractIngredients(List<MergedLine> lines) {
    return _extractKeywordField(
      lines: lines,
      fieldId: 'ingredients',
      fieldLabel: 'Ingredients List',
      keywords: kIngredientsKeywords,
      takeLinesAfter: 15, // Ingredients lists are often very long
      stage: 'back',
      defaultStatus: FieldStatus.conditional,
    );
  }

  // ---------------------------------------------------------------------------
  // Utils
  // ---------------------------------------------------------------------------

  String _stripKeyword(String text, List<String> keywords) {
    String lower = text.toLowerCase();
    for (final kw in keywords) {
      final idx = lower.indexOf(kw);
      if (idx != -1) {
        return text.substring(idx + kw.length).replaceAll(RegExp(r'^[:\-\s]+'), '').trim();
      }
    }
    return '';
  }

  List<FieldResult> _allNotFound() => const [
        FieldResult(fieldId: 'manufacturer', fieldLabel: 'Manufacturer', status: FieldStatus.notFound, stage: 'back'),
        FieldResult(fieldId: 'packer', fieldLabel: 'Packer', status: FieldStatus.notFound, stage: 'back'),
        FieldResult(fieldId: 'importer', fieldLabel: 'Importer', status: FieldStatus.notFound, stage: 'back'),
        FieldResult(fieldId: 'fssai_license', fieldLabel: 'FSSAI License', status: FieldStatus.notFound, stage: 'back'),
        FieldResult(fieldId: 'consumer_care', fieldLabel: 'Consumer Care', status: FieldStatus.notFound, stage: 'back'),
        FieldResult(fieldId: 'country_of_origin', fieldLabel: 'Country of Origin', status: FieldStatus.notFound, stage: 'back'),
        FieldResult(fieldId: 'ingredients', fieldLabel: 'Ingredients', status: FieldStatus.notFound, stage: 'back'),
      ];
}

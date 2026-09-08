import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/compliance_report.dart';
import '../models/field_result.dart';
import '../models/ocr_block.dart';
import '../utils/date_validator.dart';

/// Builds and saves the finalization JSON record for every completed scan.
/// The JSON is designed for future AI training use.
class TrainingRecordBuilder {
  static const String schemaVersion = '1.0';

  /// Build and write the training JSON to [appDocDir]/output/[scanId].json.
  /// Returns the path of the saved file.
  Future<String> buildAndSave(
    ComplianceReport report, {
    String verificationStatus = 'unverified',
    List<Map<String, dynamic>> corrections = const [],
  }) async {
    final json = buildJson(
      report,
      verificationStatus: verificationStatus,
      corrections: corrections,
    );
    final dir = await getApplicationDocumentsDirectory();
    final outputDir = Directory(p.join(dir.path, 'output'));
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

    final filePath = p.join(outputDir.path, '${report.scanId}.json');
    await File(filePath).writeAsString(jsonEncode(json), flush: true);
    return filePath;
  }

  Map<String, dynamic> buildJson(
    ComplianceReport report, {
    String verificationStatus = 'unverified',
    List<Map<String, dynamic>> corrections = const [],
  }) {
    return {
      'schema_version': schemaVersion,
      'scan_id': report.scanId,
      'timestamp': report.timestamp.toIso8601String(),
      'stages': report.stages.map((stage) => {
        'stage': stage.stage.name,
        'image_paths': stage.imagePaths,
        'has_clipping': stage.hasClipping,
        'all_raw_text': stage.allRawText,
        'ocr_blocks': stage.ocrBlocks.map(_blockToJson).toList(),
      }).toList(),
      'raw_ocr_blocks': [
        for (final stage in report.stages)
          for (final block in stage.ocrBlocks)
            {
              'text': block.text,
              'bounding_box': [
                block.boundingBox.left,
                block.boundingBox.top,
                block.boundingBox.width,
                block.boundingBox.height,
              ],
              'confidence': block.confidence,
              'stage': stage.stage.name,
            },
      ],
      'extracted_fields': {
        for (final r in report.fieldResults)
          r.fieldId: _fieldJson(report, r),
      },
      'compliance': {
        'overall_score': report.overallScore,
        'fields_found': report.mandatoryFound,
        'fields_total': report.mandatoryTotal,
        'violations': report.violations,
        'font_size_pass': report.fontSizePass,
        'small_text_block_indices': report.smallTextBlocks
            .map((b) => b.originalIndex)
            .toList(),
      },
      'verification_status': verificationStatus,
      'corrections_made': corrections,
      'training_label': null,
    };
  }

  Map<String, dynamic>? _fieldJson(
      ComplianceReport report, FieldResult result) {
    final isDate = result.fieldId == 'mfg_date' || result.fieldId == 'expiry_date';
    final value = isDate
        ? DateValidator.validatedDate(result.normalisedValue ?? '')
        : result.normalisedValue ?? result.matchedText;
    if (value == null || value.isEmpty) return null;
    return {
      'value': value,
      'bounding_box': _boundingBoxFor(report, result),
      'matched_raw': result.matchedText,
      'ocr_confidence': result.ocrConfidence,
      'match_confidence': result.matchConfidence,
      'field_match_confidence': result.matchConfidence,
      'match_type': _matchTypeName(result.matchType),
      'status': result.status.name,
      'source_block_indices': result.sourceBlockIndices,
      'stage': result.stage,
      'match_reason': result.matchReason,
    };
  }

  String _matchTypeName(MatchType type) => switch (type) {
        MatchType.coLocated => 'co_located',
        MatchType.crossImageInferred => 'cross_image_inferred',
        MatchType.formatOnly => 'format_only',
      };

  List<double>? _boundingBoxFor(
      ComplianceReport report, FieldResult result) {
    for (final stage in report.stages) {
      for (final block in stage.ocrBlocks) {
        if (result.sourceBlockIndices.contains(block.originalIndex)) {
          return [
            block.boundingBox.left,
            block.boundingBox.top,
            block.boundingBox.width,
            block.boundingBox.height,
          ];
        }
      }
    }
    return null;
  }

  /// Appends a verified record without invoking or changing any model.
  Future<String> appendVerifiedRecord(
    ComplianceReport report, {
    List<Map<String, dynamic>> corrections = const [],
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final outputDir = Directory(p.join(dir.path, 'output'));
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);
    final file = File(p.join(outputDir.path, 'training_set.jsonl'));
    await file.writeAsString(
      '${jsonEncode(buildJson(report, verificationStatus: 'verified', corrections: corrections))}\n',
      mode: FileMode.append,
      flush: true,
    );
    return file.path;
  }

  Future<Map<String, int>> verifiedCounts() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'output', 'training_set.jsonl'));
    if (!file.existsSync()) return {};
    final counts = <String, int>{};
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      final record = jsonDecode(line) as Map<String, dynamic>;
      if (record['verification_status'] != 'verified') continue;
      final fields = record['extracted_fields'] as Map<String, dynamic>;
      for (final entry in fields.entries) {
        if (entry.value != null) {
          counts[entry.key] = (counts[entry.key] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  Map<String, dynamic> _blockToJson(OcrBlock block) => {
        'text': block.text,
        'bounding_box': {
          'x': block.boundingBox.left,
          'y': block.boundingBox.top,
          'w': block.boundingBox.width,
          'h': block.boundingBox.height,
        },
        'confidence': block.confidence,
        'estimated_font_size_px': block.estimatedFontSizePx,
        'estimated_font_weight': block.estimatedFontWeight,
        'angle_deg': block.angleDeg,
        'stage': block.stage,
        'original_index': block.originalIndex,
      };
}

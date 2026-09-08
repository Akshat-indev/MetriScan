
import '../models/compliance_report.dart';
import '../models/field_result.dart';
import '../models/ocr_block.dart';
import '../models/stage_capture.dart';
import 'field_extractors/back_extractor.dart';
import 'field_extractors/detail_extractor.dart';
import 'field_extractors/front_extractor.dart';
import 'pass2_extractor.dart';
import 'font_size_estimator.dart';
import 'report_builder.dart';
import '../../correction_memory/correction_memory.dart';

/// Orchestrates all field extractors over the three scan stages and assembles
/// the final [ComplianceReport].
class RuleEngine {
  final FrontExtractor _front = FrontExtractor();
  final BackExtractor _back = BackExtractor();
  final DetailExtractor _detail = DetailExtractor();
  final Pass2Extractor _pass2 = Pass2Extractor();
  final FontSizeEstimator _fontSizeEstimator = FontSizeEstimator();
  final ReportBuilder _reportBuilder = ReportBuilder();

  Future<ComplianceReport> analyse({
    required String scanId,
    required List<StageCapture> stages,
  }) async {
    final allResults = <FieldResult>[];

    // --- Front stage ---
    final frontCapture = stages.where((s) => s.stage.name == 'front').firstOrNull;
    if (frontCapture != null && frontCapture.ocrBlocks.isNotEmpty) {
      final imageWidth = _estimateImageWidth(frontCapture.ocrBlocks);
      allResults.addAll(_front.extract(frontCapture.ocrBlocks, imageWidth));
    }

    // --- Back stage (merged from all back photos) ---
    final backCapture = stages.where((s) => s.stage.name == 'back').firstOrNull;
    if (backCapture != null && backCapture.ocrBlocks.isNotEmpty) {
      allResults.addAll(_back.extract(backCapture.ocrBlocks));
    }

    // --- Detail stage ---
    final detailCapture =
        stages.where((s) => s.stage.name == 'detail').firstOrNull;
    if (detailCapture != null && detailCapture.ocrBlocks.isNotEmpty) {
      final imageWidth = _estimateImageWidth(detailCapture.ocrBlocks);
      allResults.addAll(_detail.extract(detailCapture.ocrBlocks, imageWidth));
    }

    // --- Font size estimation (per-stage image scale) ---
    final smallBlocks = <OcrBlock>[];
    for (final stage in stages) {
      if (stage.imageWidth <= 0) continue;
      final result = _fontSizeEstimator.estimate(
        stage.ocrBlocks,
        stage.imageWidth.toDouble(),
      );
      smallBlocks.addAll(result.smallBlocks);
    }

    // --- Pass 1 Deduplicate: if a field appears in multiple stages, keep higher confidence ---
    var deduplicated = _deduplicateResults(allResults);

    // --- Pass 2: Cross-image / format-only matching for missing fields ---
    deduplicated = _pass2.run(stages, deduplicated);

    final extractedFields = <String, String?>{
      for (final result in deduplicated)
        result.fieldId: result.normalisedValue ?? result.matchedText,
    };
    // TEMPORARY: correction-memory stand-in, remove when trained model replaces this (see /correction_memory/README.md)
    final rememberedFields =
        await CorrectionMemory().applyKnownProduct(extractedFields);
    deduplicated = [
      for (final result in deduplicated)
        _applyRememberedValue(result, rememberedFields[result.fieldId]),
    ];

    return _reportBuilder.build(
      scanId: scanId,
      stages: stages,
      fieldResults: deduplicated,
      fontSizePass: smallBlocks.isEmpty,
      smallTextBlocks: smallBlocks,
    );
  }

  FieldResult _applyRememberedValue(FieldResult result, String? remembered) {
    if (remembered == null || remembered.trim().isEmpty) return result;
    if (remembered == result.normalisedValue) return result;
    return result.copyWith(
      status: FieldStatus.found,
      matchedText: remembered,
      normalisedValue: remembered,
      matchConfidence: 1.0,
      matchReason: 'Verified correction-memory product match',
    );
  }

  /// If two stages both found the same field, keep the one with higher match confidence.
  List<FieldResult> _deduplicateResults(List<FieldResult> results) {
    final map = <String, FieldResult>{};
    for (final r in results) {
      final existing = map[r.fieldId];
      if (existing == null) {
        map[r.fieldId] = r;
      } else {
        // Prioritize Found > Partial > NotFound
        if (r.status.isPass && !existing.status.isPass) {
          map[r.fieldId] = r;
        } else if (!r.status.isPass && existing.status.isPass) {
          continue;
        } else if (r.matchConfidence > existing.matchConfidence) {
          map[r.fieldId] = r;
        } else if (r.matchConfidence == existing.matchConfidence && r.ocrConfidence > existing.ocrConfidence) {
          map[r.fieldId] = r;
        }
      }
    }
    return map.values.toList();
  }

  double _estimateImageWidth(List<OcrBlock> blocks) {
    if (blocks.isEmpty) return 1000;
    return blocks
        .map((b) => b.boundingBox.right)
        .reduce((a, b) => a > b ? a : b);
  }
}

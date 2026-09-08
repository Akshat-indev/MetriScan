import 'package:flutter_test/flutter_test.dart';
import 'package:metriscan/core/constants/rule_definitions.dart';
import 'package:metriscan/core/models/field_result.dart';
import 'package:metriscan/core/models/ocr_block.dart';
import 'package:metriscan/core/models/compliance_report.dart';
import 'package:metriscan/core/models/scan_stage.dart';
import 'package:metriscan/core/models/stage_capture.dart';
import 'package:metriscan/core/services/field_extractors/detail_extractor.dart';
import 'package:metriscan/core/services/training_record_builder.dart';

void main() {
  group('Detail Extraction Tests', () {
    test('MRP and USP can both be extracted from the same string', () {
      final text = 'Rs.89.00 Rs.0.36 per gram';
      
      final mrpMatch = kMrpRegex.firstMatch(text);
      expect(mrpMatch, isNotNull);
      expect(mrpMatch!.group(1), equals('89.00'));
      
      final uspMatch = kUspValueRegex.firstMatch(text);
      expect(uspMatch, isNotNull);
      expect(uspMatch!.group(1), equals('0.36'));
      expect(uspMatch.group(3), equals('gram'));
    });

    test('extractor keeps MRP independent when USP is on the same line', () {
      final result = DetailExtractor().extract([
        const OcrBlock(
          text: 'Rs.89.00 Rs.0.36 per gram',
          boundingBox: OcrRect(left: 0, top: 0, width: 300, height: 20),
          confidence: 1,
          originalIndex: 0,
        ),
      ], 300);

      expect(result.firstWhere((r) => r.fieldId == 'mrp').normalisedValue, '₹89.00');
      expect(result.firstWhere((r) => r.fieldId == 'usp').normalisedValue,
          contains('0.36 per gram'));
    });

    test('rejects date-like OCR garbage instead of storing raw text', () {
      final result = DetailExtractor().extract([
        const OcrBlock(
          text: 'Mfg Date: 99/99/9999',
          boundingBox: OcrRect(left: 0, top: 0, width: 200, height: 20),
          confidence: 1,
          originalIndex: 0,
        ),
      ], 200);

      final mfg = result.firstWhere((r) => r.fieldId == 'mfg_date');
      expect(mfg.status, FieldStatus.notFound);
      expect(mfg.normalisedValue, isNull);
      expect(mfg.matchedText, isNull);
    });

    test('extracts lot values from common OCR anchor variants', () {
      final result = DetailExtractor().extract([
        const OcrBlock(
          text: 'LOT# AB-12_7 14:30',
          boundingBox: OcrRect(left: 0, top: 0, width: 220, height: 20),
          confidence: 1,
          originalIndex: 0,
        ),
      ], 220);

      final lot = result.firstWhere((r) => r.fieldId == 'lot_number');
      expect(lot.status, FieldStatus.found);
      expect(lot.normalisedValue, 'AB-12_7 14:30');
    });

    test('builds verified export JSON with OCR boxes and corrections', () {
      final block = const OcrBlock(
        text: 'Lot No: AB-12',
        boundingBox: OcrRect(left: 10, top: 20, width: 80, height: 18),
        confidence: 0.88,
        originalIndex: 4,
      );
      final report = ComplianceReport(
        scanId: 'scan-1',
        timestamp: DateTime(2026, 1, 1),
        stages: [
          StageCapture(
            stage: ScanStage.detail,
            ocrBlocks: [block],
          ),
        ],
        fieldResults: const [
          FieldResult(
            fieldId: 'lot_number',
            fieldLabel: 'Lot Number',
            status: FieldStatus.found,
            matchedText: 'AB-12',
            normalisedValue: 'AB-12',
            sourceBlockIndices: [4],
            stage: 'detail',
          ),
        ],
      );

      final json = TrainingRecordBuilder().buildJson(
        report,
        verificationStatus: 'verified',
        corrections: const [
          {
            'field': 'lot_number',
            'original_value': 'AB-I2',
            'corrected_value': 'AB-12',
          },
        ],
      );

      final field = (json['extracted_fields'] as Map<String, dynamic>)['lot_number']
          as Map<String, dynamic>;
      expect(field['bounding_box'], [10.0, 20.0, 80.0, 18.0]);
      expect(field['match_type'], 'co_located');
      expect(json['raw_ocr_blocks'], hasLength(1));
      expect(json['corrections_made'], hasLength(1));
    });
  });
}

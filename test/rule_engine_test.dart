import 'package:flutter_test/flutter_test.dart';
import 'package:metriscan/core/models/ocr_block.dart';
import 'package:metriscan/core/models/field_result.dart';
import 'package:metriscan/core/models/scan_stage.dart';
import 'package:metriscan/core/models/stage_capture.dart';
import 'package:metriscan/core/services/field_extractors/front_extractor.dart';
import 'package:metriscan/core/services/field_extractors/back_extractor.dart';
import 'package:metriscan/core/services/field_extractors/detail_extractor.dart';
import 'package:metriscan/core/services/rule_engine.dart';

void main() {
  group('FrontExtractor Tests', () {
    final extractor = FrontExtractor();

    test('extracts product name and company name by font size & position', () {
      final blocks = [
        const OcrBlock(
          text: 'TATA TEA GOLD',
          boundingBox: OcrRect(left: 50, top: 40, width: 400, height: 60),
          confidence: 0.95,
          estimatedFontSizePx: 60,
          originalIndex: 0,
        ),
        const OcrBlock(
          text: 'Tata Consumer Products',
          boundingBox: OcrRect(left: 60, top: 110, width: 250, height: 25),
          confidence: 0.90,
          estimatedFontSizePx: 25,
          originalIndex: 1,
        ),
      ];

      final results = extractor.extract(blocks, 500);
      final prodName = results.firstWhere((r) => r.fieldId == 'product_name');
      final compName = results.firstWhere((r) => r.fieldId == 'company_name');

      expect(prodName.status, FieldStatus.found);
      expect(prodName.matchedText, contains('TATA TEA GOLD'));

      expect(compName.status, FieldStatus.found);
      expect(compName.matchedText, contains('Tata Consumer Products'));
    });
  });

  group('BackExtractor Tests', () {
    final extractor = BackExtractor();

    test('extracts manufacturer, fssai, consumer care and ingredients', () {
      final blocks = [
        const OcrBlock(
          text: 'Ingredients: Black Tea, Natural Flavours',
          boundingBox: OcrRect(left: 20, top: 50, width: 300, height: 20),
          confidence: 0.92,
          originalIndex: 0,
        ),
        const OcrBlock(
          text: 'Manufactured by: ABC Beverages Pvt Ltd, Mumbai 400001',
          boundingBox: OcrRect(left: 20, top: 80, width: 400, height: 20),
          confidence: 0.94,
          originalIndex: 1,
        ),
        const OcrBlock(
          text: 'fssai Lic. No. 10014022002758',
          boundingBox: OcrRect(left: 20, top: 110, width: 250, height: 20),
          confidence: 0.98,
          originalIndex: 2,
        ),
        const OcrBlock(
          text: 'Customer Care: 1800-223-1223, care@tataconsumer.com',
          boundingBox: OcrRect(left: 20, top: 140, width: 350, height: 20),
          confidence: 0.89,
          originalIndex: 3,
        ),
      ];

      final results = extractor.extract(blocks);

      final mfr = results.firstWhere((r) => r.fieldId == 'manufacturer');
      final fssai = results.firstWhere((r) => r.fieldId == 'fssai_license');
      final care = results.firstWhere((r) => r.fieldId == 'consumer_care');
      final ing = results.firstWhere((r) => r.fieldId == 'ingredients');

      expect(mfr.status, FieldStatus.found);
      expect(mfr.matchedText, contains('ABC Beverages'));

      expect(fssai.status, FieldStatus.found);
      expect(fssai.normalisedValue, '10014022002758');

      expect(care.status, FieldStatus.found);
      expect(care.matchedText, contains('1800-223-1223'));

      expect(ing.status, FieldStatus.found);
      expect(ing.matchedText, contains('Black Tea'));
    });
  });

  group('DetailExtractor Tests', () {
    final extractor = DetailExtractor();

    test('extracts MRP, USP, Net Qty, Lot and dates properly', () {
      final blocks = [
        const OcrBlock(
          text: 'MRP: Rs. 240.00 (Incl. of all taxes)',
          boundingBox: OcrRect(left: 30, top: 40, width: 300, height: 25),
          confidence: 0.97,
          originalIndex: 0,
        ),
        const OcrBlock(
          text: 'Rs. 0.48 per g',
          boundingBox: OcrRect(left: 30, top: 70, width: 180, height: 20),
          confidence: 0.91,
          originalIndex: 1,
        ),
        const OcrBlock(
          text: 'Net Weight: 500 g',
          boundingBox: OcrRect(left: 30, top: 100, width: 150, height: 20),
          confidence: 0.95,
          originalIndex: 2,
        ),
        const OcrBlock(
          text: 'Lot No: L24A091',
          boundingBox: OcrRect(left: 30, top: 130, width: 160, height: 20),
          confidence: 0.93,
          originalIndex: 3,
        ),
        const OcrBlock(
          text: 'Mfg Date: 02/2026',
          boundingBox: OcrRect(left: 30, top: 160, width: 150, height: 20),
          confidence: 0.96,
          originalIndex: 4,
        ),
        const OcrBlock(
          text: 'Use By: 02/2027',
          boundingBox: OcrRect(left: 30, top: 190, width: 150, height: 20),
          confidence: 0.94,
          originalIndex: 5,
        ),
      ];

      final results = extractor.extract(blocks, 400);

      final mrp = results.firstWhere((r) => r.fieldId == 'mrp');
      final usp = results.firstWhere((r) => r.fieldId == 'usp');
      final netQty = results.firstWhere((r) => r.fieldId == 'net_quantity');
      final lot = results.firstWhere((r) => r.fieldId == 'lot_number');
      final mfg = results.firstWhere((r) => r.fieldId == 'mfg_date');
      final exp = results.firstWhere((r) => r.fieldId == 'expiry_date');

      expect(mrp.status, FieldStatus.found);
      expect(mrp.normalisedValue, contains('240.00'));

      expect(usp.status, FieldStatus.found);
      expect(usp.matchedText, contains('0.48 per g'));

      expect(netQty.status, FieldStatus.found);
      expect(netQty.normalisedValue, '500 G');

      expect(lot.status, FieldStatus.found);
      expect(lot.normalisedValue, 'L24A091');

      expect(mfg.status, FieldStatus.found);
      expect(mfg.normalisedValue, '2026-02');

      expect(exp.status, FieldStatus.found);
      expect(exp.normalisedValue, '2027-02');
      expect(mfg.normalisedValue != exp.normalisedValue, isTrue);
    });
  });

  group('RuleEngine End-to-End Test', () {
    test('assembles compliance report from 3 stages and computes score', () async {
      final engine = RuleEngine();
      final stages = [
        const StageCapture(
          stage: ScanStage.front,
          ocrBlocks: [
            OcrBlock(
              text: 'GOOD LIFE WHOLE WHEAT ATTA',
              boundingBox: OcrRect(left: 20, top: 30, width: 350, height: 50),
              estimatedFontSizePx: 50,
              confidence: 0.99,
              originalIndex: 0,
            ),
          ],
        ),
        const StageCapture(
          stage: ScanStage.back,
          ocrBlocks: [
            OcrBlock(
              text: 'Manufactured by: Reliance Retail Ltd, Navi Mumbai',
              boundingBox: OcrRect(left: 10, top: 40, width: 400, height: 20),
              confidence: 0.95,
              originalIndex: 1,
            ),
            OcrBlock(
              text: 'Customer Care: 1800-891-0001',
              boundingBox: OcrRect(left: 10, top: 70, width: 250, height: 20),
              confidence: 0.90,
              originalIndex: 2,
            ),
          ],
        ),
        const StageCapture(
          stage: ScanStage.detail,
          ocrBlocks: [
            OcrBlock(
              text: 'MRP: Rs. 275.00',
              boundingBox: OcrRect(left: 10, top: 30, width: 200, height: 25),
              confidence: 0.98,
              originalIndex: 3,
            ),
            OcrBlock(
              text: 'Net Qty: 5 kg',
              boundingBox: OcrRect(left: 10, top: 60, width: 150, height: 20),
              confidence: 0.97,
              originalIndex: 4,
            ),
            OcrBlock(
              text: 'Lot No: GL9901',
              boundingBox: OcrRect(left: 10, top: 90, width: 150, height: 20),
              confidence: 0.92,
              originalIndex: 5,
            ),
            OcrBlock(
              text: 'Mfg: 01/2026',
              boundingBox: OcrRect(left: 10, top: 120, width: 150, height: 20),
              confidence: 0.95,
              originalIndex: 6,
            ),
          ],
        ),
      ];

      final report = await engine.analyse(scanId: 'test-scan-001', stages: stages);

      expect(report.mandatoryFound, 7); // All 7 mandatory fields present
      expect(report.overallScore, 1.0);
      expect(report.statusLabel, 'Compliant');
    });
  });
}

import '../constants/rule_definitions.dart';
import '../models/compliance_report.dart';
import '../models/field_result.dart';
import '../models/ocr_block.dart';
import '../models/stage_capture.dart';

/// Assembles a [ComplianceReport] from field results and font-size data.
class ReportBuilder {
  ComplianceReport build({
    required String scanId,
    required List<StageCapture> stages,
    required List<FieldResult> fieldResults,
    required bool fontSizePass,
    required List<OcrBlock> smallTextBlocks,
  }) {
    // Compute compliance score against mandatory fields only
    const mandatory = kMandatoryFields;
    final found = mandatory.where((id) {
      final r = fieldResults.where((f) => f.fieldId == id).firstOrNull;
      return r != null && r.isPass;
    }).length;

    final score = mandatory.isEmpty ? 0.0 : found / mandatory.length;

    // Collect plain-language violations
    final violations = <String>[];
    for (final id in mandatory) {
      final r = fieldResults.where((f) => f.fieldId == id).firstOrNull;
      if (r == null || r.isFail) {
        violations.add(
          r?.violation ??
              '${_labelFor(id)} is missing — mandatory under Rule 6, Legal Metrology (Packaged Commodities) Rules, 2011.',
        );
      } else if (r.isPartial && r.violation != null) {
        violations.add(r.violation!);
      }
    }

    // Conditional field violations
    for (final id in kConditionalFields) {
      final r = fieldResults.where((f) => f.fieldId == id).firstOrNull;
      if (r != null && r.isFail && r.violation != null) {
        violations.add(r.violation!);
      }
    }

    if (!fontSizePass) {
      violations.add(
        'Some text blocks appear below the minimum legibility threshold '
        '(estimated — not a certified measurement).',
      );
    }

    return ComplianceReport(
      scanId: scanId,
      timestamp: DateTime.now(),
      stages: stages,
      fieldResults: fieldResults,
      overallScore: score,
      mandatoryFound: found,
      mandatoryTotal: mandatory.length,
      violations: violations,
      fontSizePass: fontSizePass,
      smallTextBlocks: smallTextBlocks,
    );
  }

  String _labelFor(String id) {
    const labels = {
      'product_name': 'Product Name',
      'manufacturer': 'Manufacturer Name & Address',
      'net_quantity': 'Net Quantity',
      'mrp': 'MRP',
      'mfg_date': 'Mfg / Packed Date',
      'consumer_care': 'Consumer Care Details',
      'lot_number': 'Lot Number',
    };
    return labels[id] ?? id;
  }
}

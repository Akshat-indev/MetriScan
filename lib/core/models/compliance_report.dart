import 'field_result.dart';
import 'ocr_block.dart';
import 'stage_capture.dart';

/// The assembled compliance report across all 3 scan stages.
class ComplianceReport {
  final String scanId;
  final DateTime timestamp;
  final List<StageCapture> stages;
  final List<FieldResult> fieldResults;
  final double overallScore;
  final int mandatoryFound;
  final int mandatoryTotal;
  final List<String> violations;
  final bool fontSizePass;
  final List<OcrBlock> smallTextBlocks;
  final String? trainingJsonPath;

  const ComplianceReport({
    required this.scanId,
    required this.timestamp,
    this.stages = const [],
    this.fieldResults = const [],
    this.overallScore = 0.0,
    this.mandatoryFound = 0,
    this.mandatoryTotal = 0,
    this.violations = const [],
    this.fontSizePass = true,
    this.smallTextBlocks = const [],
    this.trainingJsonPath,
  });

  String get statusLabel {
    if (overallScore >= 0.9) return 'Compliant';
    if (overallScore >= 0.6) return 'Partial';
    return 'Non-Compliant';
  }

  String? get thumbnailPath {
    try {
      return stages
          .firstWhere((s) => s.stage.name == 'front')
          .imagePaths
          .first;
    } catch (_) {
      return null;
    }
  }

  ComplianceReport copyWith({
    String? scanId,
    DateTime? timestamp,
    List<StageCapture>? stages,
    List<FieldResult>? fieldResults,
    double? overallScore,
    int? mandatoryFound,
    int? mandatoryTotal,
    List<String>? violations,
    bool? fontSizePass,
    List<OcrBlock>? smallTextBlocks,
    String? trainingJsonPath,
  }) => ComplianceReport(
        scanId: scanId ?? this.scanId,
        timestamp: timestamp ?? this.timestamp,
        stages: stages ?? this.stages,
        fieldResults: fieldResults ?? this.fieldResults,
        overallScore: overallScore ?? this.overallScore,
        mandatoryFound: mandatoryFound ?? this.mandatoryFound,
        mandatoryTotal: mandatoryTotal ?? this.mandatoryTotal,
        violations: violations ?? this.violations,
        fontSizePass: fontSizePass ?? this.fontSizePass,
        smallTextBlocks: smallTextBlocks ?? this.smallTextBlocks,
        trainingJsonPath: trainingJsonPath ?? this.trainingJsonPath,
      );

  Map<String, dynamic> toJson() => {
        'scan_id': scanId,
        'timestamp': timestamp.toIso8601String(),
        'stages': stages.map((s) => s.toJson()).toList(),
        'field_results': fieldResults.map((r) => r.toJson()).toList(),
        'overall_score': overallScore,
        'mandatory_found': mandatoryFound,
        'mandatory_total': mandatoryTotal,
        'violations': violations,
        'font_size_pass': fontSizePass,
        'small_text_blocks': smallTextBlocks.map((b) => b.toJson()).toList(),
        'training_json_path': trainingJsonPath,
      };

  factory ComplianceReport.fromJson(Map<String, dynamic> json) =>
      ComplianceReport(
        scanId: json['scan_id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        stages: (json['stages'] as List<dynamic>?)
                ?.map((e) => StageCapture.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        fieldResults: (json['field_results'] as List<dynamic>?)
                ?.map((e) => FieldResult.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        overallScore: (json['overall_score'] as num? ?? 0).toDouble(),
        mandatoryFound: json['mandatory_found'] as int? ?? 0,
        mandatoryTotal: json['mandatory_total'] as int? ?? 0,
        violations: (json['violations'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        fontSizePass: json['font_size_pass'] as bool? ?? true,
        smallTextBlocks: (json['small_text_blocks'] as List<dynamic>?)
                ?.map((e) => OcrBlock.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        trainingJsonPath: json['training_json_path'] as String?,
      );
}

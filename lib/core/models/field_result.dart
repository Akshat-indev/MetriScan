enum FieldStatus { found, notFound, partial, conditional }

enum MatchType {
  coLocated,
  crossImageInferred,
  formatOnly,
}

extension FieldStatusX on FieldStatus {
  bool get isPass => this == FieldStatus.found || this == FieldStatus.conditional;
  bool get isFail => this == FieldStatus.notFound;
  bool get isPartial => this == FieldStatus.partial;
}

/// Result of attempting to extract one mandatory field from the OCR output.
class FieldResult {
  final String fieldId;
  final String fieldLabel;
  final FieldStatus status;
  final String? matchedText;
  final String? normalisedValue;
  final double ocrConfidence;
  final double matchConfidence;
  final List<int> sourceBlockIndices;
  final String? violation;
  final String stage;
  final String? matchReason;
  final double? fontSizePx;
  final MatchType matchType;

  const FieldResult({
    required this.fieldId,
    required this.fieldLabel,
    required this.status,
    this.matchedText,
    this.normalisedValue,
    this.ocrConfidence = 0.0,
    this.matchConfidence = 0.0,
    this.sourceBlockIndices = const [],
    this.violation,
    this.stage = 'unknown',
    this.matchReason,
    this.fontSizePx,
    this.matchType = MatchType.coLocated,
  });

  bool get isPass => status.isPass;
  bool get isFail => status.isFail;
  bool get isPartial => status.isPartial;

  FieldResult copyWith({
    String? fieldId,
    String? fieldLabel,
    FieldStatus? status,
    String? matchedText,
    String? normalisedValue,
    double? ocrConfidence,
    double? matchConfidence,
    List<int>? sourceBlockIndices,
    String? violation,
    String? stage,
    String? matchReason,
  }) => FieldResult(
        fieldId: fieldId ?? this.fieldId,
        fieldLabel: fieldLabel ?? this.fieldLabel,
        status: status ?? this.status,
        matchedText: matchedText ?? this.matchedText,
        normalisedValue: normalisedValue ?? this.normalisedValue,
        ocrConfidence: ocrConfidence ?? this.ocrConfidence,
        matchConfidence: matchConfidence ?? this.matchConfidence,
        sourceBlockIndices: sourceBlockIndices ?? this.sourceBlockIndices,
        violation: violation ?? this.violation,
        stage: stage ?? this.stage,
        matchReason: matchReason ?? this.matchReason,
      );

  Map<String, dynamic> toJson() => {
        'field_id': fieldId,
        'field_label': fieldLabel,
        'status': status.name,
        'matched_text': matchedText,
        'normalised_value': normalisedValue,
        'ocr_confidence': ocrConfidence,
        'match_confidence': matchConfidence,
        'source_block_indices': sourceBlockIndices,
        'violation': violation,
        'stage': stage,
        'match_reason': matchReason,
      };

  factory FieldResult.fromJson(Map<String, dynamic> json) => FieldResult(
        fieldId: json['field_id'] as String,
        fieldLabel: json['field_label'] as String,
        status: FieldStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => FieldStatus.notFound,
        ),
        matchedText: json['matched_text'] as String?,
        normalisedValue: json['normalised_value'] as String?,
        ocrConfidence: (json['ocr_confidence'] as num? ?? json['confidence'] as num? ?? 0).toDouble(),
        matchConfidence: (json['match_confidence'] as num? ?? json['confidence'] as num? ?? 0).toDouble(),
        sourceBlockIndices: (json['source_block_indices'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            [],
        violation: json['violation'] as String?,
        stage: json['stage'] as String? ?? 'unknown',
        matchReason: json['match_reason'] as String?,
      );
}

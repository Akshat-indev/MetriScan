import 'dart:ui' show Rect;

/// A single recognized text region returned by the OCR engine.
/// Bounding box coordinates are in the image's pixel space.
class OcrBlock {
  final String text;
  final OcrRect boundingBox;
  final double confidence;
  final double estimatedFontSizePx;
  final String estimatedFontWeight;
  final double angleDeg;
  final String stage;
  final int originalIndex;

  const OcrBlock({
    required this.text,
    required this.boundingBox,
    this.confidence = 1.0,
    this.estimatedFontSizePx = 0.0,
    this.estimatedFontWeight = 'unknown',
    this.angleDeg = 0.0,
    this.stage = 'unknown',
    this.originalIndex = -1,
  });

  OcrBlock copyWith({
    String? text,
    OcrRect? boundingBox,
    double? confidence,
    double? estimatedFontSizePx,
    String? estimatedFontWeight,
    double? angleDeg,
    String? stage,
    int? originalIndex,
  }) => OcrBlock(
        text: text ?? this.text,
        boundingBox: boundingBox ?? this.boundingBox,
        confidence: confidence ?? this.confidence,
        estimatedFontSizePx: estimatedFontSizePx ?? this.estimatedFontSizePx,
        estimatedFontWeight: estimatedFontWeight ?? this.estimatedFontWeight,
        angleDeg: angleDeg ?? this.angleDeg,
        stage: stage ?? this.stage,
        originalIndex: originalIndex ?? this.originalIndex,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'bounding_box': boundingBox.toJson(),
        'confidence': confidence,
        'estimated_font_size_px': estimatedFontSizePx,
        'estimated_font_weight': estimatedFontWeight,
        'angle_deg': angleDeg,
        'stage': stage,
        'original_index': originalIndex,
      };

  factory OcrBlock.fromJson(Map<String, dynamic> json) => OcrBlock(
        text: json['text'] as String,
        boundingBox: OcrRect.fromJson(json['bounding_box'] as Map<String, dynamic>),
        confidence: (json['confidence'] as num).toDouble(),
        estimatedFontSizePx: (json['estimated_font_size_px'] as num).toDouble(),
        estimatedFontWeight: json['estimated_font_weight'] as String? ?? 'unknown',
        angleDeg: (json['angle_deg'] as num? ?? 0).toDouble(),
        stage: json['stage'] as String? ?? 'unknown',
        originalIndex: json['original_index'] as int? ?? -1,
      );
}

/// JSON-serialisable rectangle (dart:ui Rect is not serialisable).
class OcrRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const OcrRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  Rect toRect() => Rect.fromLTWH(left, top, width, height);

  factory OcrRect.fromRect(Rect r) =>
      OcrRect(left: r.left, top: r.top, width: r.width, height: r.height);

  Map<String, dynamic> toJson() =>
      {'x': left, 'y': top, 'w': width, 'h': height};

  factory OcrRect.fromJson(Map<String, dynamic> json) => OcrRect(
        left: (json['x'] as num).toDouble(),
        top: (json['y'] as num).toDouble(),
        width: (json['w'] as num).toDouble(),
        height: (json['h'] as num).toDouble(),
      );
}

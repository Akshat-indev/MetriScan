import 'ocr_block.dart';
import 'scan_stage.dart';

/// All data collected during one capture stage (images + OCR results).
class StageCapture {
  final ScanStage stage;
  final List<String> imagePaths;
  final List<OcrBlock> ocrBlocks;
  final bool hasClipping;
  final String allRawText;
  final int imageWidth;
  final int imageHeight;

  const StageCapture({
    required this.stage,
    this.imagePaths = const [],
    this.ocrBlocks = const [],
    this.hasClipping = false,
    this.allRawText = '',
    this.imageWidth = 0,
    this.imageHeight = 0,
  });

  StageCapture copyWith({
    ScanStage? stage,
    List<String>? imagePaths,
    List<OcrBlock>? ocrBlocks,
    bool? hasClipping,
    String? allRawText,
    int? imageWidth,
    int? imageHeight,
  }) =>
      StageCapture(
        stage: stage ?? this.stage,
        imagePaths: imagePaths ?? this.imagePaths,
        ocrBlocks: ocrBlocks ?? this.ocrBlocks,
        hasClipping: hasClipping ?? this.hasClipping,
        allRawText: allRawText ?? this.allRawText,
        imageWidth: imageWidth ?? this.imageWidth,
        imageHeight: imageHeight ?? this.imageHeight,
      );

  Map<String, dynamic> toJson() => {
        'stage': stage.name,
        'image_paths': imagePaths,
        'has_clipping': hasClipping,
        'all_raw_text': allRawText,
        'image_width': imageWidth,
        'image_height': imageHeight,
        'ocr_blocks': ocrBlocks.map((b) => b.toJson()).toList(),
      };

  factory StageCapture.fromJson(Map<String, dynamic> json) => StageCapture(
        stage: ScanStage.values.firstWhere(
          (s) => s.name == json['stage'],
          orElse: () => ScanStage.front,
        ),
        imagePaths: (json['image_paths'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        ocrBlocks: (json['ocr_blocks'] as List<dynamic>?)
                ?.map((e) => OcrBlock.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        hasClipping: json['has_clipping'] as bool? ?? false,
        allRawText: json['all_raw_text'] as String? ?? '',
        imageWidth: json['image_width'] as int? ?? 0,
        imageHeight: json['image_height'] as int? ?? 0,
      );
}

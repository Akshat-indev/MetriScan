import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/compliance_report.dart';
import '../../core/models/ocr_block.dart';
import '../../core/models/scan_stage.dart';
import '../../core/models/stage_capture.dart';
import '../../core/services/rule_engine.dart';
import '../../core/services/training_record_builder.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final _ruleEngine = RuleEngine();
final _trainingBuilder = TrainingRecordBuilder();

final ocrReviewProvider =
    FutureProvider.family<ComplianceReport, List<StageCapture>>(
  (ref, captures) async {
    final scanId = const Uuid().v4();
    return _ruleEngine.analyse(scanId: scanId, stages: captures);
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class OcrReviewScreen extends ConsumerWidget {
  final List<StageCapture> captures;

  const OcrReviewScreen({super.key, required this.captures});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(ocrReviewProvider(captures));

    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Review'),
        actions: [
          reportAsync
                  .whenData((report) => TextButton(
                        onPressed: () => _runCompliance(context, ref, report),
                        child: const Text('Check ›'),
                      ))
                  .value ??
              const SizedBox.shrink(),
        ],
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (report) => _OcrReviewContent(
          captures: captures,
          report: report,
          onRunCompliance: () => _runCompliance(context, ref, report),
        ),
      ),
    );
  }

  Future<void> _runCompliance(
    BuildContext context,
    WidgetRef ref,
    ComplianceReport report,
  ) async {
    try {
      // Save training JSON
      final outputPath = await _trainingBuilder.buildAndSave(report);

      // Manually copy the report since copyWith doesn't exist
      final finalReport = ComplianceReport(
        scanId: report.scanId,
        timestamp: report.timestamp,
        stages: report.stages,
        fieldResults: report.fieldResults,
        overallScore: report.overallScore,
        mandatoryFound: report.mandatoryFound,
        mandatoryTotal: report.mandatoryTotal,
        violations: report.violations,
        fontSizePass: report.fontSizePass,
        smallTextBlocks: report.smallTextBlocks,
        trainingJsonPath: outputPath,
      );

      if (context.mounted) {
        context.push('/report', extra: finalReport);
      }
    } catch (e, st) {
      debugPrint('Error running compliance check: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _OcrReviewContent extends StatefulWidget {
  final List<StageCapture> captures;
  final ComplianceReport report;
  final VoidCallback onRunCompliance;

  const _OcrReviewContent({
    required this.captures,
    required this.report,
    required this.onRunCompliance,
  });

  @override
  State<_OcrReviewContent> createState() => _OcrReviewContentState();
}

class _OcrReviewContentState extends State<_OcrReviewContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.captures.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Stage tabs
        TabBar(
          controller: _tabController,
          tabs: widget.captures
              .map((c) => Tab(text: c.stage.displayName))
              .toList(),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: widget.captures.map((capture) {
              return _StageReviewTab(
                capture: capture,
                reportBlocks: widget.report.stages
                    .firstWhere((s) => s.stage == capture.stage,
                        orElse: () => capture)
                    .ocrBlocks,
              );
            }).toList(),
          ),
        ),

        // Bottom action
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: widget.onRunCompliance,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Run Compliance Check',
                    style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Per-stage tab: image with OCR bounding box overlay + scrollable raw text.
class _StageReviewTab extends StatelessWidget {
  final StageCapture capture;
  final List<OcrBlock> reportBlocks;

  const _StageReviewTab({required this.capture, required this.reportBlocks});

  @override
  Widget build(BuildContext context) {
    final imagePath = capture.imagePaths.firstOrNull;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image with OCR overlay
          if (imagePath != null)
            Stack(
              children: [
                Image.file(
                  File(imagePath),
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                ),
                // OCR bounding box overlay
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomPaint(
                        painter: _OcrOverlayPainter(
                          blocks: reportBlocks,
                          renderSize: constraints.biggest,
                          imageWidth: capture.imageWidth,
                          imageHeight: capture.imageHeight,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

          // Raw OCR text
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Extracted Text (${reportBlocks.length} blocks)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ...reportBlocks.map((block) => _BlockTile(block: block)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  final OcrBlock block;

  const _BlockTile({required this.block});

  @override
  Widget build(BuildContext context) {
    final conf = block.confidence;
    final color = conf >= 0.8
        ? Colors.green
        : conf >= 0.5
            ? Colors.orange
            : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 20,
            color: color,
            margin: const EdgeInsets.only(right: 8, top: 2),
          ),
          Expanded(
            child: Text(
              block.text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            '${(conf * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

class _OcrOverlayPainter extends CustomPainter {
  final List<OcrBlock> blocks;
  final Size renderSize;
  final int imageWidth;
  final int imageHeight;

  _OcrOverlayPainter({
    required this.blocks,
    required this.renderSize,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth == 0 || imageHeight == 0) return;

    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    for (final block in blocks) {
      final conf = block.confidence;
      final color = conf >= 0.8
          ? Colors.green
          : conf >= 0.5
              ? Colors.orange
              : Colors.red;

      final rect = Rect.fromLTWH(
        block.boundingBox.left * scaleX,
        block.boundingBox.top * scaleY,
        block.boundingBox.width * scaleX,
        block.boundingBox.height * scaleY,
      );

      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withAlpha(40)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withAlpha(180)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_OcrOverlayPainter old) => blocks != old.blocks;
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/compliance_report.dart';
import '../../core/models/field_result.dart';
import '../../core/services/scan_repository.dart';
import '../../core/services/pdf_exporter.dart';
import '../../core/services/training_record_builder.dart';
import '../../core/utils/date_validator.dart';
import '../../correction_memory/correction_memory.dart';
import '../../shared/widgets/field_tile.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ReportScreen extends ConsumerStatefulWidget {
  final ComplianceReport? report;
  final String? scanId; // when opened from history

  const ReportScreen({super.key, this.report}) : scanId = null;
  const ReportScreen.fromHistory({super.key, required String this.scanId})
      : report = null;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ComplianceReport? _report;
  bool _loading = false;
  bool _saved = false;
  bool _verified = false;
  bool _sentToTraining = false;
  Map<String, TextEditingController> _controllers = {};
  Map<String, int> _verifiedCounts = {};
  Map<String, String> _originalValues = {};

  @override
  void initState() {
    super.initState();
    if (widget.report != null) {
      _report = widget.report;
      _originalValues = {
        for (final result in widget.report!.fieldResults)
          result.fieldId: result.normalisedValue ?? result.matchedText ?? '',
      };
    } else {
      _loadFromHistory();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

    void _ensureControllers(ComplianceReport report) {
      if (_controllers.isNotEmpty) return;
      _controllers = {
        for (final result in report.fieldResults)
          result.fieldId: TextEditingController(
            text: result.normalisedValue ?? result.matchedText ?? '',
          ),
      };
    }

    Future<void> _verifyAndSave() async {
      final report = _report;
      if (report == null) return;
      final corrected = report.fieldResults.map((result) {
        var value = _controllers[result.fieldId]!.text.trim();
        if (result.fieldId == 'mfg_date' || result.fieldId == 'expiry_date') {
          value = DateValidator.validatedDate(value) ?? '';
        }
        if (value.isEmpty) {
          return FieldResult(
            fieldId: result.fieldId,
            fieldLabel: result.fieldLabel,
            status: FieldStatus.notFound,
            violation: result.violation,
            stage: result.stage,
          );
        }
        return FieldResult(
          fieldId: result.fieldId,
          fieldLabel: result.fieldLabel,
          status: FieldStatus.found,
          matchedText: value,
          normalisedValue: value,
          ocrConfidence: result.ocrConfidence,
          matchConfidence: 1,
          sourceBlockIndices: result.sourceBlockIndices,
          stage: result.stage,
          matchReason: 'User verified/corrected',
          matchType: result.matchType,
        );
      }).toList();
      final corrections = <Map<String, dynamic>>[];
      for (final result in corrected) {
        final original = _originalValues[result.fieldId] ?? '';
        final correctedValue = result.normalisedValue ?? '';
        if (original != correctedValue) {
          corrections.add({
            'field': result.fieldId,
            'original_value': original.isEmpty ? null : original,
            'corrected_value': correctedValue.isEmpty ? null : correctedValue,
          });
        }
      }
      final verifiedReport = report.copyWith(fieldResults: corrected);
      final correctedFields = <String, String?>{
        for (final result in corrected)
          result.fieldId: result.normalisedValue,
      };
      final rawOcrSnippets = <String, String>{
        for (final result in report.fieldResults)
          if (result.sourceBlockIndices.isNotEmpty)
            result.fieldId: _rawSnippetFor(report, result),
      };
      // TEMPORARY: correction-memory stand-in, remove when trained model replaces this (see /correction_memory/README.md)
      await CorrectionMemory().applyKnownProduct(
        correctedFields,
        verifiedCorrections: correctedFields,
        rawOcrSnippets: rawOcrSnippets,
      );
      final outputPath = await TrainingRecordBuilder().buildAndSave(
        verifiedReport,
        verificationStatus: 'verified',
        corrections: corrections,
      );
      if (mounted) {
        setState(() {
          _report = verifiedReport.copyWith(trainingJsonPath: outputPath);
          _verified = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Corrections saved as verified.')),
        );
      }
    }

    String _rawSnippetFor(ComplianceReport report, FieldResult result) {
      final indices = result.sourceBlockIndices.toSet();
      final blockText = report.stages
          .expand((stage) => stage.ocrBlocks)
          .where((block) => indices.contains(block.originalIndex))
          .map((block) => block.text)
          .join(' ')
          .trim();
      return blockText.isNotEmpty ? blockText : (result.matchedText ?? '').trim();
    }

    Future<void> _sendToTraining() async {
      if (!_verified || _report == null) return;
      await TrainingRecordBuilder().appendVerifiedRecord(
        _report!,
        corrections: _correctionsForCurrentReport(),
      );
      final counts = await TrainingRecordBuilder().verifiedCounts();
      if (mounted) {
        setState(() {
          _sentToTraining = true;
          _verifiedCounts = counts;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verified record added to training set.')),
        );
      }
    }

  List<Map<String, dynamic>> _correctionsForCurrentReport() {
    if (_report == null) return const [];
    return [
      for (final result in _report!.fieldResults)
        if ((_originalValues[result.fieldId] ?? '') !=
            (result.normalisedValue ?? ''))
          {
            'field': result.fieldId,
            'original_value': _originalValues[result.fieldId],
            'corrected_value': result.normalisedValue,
          },
    ];
  }

  Future<void> _loadFromHistory() async {
    setState(() => _loading = true);
    _report = await ScanRepository().getReportById(widget.scanId!);
    if (_report != null) {
      _originalValues = {
        for (final result in _report!.fieldResults)
          result.fieldId: result.normalisedValue ?? result.matchedText ?? '',
      };
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_report == null || _saved) return;
    await ScanRepository().insertScan(_report!, _report!.trainingJsonPath);
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan saved to history.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_report == null) {
      return const Scaffold(
          body: Center(child: Text('Report not found.')));
    }

    final report = _report!;
    _ensureControllers(report);
    final score = report.overallScore;
    final scoreColor = score >= 0.9
        ? Colors.green
        : score >= 0.6
            ? Colors.orange
            : Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compliance Report'),
        actions: [
          if (!_saved && widget.report != null)
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Score card
            _ScoreCard(report: report, scoreColor: scoreColor),
            const SizedBox(height: 16),

            // Thumbnail
            if (report.thumbnailPath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(report.thumbnailPath!),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),

            // Violations
            if (report.violations.isNotEmpty)
              _ViolationsCard(violations: report.violations),
            const SizedBox(height: 16),

            _VerificationCard(
              report: report,
              controllers: _controllers,
              verified: _verified,
              sentToTraining: _sentToTraining,
              verifiedCounts: _verifiedCounts,
              onVerify: _verifyAndSave,
              onSendToTraining: _sendToTraining,
            ),
            const SizedBox(height: 16),

            // Field results by stage
            const _SectionHeader('Front Label Fields'),
            ...report.fieldResults
                .where((r) => r.stage == 'front')
                .map((r) => FieldTile(result: r)),
            const SizedBox(height: 8),

            const _SectionHeader('Back Label Fields'),
            ...report.fieldResults
                .where((r) => r.stage == 'back')
                .map((r) => FieldTile(result: r)),
            const SizedBox(height: 8),

            const _SectionHeader('Detail Fields'),
            ...report.fieldResults
                .where((r) => r.stage == 'detail')
                .map((r) => FieldTile(result: r)),
            const SizedBox(height: 8),

            // Font size note
            _FontSizeCard(report: report),
            const SizedBox(height: 16),

            // Training JSON note
            if (report.trainingJsonPath != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.data_object, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Training JSON saved:\n${report.trainingJsonPath}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            await PdfExporter().exportAndShare(report);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error exporting PDF: $e')),
              );
            }
          }
        },
        icon: const Icon(Icons.share_outlined),
        label: const Text('Export PDF'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _ScoreCard extends StatelessWidget {
  final ComplianceReport report;
  final Color scoreColor;

  const _ScoreCard({required this.report, required this.scoreColor});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: report.overallScore,
                    strokeWidth: 8,
                    color: scoreColor,
                    backgroundColor: scoreColor.withAlpha(40),
                  ),
                  Center(
                    child: Text(
                      '${(report.overallScore * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: scoreColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.statusLabel,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${report.mandatoryFound} of ${report.mandatoryTotal} '
                    'mandatory fields detected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    report.timestamp.toLocal().toString().substring(0, 16),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViolationsCard extends StatelessWidget {
  final List<String> violations;

  const _ViolationsCard({required this.violations});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Text(
                  'Violations (${violations.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...violations.map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Colors.red)),
                    Expanded(
                      child: Text(v,
                          style: TextStyle(
                              fontSize: 13, color: Colors.red.shade800)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontSizeCard extends StatelessWidget {
  final ComplianceReport report;

  const _FontSizeCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  report.fontSizePass ? Icons.check_circle : Icons.warning,
                  color: report.fontSizePass ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                const Text('Font Legibility (Estimate)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              report.fontSizePass
                  ? 'All detected text meets the minimum estimated size threshold.'
                  : '${report.smallTextBlocks.length} text block(s) appear below minimum threshold.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '⚠ This is a pixel-ratio estimate, not a certified legal measurement.',
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  final ComplianceReport report;
  final Map<String, TextEditingController> controllers;
  final bool verified;
  final bool sentToTraining;
  final Map<String, int> verifiedCounts;
  final VoidCallback onVerify;
  final VoidCallback onSendToTraining;

  const _VerificationCard({
    required this.report,
    required this.controllers,
    required this.verified,
    required this.sentToTraining,
    required this.verifiedCounts,
    required this.onVerify,
    required this.onSendToTraining,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Confirm / Correct Extraction',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Review values, then save the corrected record as verified.'),
            const SizedBox(height: 8),
            ...report.fieldResults.map(
              (result) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: controllers[result.fieldId],
                  decoration: InputDecoration(
                    labelText: result.fieldLabel,
                    hintText: 'Leave blank if not present',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onVerify,
                    icon: const Icon(Icons.verified_outlined),
                    label: Text(verified ? 'Verified' : 'Confirm / Correct'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: verified && !sentToTraining ? onSendToTraining : null,
                    icon: const Icon(Icons.add_to_photos_outlined),
                    label: Text(sentToTraining ? 'Added' : 'Send to training set'),
                  ),
                ),
              ],
            ),
            if (verifiedCounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Verified records by field: ${verifiedCounts.entries.map((e) => '${e.key} ${e.value}').join(' • ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

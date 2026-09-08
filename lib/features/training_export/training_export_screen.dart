import 'package:flutter/material.dart';

import '../../core/services/training_export_service.dart';

class TrainingExportScreen extends StatefulWidget {
  const TrainingExportScreen({super.key});

  @override
  State<TrainingExportScreen> createState() => _TrainingExportScreenState();
}

class _TrainingExportScreenState extends State<TrainingExportScreen> {
  final _service = TrainingExportService();
  int _count = 0;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final count = await _service.verifiedScanCount();
    if (mounted) setState(() { _count = count; _loading = false; });
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final result = await _service.exportVerifiedScans();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${result.scanCount} verified scan(s) exported',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(result.zipPath, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _service.shareExport(result),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share ZIP'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Training Data Export')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          const Icon(Icons.dataset_outlined, size: 42),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$_count verified scans ready for export',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 6),
                                const Text(
                                  'Each export contains original images, OCR overlays, and corrected fields. No model training happens here.',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _count == 0 || _exporting ? null : _export,
                      icon: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.archive_outlined),
                      label: Text(_exporting
                          ? 'Packaging…'
                          : 'Export Training Data'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

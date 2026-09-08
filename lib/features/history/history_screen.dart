import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/scan_record.dart';
import '../../core/services/scan_repository.dart';

final historyProvider = FutureProvider<List<ScanRecord>>((ref) async {
  return ScanRepository().getAllScans();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MetriScan'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Export Training Data',
            onPressed: () => context.push('/training-export'),
            icon: const Icon(Icons.dataset_outlined),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (scans) {
          if (scans.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner,
                      size: 72,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text('No scans yet',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Tap + to scan your first label'),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: scans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final scan = scans[index];
              return _ScanCard(
                scan: scan,
                onTap: () => context.push('/report/${scan.id}'),
                onDelete: () async {
                  await ScanRepository().deleteScan(scan.id);
                  ref.invalidate(historyProvider);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scan'),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('New Scan'),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  final ScanRecord scan;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ScanCard({
    required this.scan,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final score = scan.complianceScore;
    final scoreColor = score >= 0.9
        ? Colors.green
        : score >= 0.6
            ? Colors.orange
            : Colors.red;

    final date = DateTime.fromMillisecondsSinceEpoch(scan.timestampMs);
    final dateStr = '${date.day}/${date.month}/${date.year}  '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';

    return Dismissible(
      key: Key(scan.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              // Thumbnail
              if (scan.frontImagePath != null)
                Image.file(
                  File(scan.frontImagePath!),
                  width: 72,
                  height: 80,
                  fit: BoxFit.cover,
                )
              else
                Container(
                  width: 72,
                  height: 80,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.label_outline),
                ),

              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateStr,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: scoreColor.withAlpha(30),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scoreColor),
                          ),
                          child: Text(
                            '${(score * 100).toStringAsFixed(0)}%  '
                            '${scan.overallPass == 1 ? 'Compliant' : score >= 0.6 ? 'Partial' : 'Non-Compliant'}',
                            style: TextStyle(
                                color: scoreColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right, color: Colors.grey),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

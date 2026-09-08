import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Packages verified records and their source/OCR images for later training.
/// This service only exports data; it does not train or score a model.
class TrainingExportService {
  Future<int> verifiedScanCount() async {
    final records = await _verifiedRecords();
    return records.length;
  }

  Future<TrainingExportResult> exportVerifiedScans() async {
    final records = await _verifiedRecords();
    final docs = await getApplicationDocumentsDirectory();
    final exports = Directory(p.join(docs.path, 'exports'));
    if (!exports.existsSync()) exports.createSync(recursive: true);

    final staging = await getTemporaryDirectory();
    final buildDir = Directory(
        p.join(staging.path, 'metriscan_training_${DateTime.now().millisecondsSinceEpoch}'));
    buildDir.createSync(recursive: true);

    for (final record in records) {
      await _writeScanExport(buildDir, record);
    }

    final zipPath = p.join(
      exports.path,
      'metriscan_training_${DateTime.now().toIso8601String().replaceAll(':', '-')}.zip',
    );
    await ZipFileEncoder().zipDirectory(buildDir, filename: zipPath);
    await File(p.join(exports.path, '.last_export')).writeAsString(
      DateTime.now().toIso8601String(),
      flush: true,
    );
    await buildDir.delete(recursive: true);
    return TrainingExportResult(
      zipPath: zipPath,
      scanCount: records.length,
      exportDirectory: exports.path,
    );
  }

  Future<void> shareExport(TrainingExportResult result) async {
    await Share.shareXFiles(
      [XFile(result.zipPath)],
      text: 'MetriScan verified training data export',
    );
  }

  Future<List<Map<String, dynamic>>> _verifiedRecords() async {
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, 'output', 'training_set.jsonl'));
    if (!file.existsSync()) return [];
    final exports = Directory(p.join(docs.path, 'exports'));
    final marker = File(p.join(exports.path, '.last_export'));
    final lastExport = marker.existsSync()
        ? DateTime.tryParse(await marker.readAsString())
        : null;

    final unique = <String, Map<String, dynamic>>{};
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      final record = jsonDecode(line) as Map<String, dynamic>;
      final timestamp = DateTime.tryParse(record['timestamp'] as String? ?? '');
      if (record['verification_status'] == 'verified' &&
          (lastExport == null ||
              (timestamp != null && timestamp.isAfter(lastExport)))) {
        unique[record['scan_id'] as String] = record;
      }
    }
    return unique.values.toList();
  }

  Future<void> _writeScanExport(
      Directory root, Map<String, dynamic> record) async {
    final scanId = record['scan_id'] as String;
    final scanDir = Directory(p.join(root.path, 'scan_$scanId'));
    scanDir.createSync(recursive: true);

    final stages = (record['stages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    for (final stage in stages) {
      final stageName = stage['stage'] as String? ?? 'unknown';
      final imagePaths = (stage['image_paths'] as List<dynamic>? ?? [])
          .cast<String>();
      final blocks = (stage['ocr_blocks'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      for (var i = 0; i < imagePaths.length; i++) {
        final original = File(imagePaths[i]);
        if (!original.existsSync()) continue;
        final suffix = stageName == 'back' ? '_${i + 1}' : '';
        final originalName = 'original_${stageName}$suffix.jpg';
        await original.copy(p.join(scanDir.path, originalName));
        await _writeAnnotated(
          original,
          blocks,
          record['extracted_fields'] as Map<String, dynamic>? ?? {},
          p.join(scanDir.path, 'ocr_annotated_${stageName}$suffix.jpg'),
        );
      }
    }

    final json = Map<String, dynamic>.from(record);
    await File(p.join(scanDir.path, 'scan_data.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
  }

  Future<void> _writeAnnotated(
    File source,
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> fields,
    String destination,
  ) async {
    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) return;

    final labelsByBox = <String, String>{};
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic> && value['bounding_box'] is List) {
        labelsByBox[_boxKey(value['bounding_box'] as List<dynamic>)] = entry.key;
      }
    }

    for (final block in blocks) {
      final box = block['bounding_box'] as Map<String, dynamic>?;
      if (box == null) continue;
      final x = (box['x'] as num).round();
      final y = (box['y'] as num).round();
      final w = (box['w'] as num).round();
      final h = (box['h'] as num).round();
      final label = labelsByBox[_boxKey([x, y, w, h])] ?? 'unmatched';
      final color = label == 'unmatched'
          ? img.ColorRgb8(130, 130, 130)
          : img.ColorRgb8(30, 180, 70);
      img.drawRect(decoded,
          x1: x,
          y1: y,
          x2: x + w,
          y2: y + h,
          color: color,
          thickness: 3);
      img.drawString(decoded, label,
          font: img.arial14, x: x, y: y > 18 ? y - 18 : y, color: color);
    }
    await File(destination).writeAsBytes(img.encodeJpg(decoded, quality: 90));
  }

  String _boxKey(List<dynamic> values) =>
      values.take(4).map((value) => (value as num).round()).join(',');
}

class TrainingExportResult {
  final String zipPath;
  final String exportDirectory;
  final int scanCount;

  const TrainingExportResult({
    required this.zipPath,
    required this.exportDirectory,
    required this.scanCount,
  });
}

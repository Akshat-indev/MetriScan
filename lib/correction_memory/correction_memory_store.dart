import 'dart:convert';
import 'dart:developer' as developer;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'memory_similarity.dart';

class ProductMemoryMatch {
  final Map<String, String?> correctedFields;
  final double similarity;

  const ProductMemoryMatch({
    required this.correctedFields,
    required this.similarity,
  });
}

class PatternCorrection {
  final String fieldType;
  final String rawSnippet;
  final String correctedPattern;
  final int verifiedCount;

  const PatternCorrection({
    required this.fieldType,
    required this.rawSnippet,
    required this.correctedPattern,
    required this.verifiedCount,
  });
}

/// Owns the correction-memory database, separate from scan history.
class CorrectionMemoryStore {
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final directory = await getApplicationDocumentsDirectory();
    _database = await openDatabase(
      p.join(directory.path, 'correction_memory.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE product_memory (
            fingerprint TEXT PRIMARY KEY,
            corrected_fields TEXT NOT NULL,
            verified_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pattern_corrections (
            field_type TEXT NOT NULL,
            raw_ocr_snippet TEXT NOT NULL,
            corrected_pattern TEXT NOT NULL,
            verified_count INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (field_type, raw_ocr_snippet, corrected_pattern)
          )
        ''');
      },
    );
    return _database!;
  }

  Future<void> saveProductMemory({
    required String fingerprint,
    required Map<String, String?> correctedFields,
  }) async {
    final db = await _db;
    await db.insert(
      'product_memory',
      {
        'fingerprint': fingerprint,
        'corrected_fields': jsonEncode(correctedFields),
        'verified_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    developer.log(
      'product_memory write fingerprint="$fingerprint" '
      'corrected_fields=${jsonEncode(correctedFields)}',
      name: 'metriscan.correction_memory',
    );
  }

  Future<ProductMemoryMatch?> findClosestProduct(String fingerprint) async {
    final db = await _db;
    final rows = await db.query('product_memory');
    ProductMemoryMatch? best;
    for (final row in rows) {
      final score = similarity(fingerprint, row['fingerprint'] as String);
      developer.log(
        'product_memory compare incoming="$fingerprint" '
        'stored="${row['fingerprint']}" similarity=$score',
        name: 'metriscan.correction_memory',
      );
      if (best == null || score > best.similarity) {
        final decoded = jsonDecode(row['corrected_fields'] as String)
            as Map<String, dynamic>;
        best = ProductMemoryMatch(
          correctedFields: decoded.map(
            (key, value) => MapEntry(key, value as String?),
          ),
          similarity: score,
        );
      }
    }
    developer.log(
      'product_memory read rows=${rows.length} '
      'best_similarity=${best?.similarity}',
      name: 'metriscan.correction_memory',
    );
    return best;
  }

  Future<void> savePatternCorrection({
    required String fieldType,
    required String rawSnippet,
    required String correctedPattern,
  }) async {
    final db = await _db;
    final existing = await db.query(
      'pattern_corrections',
      where: 'field_type = ? AND raw_ocr_snippet = ? AND corrected_pattern = ?',
      whereArgs: [fieldType, rawSnippet, correctedPattern],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('pattern_corrections', {
        'field_type': fieldType,
        'raw_ocr_snippet': rawSnippet,
        'corrected_pattern': correctedPattern,
        'verified_count': 1,
      });
      developer.log(
        'pattern_corrections write field="$fieldType" raw="$rawSnippet" '
        'corrected="$correctedPattern" verified_count=1',
        name: 'metriscan.correction_memory',
      );
      return;
    }
    final nextCount = (existing.first['verified_count'] as int) + 1;
    await db.update(
      'pattern_corrections',
      {'verified_count': nextCount},
      where: 'field_type = ? AND raw_ocr_snippet = ? AND corrected_pattern = ?',
      whereArgs: [fieldType, rawSnippet, correctedPattern],
    );
    developer.log(
      'pattern_corrections update field="$fieldType" raw="$rawSnippet" '
      'corrected="$correctedPattern" verified_count=$nextCount',
      name: 'metriscan.correction_memory',
    );
  }

  Future<List<PatternCorrection>> patternCorrections() async {
    final db = await _db;
    final rows = await db.query('pattern_corrections');
    developer.log(
      'pattern_corrections read rows=${rows.length}',
      name: 'metriscan.correction_memory',
    );
    return rows
        .map(
          (row) => PatternCorrection(
            fieldType: row['field_type'] as String,
            rawSnippet: row['raw_ocr_snippet'] as String,
            correctedPattern: row['corrected_pattern'] as String,
            verifiedCount: row['verified_count'] as int,
          ),
        )
        .toList();
  }
}

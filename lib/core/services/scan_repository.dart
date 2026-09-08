import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/compliance_report.dart';
import '../models/scan_record.dart';

/// SQLite persistence layer for scan history.
class ScanRepository {
  static final ScanRepository _instance = ScanRepository._internal();
  factory ScanRepository() => _instance;
  ScanRepository._internal();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'metriscan.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scans (
            id TEXT PRIMARY KEY,
            timestamp INTEGER NOT NULL,
            front_image_path TEXT,
            back_image_paths TEXT,
            detail_image_path TEXT,
            report_json TEXT NOT NULL,
            compliance_score REAL NOT NULL,
            overall_pass INTEGER NOT NULL,
            output_json_path TEXT
          )
        ''');
      },
    );
  }

  Future<void> insertScan(ComplianceReport report, String? outputJsonPath) async {
    final db = await _database;
    final front = report.stages
        .where((s) => s.stage.name == 'front')
        .expand((s) => s.imagePaths)
        .firstOrNull;
    final back = report.stages
        .where((s) => s.stage.name == 'back')
        .expand((s) => s.imagePaths)
        .toList();
    final detail = report.stages
        .where((s) => s.stage.name == 'detail')
        .expand((s) => s.imagePaths)
        .firstOrNull;

    await db.insert(
      'scans',
      {
        'id': report.scanId,
        'timestamp': report.timestamp.millisecondsSinceEpoch,
        'front_image_path': front,
        'back_image_paths': jsonEncode(back),
        'detail_image_path': detail,
        'report_json': jsonEncode(report.toJson()),
        'compliance_score': report.overallScore,
        'overall_pass': report.overallScore >= 0.9 ? 1 : 0,
        'output_json_path': outputJsonPath,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ScanRecord>> getAllScans() async {
    final db = await _database;
    final rows = await db.query('scans', orderBy: 'timestamp DESC');
    return rows.map((r) => ScanRecord.fromJson(r)).toList();
  }

  Future<ComplianceReport?> getReportById(String id) async {
    final db = await _database;
    final rows = await db.query('scans', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final json = jsonDecode(rows.first['report_json'] as String)
        as Map<String, dynamic>;
    return ComplianceReport.fromJson(json);
  }

  Future<void> deleteScan(String id) async {
    final db = await _database;
    await db.delete('scans', where: 'id = ?', whereArgs: [id]);
  }
}

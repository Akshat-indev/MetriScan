import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'correction_memory_store.dart';
import 'memory_similarity.dart';

/// Temporary similarity-based replacement for a trained correction model.
class CorrectionMemory {
  static final CorrectionMemory _instance = CorrectionMemory._internal();

  factory CorrectionMemory() => _instance;

  CorrectionMemory._internal();

  final CorrectionMemoryStore _store = CorrectionMemoryStore();

  /// Applies trusted OCR-pattern substitutions before keyword matching.
  Future<String> preprocessOcrText(String rawText) async {
    if (!_flutterBindingIsReady) return rawText;
    var corrected = rawText;
    List<PatternCorrection> patterns;
    try {
      patterns = await _store.patternCorrections();
    } on StateError {
      // Pure Dart rule-engine tests do not initialize Flutter's platform
      // bindings; correction memory is inactive until the app is running.
      return rawText;
    }
    for (final pattern in patterns) {
      if (pattern.verifiedCount < 2 || pattern.rawSnippet.isEmpty) continue;
      corrected = corrected.replaceAllMapped(
        RegExp(RegExp.escape(pattern.rawSnippet), caseSensitive: false),
        (_) => pattern.correctedPattern,
      );
      if (corrected != rawText) {
        developer.log(
          'pattern applied raw="${pattern.rawSnippet}" '
          'corrected="${pattern.correctedPattern}" '
          'verified_count=${pattern.verifiedCount}',
          name: 'metriscan.correction_memory',
        );
      }
    }
    return corrected;
  }

  /// Applies a high-similarity verified product memory to extracted fields.
  ///
  /// [verifiedCorrections] and [rawOcrSnippets] are supplied only when the
  /// current report has just been verified by the user.
  Future<Map<String, String?>> applyKnownProduct(
    Map<String, String?> extractedFields, {
    Map<String, String?>? verifiedCorrections,
    Map<String, String>? rawOcrSnippets,
  }) async {
    if (!_flutterBindingIsReady) return extractedFields;
    if (verifiedCorrections != null) {
      await recordVerifiedCorrection(
        verifiedCorrections,
        rawOcrSnippets: rawOcrSnippets ?? const {},
      );
    }

    final fingerprint = productFingerprint(extractedFields);
    developer.log(
      'rescan fingerprint="$fingerprint"',
      name: 'metriscan.correction_memory',
    );
    if (fingerprint.isEmpty) return extractedFields;

    ProductMemoryMatch? memory;
    try {
      memory = await _store.findClosestProduct(fingerprint);
    } on StateError {
      // Keep the rule engine usable in non-platform test environments.
      return extractedFields;
    }
    if (memory == null || memory.similarity < 0.80) {
      developer.log(
        'product_memory no override similarity=${memory?.similarity}',
        name: 'metriscan.correction_memory',
      );
      return extractedFields;
    }

    final merged = {...extractedFields};
    for (final entry in memory.correctedFields.entries) {
      final current = extractedFields[entry.key];
      if (current != null && current.isNotEmpty && current != entry.value) {
        developer.log(
          'Correction-memory disagreement for ${entry.key}: '
          'rule="$current", memory="${entry.value}"',
          name: 'metriscan.correction_memory',
        );
      }
      merged[entry.key] = entry.value;
    }
    return merged;
  }

  /// Stores product-level corrections and recurring OCR-pattern corrections.
  Future<void> recordVerifiedCorrection(
    Map<String, String?> correctedFields, {
    required Map<String, String> rawOcrSnippets,
  }) async {
    final fingerprint = productFingerprint(correctedFields);
    developer.log(
      'verified correction fingerprint="$fingerprint"',
      name: 'metriscan.correction_memory',
    );
    if (fingerprint.isNotEmpty) {
      await _store.saveProductMemory(
        fingerprint: fingerprint,
        correctedFields: correctedFields,
      );
    }

    for (final entry in rawOcrSnippets.entries) {
      final raw = normalize(entry.value);
      final corrected = correctedFields[entry.key];
      if (raw.isEmpty || corrected == null || corrected.trim().isEmpty) {
        continue;
      }
      await _store.savePatternCorrection(
        fieldType: entry.key,
        rawSnippet: raw,
        correctedPattern: corrected.trim(),
      );
    }
  }

  /// Stable product fingerprint based on front-page fields.
  String productFingerprint(Map<String, String?> fields) {
    final parts = [
      fields['product_name'],
      fields['company_name'],
      fields['net_quantity'],
    ].map((value) => normalize(value ?? '')).toList();
    if (parts.every((part) => part.isEmpty)) return '';
    return parts.join('|');
  }

  bool get _flutterBindingIsReady {
    try {
      WidgetsBinding.instance;
      return true;
    } on FlutterError {
      return false;
    }
  }
}

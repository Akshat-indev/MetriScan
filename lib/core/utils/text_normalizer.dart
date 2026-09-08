import 'dart:math';

/// Utility functions to normalize OCR text and perform fuzzy matching.
class TextNormalizer {
  /// Strip stray punctuation, lowercase, and fix common OCR typos.
  static String normalizeOcr(String text) {
    String t = text.toLowerCase().trim();
    // Common OCR misreads
    t = t.replaceAll(RegExp(r'\b0\b'), 'o'); 
    t = t.replaceAll('₹', 'rs');
    t = t.replaceAll('₹', 'rs'); // in case of different character encodings
    t = t.replaceAll('m.r.p', 'mrp');
    t = t.replaceAll('m.r.p.', 'mrp');
    t = t.replaceAll(RegExp(r'\s+'), ' '); // compress spaces
    
    // For fuzzy matching, strip punctuation
    return t.replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }

  /// Basic Levenshtein distance
  static int levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var v0 = List<int>.generate(b.length + 1, (i) => i);
    var v1 = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        var cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (var j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[b.length];
  }

  /// Returns true if [normalizedInput] fuzzy-matches any keyword in [keywords]
  /// within [maxDistance].
  static String? fuzzyMatchAny(String normalizedInput, List<String> keywords, {int maxDistance = 2}) {
    final tokens = normalizedInput.split(' ');
    
    for (final keyword in keywords) {
      final normalizedKeyword = normalizeOcr(keyword);
      // check if any token matches
      for (final token in tokens) {
        if (levenshteinDistance(token, normalizedKeyword) <= maxDistance) {
          return keyword;
        }
      }
      // check sliding window for multi-word keywords
      final kwTokens = normalizedKeyword.split(' ');
      if (kwTokens.length > 1 && tokens.length >= kwTokens.length) {
        for (var i = 0; i <= tokens.length - kwTokens.length; i++) {
          final window = tokens.sublist(i, i + kwTokens.length).join(' ');
          if (levenshteinDistance(window, normalizedKeyword) <= maxDistance) {
            return keyword;
          }
        }
      }
    }
    return null;
  }
}

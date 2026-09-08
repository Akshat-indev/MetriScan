import 'package:flutter_test/flutter_test.dart';
import 'package:metriscan/correction_memory/correction_memory.dart';
import 'package:metriscan/correction_memory/memory_similarity.dart';

void main() {
  group('Correction memory similarity', () {
    test('normalizes punctuation and repeated whitespace', () {
      expect(normalize('  Acme® 500-g  '), 'acme 500 g');
    });

    test('recognizes a near-duplicate product fingerprint', () {
      final score = similarity(
        'fresh soap|acme labs|100 g',
        'Fresh-Soap|Acme Labs|100g',
      );
      expect(score, greaterThanOrEqualTo(0.85));
    });

    test('fingerprints only stable front-page fields', () {
      final fingerprint = CorrectionMemory().productFingerprint({
        'product_name': 'Fresh Soap!',
        'company_name': 'Acme Labs',
        'net_quantity': '100 g',
        'mrp': '₹89.00',
      });
      expect(fingerprint, 'fresh soap|acme labs|100 g');
    });

    test('does not treat unrelated products as similar', () {
      expect(
        similarity('fresh soap|acme labs|100 g', 'green tea|other foods|250 g'),
        lessThan(0.85),
      );
    });
  });
}

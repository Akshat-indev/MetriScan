/// Validates date strings parsed by the OCR regex to ensure they are logically sound.
class DateValidator {
  /// Returns a canonical date only when the complete candidate is valid.
  static String? validatedDate(String rawDate) {
    final value = rawDate.trim();
    if (value.isEmpty) return null;

    final yyyymm = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value);
    if (yyyymm != null) {
      final year = int.parse(yyyymm.group(1)!);
      final month = int.parse(yyyymm.group(2)!);
      return _isValid(year, month) ? value : null;
    }

    final yyyymmdd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (yyyymmdd != null) {
      final year = int.parse(yyyymmdd.group(1)!);
      final month = int.parse(yyyymmdd.group(2)!);
      final day = int.parse(yyyymmdd.group(3)!);
      return _isValidDay(year, month, day) ? value : null;
    }

    final dmy = RegExp(r'^(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{4})$')
        .firstMatch(value);
    if (dmy != null) {
      final day = int.parse(dmy.group(1)!);
      final month = int.parse(dmy.group(2)!);
      final year = int.parse(dmy.group(3)!);
      return _isValidDay(year, month, day)
          ? '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}'
          : null;
    }

    final mmyyyy = RegExp(r'^(\d{1,2})[\/\-\.](\d{4})$').firstMatch(value);
    if (mmyyyy != null) {
      final month = int.parse(mmyyyy.group(1)!);
      final year = int.parse(mmyyyy.group(2)!);
      return _isValid(year, month)
          ? '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}'
          : null;
    }

    final textMonth = RegExp(
      r'^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s,\.]+(\d{4})$',
      caseSensitive: false,
    ).firstMatch(value);
    if (textMonth != null) {
      const months = <String, int>{
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      };
      final month = months[textMonth.group(1)!.substring(0, 3).toLowerCase()];
      final year = int.parse(textMonth.group(2)!);
      if (month != null && _isValid(year, month)) {
        return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
      }
    }
    return null;
  }

  static bool isValidDateString(String rawDate) {
    return validatedDate(rawDate) != null;
  }

  static bool _isValid(int year, int month) {
    // Basic bounds checking for reasonable manufacturing/expiry dates
    // Assume products scanned won't be from before 2010 or expiring after 2040.
    if (year < 2010 || year > 2040) return false;
    if (month < 1 || month > 12) return false;
    return true;
  }

  static bool _isValidDay(int year, int month, int day) {
    if (!_isValid(year, month) || day < 1) return false;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }
}

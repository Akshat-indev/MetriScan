/// The three guided capture stages of a MetriScan session.
enum ScanStage { front, back, detail }

extension ScanStageX on ScanStage {
  String get displayName {
    switch (this) {
      case ScanStage.front:
        return 'Front Label';
      case ScanStage.back:
        return 'Back Label';
      case ScanStage.detail:
        return 'MRP · Dates · Detail';
    }
  }

  String get guidanceText {
    switch (this) {
      case ScanStage.front:
        return 'Point at the front — product name and brand visible';
      case ScanStage.back:
        return 'Point at the back — ingredients, FSSAI, manufacturer details';
      case ScanStage.detail:
        return 'Point at MRP, dates, and lot number — fine print OK';
    }
  }

  bool get allowsMultipleCaptures => this == ScanStage.back;
  bool get enforcesBoundaryClipping => this != ScanStage.detail;
  String get id => name;
}

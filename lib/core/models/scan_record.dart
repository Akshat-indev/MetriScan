/// SQLite row model for the scan history list.
class ScanRecord {
  final String id;
  final int timestampMs;
  final String? frontImagePath;
  final String backImagePathsJson;
  final String? detailImagePath;
  final String reportJson;
  final double complianceScore;
  final int overallPass;
  final String? outputJsonPath;

  const ScanRecord({
    required this.id,
    required this.timestampMs,
    this.frontImagePath,
    this.backImagePathsJson = '[]',
    this.detailImagePath,
    required this.reportJson,
    required this.complianceScore,
    required this.overallPass,
    this.outputJsonPath,
  });

  factory ScanRecord.fromJson(Map<String, dynamic> json) => ScanRecord(
        id: json['id'] as String,
        timestampMs: json['timestamp'] as int,
        frontImagePath: json['front_image_path'] as String?,
        backImagePathsJson: json['back_image_paths'] as String? ?? '[]',
        detailImagePath: json['detail_image_path'] as String?,
        reportJson: json['report_json'] as String,
        complianceScore: (json['compliance_score'] as num).toDouble(),
        overallPass: json['overall_pass'] as int,
        outputJsonPath: json['output_json_path'] as String?,
      );
}

import 'package:flutter/material.dart';
import '../../../core/models/scan_stage.dart';

/// Top banner showing the current stage name and guidance text.
class StageGuideBanner extends StatelessWidget {
  final ScanStage stage;

  const StageGuideBanner({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withAlpha(180),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _stageIcon(stage),
                const SizedBox(width: 8),
                Text(
                  stage.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              stage.guidanceText,
              style: TextStyle(
                color: Colors.white.withAlpha(200),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stageIcon(ScanStage stage) {
    final icons = {
      ScanStage.front: Icons.label_important_outline,
      ScanStage.back: Icons.flip_to_back_outlined,
      ScanStage.detail: Icons.text_snippet_outlined,
    };
    return Icon(icons[stage], color: Colors.green.shade300, size: 22);
  }
}

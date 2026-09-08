import 'package:flutter/material.dart';
import '../../core/models/field_result.dart';

/// Expandable tile for a single extracted field.
class FieldTile extends StatelessWidget {
  final FieldResult result;

  const FieldTile({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(result.status);
    final icon = _statusIcon(result.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          result.fieldLabel,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        trailing: _StatusBadge(status: result.status),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.matchedText != null) ...[
                  const Text('Extracted:',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(
                    result.matchedText!,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (result.normalisedValue != null &&
                      result.normalisedValue != result.matchedText) ...[
                    const SizedBox(height: 4),
                    const Text('Normalised:',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      result.normalisedValue!,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'OCR Conf: ${(result.ocrConfidence * 100).toStringAsFixed(0)}%  •  Rule Conf: ${(result.matchConfidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                  if (result.matchReason != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Reason: ${result.matchReason}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  ],
                  if (result.fontSizePx != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Est. Font Size: ${result.fontSizePx!.toStringAsFixed(1)} px',
                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                    ),
                  ],
                  if (result.matchType != MatchType.coLocated) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.purple.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        'Inferred (${result.matchType.name})',
                        style: const TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
                if (result.violation != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: Colors.red),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          result.violation!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(FieldStatus status) {
    switch (status) {
      case FieldStatus.found:
        return Colors.green;
      case FieldStatus.partial:
        return Colors.orange;
      case FieldStatus.notFound:
        return Colors.red;
      case FieldStatus.conditional:
        return Colors.blueGrey;
    }
  }

  IconData _statusIcon(FieldStatus status) {
    switch (status) {
      case FieldStatus.found:
        return Icons.check_circle_outline;
      case FieldStatus.partial:
        return Icons.warning_amber_outlined;
      case FieldStatus.notFound:
        return Icons.cancel_outlined;
      case FieldStatus.conditional:
        return Icons.help_outline;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final FieldStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final labels = {
      FieldStatus.found: ('Found', Colors.green),
      FieldStatus.partial: ('Partial', Colors.orange),
      FieldStatus.notFound: ('Missing', Colors.red),
      FieldStatus.conditional: ('N/A', Colors.blueGrey),
    };
    final (label, color) = labels[status]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';

/// Horizontal strip showing thumbnails of captured back-label photos.
class BackThumbnailRow extends StatelessWidget {
  final List<String> imagePaths;

  const BackThumbnailRow({super.key, required this.imagePaths});

  @override
  Widget build(BuildContext context) {
    if (imagePaths.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...imagePaths.asMap().entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(entry.value),
                    width: 56,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${entry.key + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        // Empty slots
        ...List.generate(
          (3 - imagePaths.length).clamp(0, 3),
          (_) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              width: 56,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white38, width: 1.5),
              ),
              child: const Icon(Icons.add_photo_alternate_outlined,
                  color: Colors.white38, size: 24),
            ),
          ),
        ),
      ],
    );
  }
}

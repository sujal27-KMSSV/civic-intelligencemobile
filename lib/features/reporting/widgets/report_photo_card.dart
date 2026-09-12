import 'dart:io';

import 'package:flutter/material.dart';

/// Reusable rounded photo preview used in the review and result screens.
class ReportPhotoCard extends StatelessWidget {
  const ReportPhotoCard({super.key, required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text(
              'Photo attached',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              cacheWidth: 540,
              errorBuilder: (context, error, stack) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
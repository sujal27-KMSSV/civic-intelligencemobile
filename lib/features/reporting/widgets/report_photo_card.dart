import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/widgets/remote_photo.dart';

/// Reusable rounded photo preview used in the review and result screens.
///
/// Accepts either a local file path (pre-submit preview) or a remote URL
/// (returned by the API after the report is saved).
class ReportPhotoCard extends StatelessWidget {
  const ReportPhotoCard({super.key, required this.imagePath});

  final String imagePath;

  bool get _isRemote =>
      imagePath.startsWith('http://') || imagePath.startsWith('https://');

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
        AspectRatio(
          aspectRatio: 4 / 3,
          child: _isRemote
              ? RemotePhoto(
                  url: imagePath,
                  borderRadius: 16,
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                    cacheWidth: 540,
                    errorBuilder: (context, error, stack) => Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
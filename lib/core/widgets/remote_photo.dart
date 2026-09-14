import 'dart:io';

import 'package:flutter/material.dart';

/// Renders an issue photo from a network URL (or a local path) with a
/// consistent placeholder while loading and on error. Used by list cards so
/// uploaded photos are visible everywhere, not just on the detail screen.
class RemotePhoto extends StatelessWidget {
  const RemotePhoto({
    super.key,
    required this.url,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 12,
  });

  final String? url;
  final double aspectRatio;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final value = url;
    if (value == null || value.isEmpty) return _placeholder;

    final Widget image;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      image = Image.network(
        value,
        fit: BoxFit.cover,
        cacheWidth: 540,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: 120,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stack) => _placeholder,
      );
    } else {
      image = Image.file(
        File(value),
        fit: BoxFit.cover,
        cacheWidth: 540,
        errorBuilder: (context, error, stack) => _placeholder,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(aspectRatio: aspectRatio, child: image),
    );
  }

  Widget get _placeholder => Container(
        color: const Color(0xFFE8EAED),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, size: 36, color: Colors.grey),
      );
}
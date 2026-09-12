import 'package:flutter/material.dart';
import 'colors.dart';

/// Maps a severity string to a consistent colour across chips, markers and
/// details. Unknown or missing values fall back to grey.
Color severityColor(String? severity) {
  switch (severity?.toUpperCase() ?? '') {
    case 'CRITICAL':
      return AppColors.critical;
    case 'HIGH':
      return AppColors.high;
    case 'MEDIUM':
      return AppColors.medium;
    case 'LOW':
      return AppColors.low;
    default:
      return Colors.grey;
  }
}
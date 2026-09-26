import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Maps the engine's explainable priority label to a consistent colour across
/// chips, cards and details. Unknown or missing values fall back to grey.
Color priorityColor(String? label) {
  switch (label?.toUpperCase() ?? '') {
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

/// Rule-based priority badge ("Low", "Medium", "High", "Critical"). Uses the
/// same pill language as [SeverityChip] so the two read consistently.
class PriorityChip extends StatelessWidget {
  final String? label;

  const PriorityChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(label);
    final text = _labelFor(label);
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _labelFor(String? label) {
    switch (label?.toLowerCase() ?? '') {
      case 'critical':
        return 'Critical';
      case 'high':
        return 'High';
      case 'medium':
        return 'Medium';
      case 'low':
        return 'Low';
      default:
        final trimmed = (label ?? '').trim();
        if (trimmed.isEmpty) return '';
        return trimmed[0].toUpperCase() + trimmed.substring(1);
    }
  }
}
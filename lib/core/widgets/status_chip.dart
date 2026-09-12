import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../../models/issue.dart';

class StatusChip extends StatelessWidget {
  final IssueStatus status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (String, Color) _styleFor(IssueStatus status) {
    switch (status) {
      case IssueStatus.reported:
        return ('Reported', AppColors.primary);
      case IssueStatus.verified:
        return ('Verified', const Color(0xFFF9A825));
      case IssueStatus.assigned:
        return ('Assigned', const Color(0xFFFB8C00));
      case IssueStatus.inProgress:
        return ('In Progress', const Color(0xFFEF6C00));
      case IssueStatus.resolved:
        return ('Resolved', AppColors.secondary);
      case IssueStatus.rejected:
        return ('Rejected', const Color(0xFF757575));
      case IssueStatus.unknown:
        return ('Unknown', Colors.grey);
    }
  }
}
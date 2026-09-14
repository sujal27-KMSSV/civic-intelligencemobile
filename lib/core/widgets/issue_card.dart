import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/issue.dart';
import 'remote_photo.dart';
import 'severity_chip.dart';
import 'status_chip.dart';

class IssueCard extends StatelessWidget {
  final Issue issue;

  const IssueCard({super.key, required this.issue});

  String get _category => issue.analysis?.category ?? 'Issue';
  String get _severity => issue.analysis?.severity ?? '';
  int get _duplicateCount => issue.analysis?.duplicateCount ?? 0;

  String get _location {
    final address = issue.address;
    if (address != null && address.trim().isNotEmpty) return address;
    if (issue.latitude != null && issue.longitude != null) {
      return '${issue.latitude!.toStringAsFixed(5)}, '
          '${issue.longitude!.toStringAsFixed(5)}';
    }
    return 'Location unavailable';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/issue/${issue.id}', extra: issue),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (issue.imageUrl != null) ...[
                RemotePhoto(url: issue.imageUrl),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _category,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (_severity.isNotEmpty) ...[
                    SeverityChip(severity: _severity),
                    const SizedBox(width: 6),
                  ],
                  StatusChip(status: issue.statusEnum),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                issue.description ?? 'No description',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ),
                  Text(
                    issue.id,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    _dateLabel(issue.createdAt),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  const Spacer(),
                  if (_duplicateCount > 0) ...[
                    Icon(Icons.content_copy_outlined,
                        size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '$_duplicateCount duplicate'
                      '${_duplicateCount == 1 ? '' : 's'}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Uploaded recently';
    final local = date.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}
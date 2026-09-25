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

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/issue/${issue.id}', extra: issue),
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
              if (_coordinates != null && issue.address != null &&
                  issue.address!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.pin_drop_outlined,
                        size: 14, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _coordinates!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    _whenLabel(issue),
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

  String get _location {
    final address = issue.address;
    if (address != null && address.trim().isNotEmpty) return address;
    return _coordinates ?? 'Location unavailable';
  }

  /// "28.61390, 77.20900" — shown as a secondary line whenever coordinates are
  /// known, even when a friendly address is displayed above.
  String? get _coordinates {
    final lat = issue.latitude;
    final lng = issue.longitude;
    if (lat == null || lng == null) return null;
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  /// Created date, upgraded to an "updated" label when the report was later
  /// edited by the citizen or the authority.
  String _whenLabel(Issue issue) {
    final created = issue.createdAt;
    if (created == null) return 'Uploaded recently';
    final updated = issue.updatedAt;
    if (updated != null &&
        updated.toUtc().difference(created.toUtc()).inMinutes >= 1) {
      final corrected = updated.isAfter(created) ? updated : created;
      return 'Created ${_dateLabel(created)} · Updated ${_dateLabel(corrected)}';
    }
    return _dateLabel(created);
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
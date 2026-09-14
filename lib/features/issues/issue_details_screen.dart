import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/widgets/severity_chip.dart';
import '../../core/widgets/status_chip.dart';
import '../../models/issue.dart';
import 'issue_details_provider.dart';

/// Full view of a citizen report: photo, civic analysis, location, department
/// and a status timeline. Each field degrades to a friendly fallback when the
/// backend omits it, so the screen stays demo-safe on partial data.
///
/// When a full [issue] object is already available (e.g. from a list screen)
/// it is shown immediately, then refreshed from `GET /api/issues/{id}/` so
/// status changes from the backend appear after a pull-to-refresh. When no
/// object is given (e.g. a deep link) the screen fetches it by id.
class IssueDetailsScreen extends ConsumerWidget {
  final String issueId;
  final Issue? issue;

  const IssueDetailsScreen({super.key, required this.issueId, this.issue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // When the screen was opened from a list it already has the full Issue
    // object, so no fetch is needed (pull-to-refresh still refetches on
    // demand). Only deep links without an `issue` fetch by id.
    final fetched = issue == null ? ref.watch(issueDetailsProvider(issueId)) : null;
    final shown = fetched?.valueOrNull ?? issue;
    final fetching = issue == null && (fetched?.isLoading ?? false);
    final failed = issue == null && (fetched?.hasError ?? false);

    return Scaffold(
      appBar: AppBar(title: Text('Issue #$issueId')),
      body: fetching
          ? const Center(child: CircularProgressIndicator())
          : failed
              ? _LoadError(
                  issueId: issueId,
                  onRetry: () => ref.invalidate(issueDetailsProvider(issueId)),
                )
              : shown == null
                  ? _MissingState(issueId: issueId)
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.refresh(issueDetailsProvider(issueId).future),
                      child: _IssueDetailBody(issue: shown),
                    ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final String issueId;
  final VoidCallback onRetry;

  const _LoadError({required this.issueId, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Could not load Issue #$issueId',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingState extends StatelessWidget {
  final String issueId;

  const _MissingState({required this.issueId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Issue #$issueId was not found',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This report may have been removed or is not accessible from here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueDetailBody extends StatelessWidget {
  final Issue issue;

  const _IssueDetailBody({required this.issue});

  String get _category => issue.analysis?.category ?? 'Other';
  bool get _hasAnalysis => issue.analysis != null;
  int get _duplicates => issue.analysis?.duplicateCount ?? 0;
  bool get _isDuplicate => issue.analysis?.isDuplicate ?? false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _PhotoHeader(imageUrl: issue.imageUrl),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TitleRow(
                category: _category,
                severity: issue.analysis?.severity ?? 'Unknown',
                status: issue.statusEnum,
              ),
              const SizedBox(height: 8),
              Text(
                _submittedLine(),
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (_hasAnalysis) _AnalysisSection(issue: issue) else const _AnalysisUnavailable(),
              const SizedBox(height: 16),
              _DetailsSection(issue: issue),
              const SizedBox(height: 16),
              _StatusTimelineSection(issue: issue),
              if (_isDuplicate)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _DuplicateBanner(count: _duplicates),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _submittedLine() {
    final created = issue.createdAt;
    if (created != null) {
      return 'Reported on ${_formatDate(created)}';
    }
    return 'Reported recently';
  }
}

class _TitleRow extends StatelessWidget {
  final String category;
  final String severity;
  final IssueStatus status;

  const _TitleRow({
    required this.category,
    required this.severity,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            category,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        SeverityChip(severity: severity),
        const SizedBox(width: 6),
        StatusChip(status: status),
      ],
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  final String? imageUrl;

  const _PhotoHeader({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return const _PhotoPlaceholder();
    }

    final Widget image;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      image = Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: 1080,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stack) => const _PhotoPlaceholder(),
      );
    } else {
      image = Image.file(
        File(url),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => const _PhotoPlaceholder(),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: const Color(0xFFE8EAED),
        alignment: Alignment.center,
        child: image,
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE8EAED),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            'No photo available',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AnalysisSection extends StatelessWidget {
  final Issue issue;

  const _AnalysisSection({required this.issue});

  @override
  Widget build(BuildContext context) {
    final analysis = issue.analysis!;
    final confidence = analysis.confidence;

    return _SectionCard(
      title: 'FixMyGrid analysis',
      icon: Icons.auto_awesome_outlined,
      children: [
        if (confidence > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Confidence',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      '${(confidence * 100).round()}%',
                      style: TextStyle(
                        color: _confidenceColor(confidence),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: confidence,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    color: _confidenceColor(confidence),
                  ),
                ),
              ],
            ),
          )
        else
          const _InfoRow(
            icon: Icons.percent,
            label: 'Confidence',
            value: 'Not reported',
          ),
        _InfoRow(
          icon: Icons.scale_outlined,
          label: 'Severity',
          value: analysis.severity.toUpperCase(),
        ),
        _InfoRow(
          icon: Icons.content_copy_outlined,
          label: 'Duplicate reports',
          value: analysis.duplicateCount > 0
              ? '${analysis.duplicateCount}'
              : 'None',
        ),
        _InfoRow(
          icon: Icons.account_balance_outlined,
          label: 'Department',
          value: analysis.department.trim().isEmpty
              ? 'Unassigned'
              : analysis.department,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'Rule-based civic analysis — not a trained ML model.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Color _confidenceColor(double value) {
    if (value >= 0.8) return AppColors.secondary;
    if (value >= 0.6) return AppColors.medium;
    return AppColors.warning;
  }
}

class _AnalysisUnavailable extends StatelessWidget {
  const _AnalysisUnavailable();

  @override
  Widget build(BuildContext context) {
    return const _SectionCard(
      title: 'FixMyGrid analysis',
      icon: Icons.auto_awesome_outlined,
      children: [
        _InfoRow(
          icon: Icons.auto_awesome_outlined,
          label: 'Analysis',
          value: 'Not available yet',
        ),
      ],
    );
  }
}

class _DetailsSection extends StatelessWidget {
  final Issue issue;

  const _DetailsSection({required this.issue});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Details',
      icon: Icons.description_outlined,
      children: [
        const _InfoRow(
          icon: Icons.article_outlined,
          label: 'Description',
          value: null,
        ),
        if (issue.description != null && issue.description!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
            child: Text(
              issue.description!,
              style: const TextStyle(height: 1.4),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'No description provided.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        _InfoRow(
          icon: Icons.location_on_outlined,
          label: 'Location',
          value: _locationLabel(),
        ),
      ],
    );
  }

  String _locationLabel() {
    final address = issue.address;
    if (address != null && address.trim().isNotEmpty) return address;
    final lat = issue.latitude;
    final lng = issue.longitude;
    if (lat != null && lng != null) {
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
    return 'Location unavailable';
  }
}

class _StatusTimelineSection extends StatelessWidget {
  final Issue issue;

  const _StatusTimelineSection({required this.issue});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Status timeline',
      icon: Icons.timeline_outlined,
      children: [
        _StatusTimeline(issue: issue),
      ],
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  final Issue issue;

  const _StatusTimeline({required this.issue});

  @override
  Widget build(BuildContext context) {
    final created = issue.createdAt;
    final updated = issue.updatedAt;
    final status = issue.statusEnum;

    final hasTimestamps = created != null || updated != null;
    if (!hasTimestamps && status == IssueStatus.unknown) {
      return const Text(
        'Status history is not available for this issue yet.',
        style: TextStyle(color: Colors.grey),
      );
    }

    final (currentLabel, currentColor) = _statusStyle(status);
    final entries = <(String, String?, Color)>[
      (
        'Reported',
        created != null ? _formatDate(created) : 'Date not recorded',
        AppColors.primary,
      ),
      (
        currentLabel,
        (updated != null && updated != created
            ? _formatDate(updated)
            : created != null
            ? _formatDate(created)
            : null),
        currentColor,
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          _TimelineRow(
            title: entries[i].$1,
            subtitle: entries[i].$2,
            color: entries[i].$3,
            isLast: i == entries.length - 1,
            emphasized: i == entries.length - 1,
          ),
        ],
      ],
    );
  }

  (String, Color) _statusStyle(IssueStatus status) {
    switch (status) {
      case IssueStatus.reported:
        return ('Reported', AppColors.primary);
      case IssueStatus.verified:
        return ('Verified', const Color(0xFFF9A825));
      case IssueStatus.assigned:
        return ('Assigned', const Color(0xFFFB8C00));
      case IssueStatus.inProgress:
        return ('In Progress', AppColors.warning);
      case IssueStatus.resolved:
        return ('Resolved', AppColors.secondary);
      case IssueStatus.rejected:
        return ('Rejected', const Color(0xFF757575));
      case IssueStatus.unknown:
        return ('Status unknown', Colors.grey);
    }
  }
}

class _TimelineRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color color;
  final bool isLast;
  final bool emphasized;

  const _TimelineRow({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isLast,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: Colors.grey[300]),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          emphasized ? FontWeight.bold : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateBanner extends StatelessWidget {
  final int count;

  const _DuplicateBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 0 ? '$count duplicate reports reported' : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label ?? 'This issue was flagged as a possible duplicate.',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _InfoRow({required this.icon, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value ?? 'Not available',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year} · '
      '$hour:$minute';
}
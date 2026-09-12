import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/issue_card.dart';
import '../../models/issue.dart';
import 'my_reports_provider.dart';

class MyReportsScreen extends ConsumerStatefulWidget {
  const MyReportsScreen({super.key});

  @override
  ConsumerState<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends ConsumerState<MyReportsScreen> {
  final List<IssueStatus> _filters = const [
    IssueStatus.reported,
    IssueStatus.verified,
    IssueStatus.assigned,
    IssueStatus.inProgress,
    IssueStatus.resolved,
    IssueStatus.rejected,
  ];
  IssueStatus? _selected;

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(myReportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
      body: SafeArea(
        child: reportsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load reports',
            message: 'Something went wrong. Try again.',
            action: FilledButton(
              onPressed: () => ref.invalidate(myReportsProvider),
              child: const Text('Retry'),
            ),
          ),
          data: (reports) => _buildContent(reports),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/report'),
        icon: const Icon(Icons.add),
        label: const Text('New Report'),
      ),
    );
  }

  Widget _buildContent(List<Issue> reports) {
    final List<Issue> issues = _selected == null
        ? reports
        : reports.where((issue) => issue.statusEnum == _selected).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _FilterChip(
                  label: 'All',
                  selected: _selected == null,
                  onTap: () => setState(() => _selected = null),
                );
              }
              final status = _filters[index - 1];
              return _FilterChip(
                label: _labelFor(status),
                selected: _selected == status,
                onTap: () => setState(() => _selected = status),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (issues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${issues.length} report${issues.length == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: issues.isEmpty
              ? _emptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: issues.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      IssueCard(issue: issues[index]),
                ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    if (_selected == null) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No reports yet',
        message: 'Submit your first report and track its status here.',
      );
    }
    return const EmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: 'Nothing here yet',
      message: 'Try a different filter or submit a new report.',
    );
  }

  String _labelFor(IssueStatus status) {
    switch (status) {
      case IssueStatus.reported:
        return 'Reported';
      case IssueStatus.verified:
        return 'Verified';
      case IssueStatus.assigned:
        return 'Assigned';
      case IssueStatus.inProgress:
        return 'In Progress';
      case IssueStatus.resolved:
        return 'Resolved';
      case IssueStatus.rejected:
        return 'Rejected';
      case IssueStatus.unknown:
        return 'Unknown';
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
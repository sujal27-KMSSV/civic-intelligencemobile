import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_logo.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/issue_card.dart';
import '../../features/auth/auth_state.dart';
import '../../features/feed/issue_feed_repository.dart';
import '../../features/notifications/notification_center.dart';
import '../../models/issue.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issuesAsync = ref.watch(issueFeedProvider);
    final issues = issuesAsync.valueOrNull ?? const <Issue>[];
    final unread = ref.watch(notificationCenterProvider).unreadCount;
    final userName = _displayName(ref);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(issueFeedProvider.future),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  issues: issues,
                  userName: userName,
                  unreadCount: unread,
                  onNotificationsPressed: () => context.go('/notifications'),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _QuickReportCard(
                        onTap: () => context.go('/report'),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Community Reports',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Reports shared by you and other residents in your area.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => context.go('/my-reports'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View your reports',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              _reportsSliver(context, ref, issuesAsync),
            ],
          ),
        ),
      ),
    );
  }

  String? _displayName(WidgetRef ref) {
    final authState = ref.watch(authProvider).valueOrNull;
    final user = authState?.user;
    if (user != null && user.fullName.trim().isNotEmpty) return user.fullName;
    return null;
  }

  Widget _reportsSliver(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Issue>> issuesAsync,
  ) {
    final issues = issuesAsync.valueOrNull ?? const <Issue>[];

    return issuesAsync.when(
      loading: () {
        if (issues.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return _buildList(issues);
      },
      error: (_, __) {
        if (issues.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 64),
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load reports',
                message: 'Check your connection and try again.',
                action: FilledButton(
                  onPressed: () => ref.invalidate(issueFeedProvider),
                  child: const Text('Retry'),
                ),
              ),
            ),
          );
        }
        return _buildList(issues);
      },
      data: (list) {
        if (list.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 64),
              child: EmptyState(
                icon: Icons.travel_explore,
                title: 'No community reports yet',
                message:
                    'Reports shared by residents will appear here. Be the first '
                    'to report an issue and help improve your city.',
                action: FilledButton.icon(
                  onPressed: () => context.go('/report'),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Report an issue'),
                ),
              ),
            ),
          );
        }
        return _buildList(list);
      },
    );
  }

  Widget _buildList(List<Issue> issues) {
    return SliverList.builder(
      itemCount: issues.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            index == issues.length - 1 ? 16 : 12,
          ),
          child: IssueCard(issue: issues[index]),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final List<Issue> issues;
  final String? userName;
  final int unreadCount;
  final VoidCallback onNotificationsPressed;

  const _Header({
    required this.issues,
    required this.userName,
    required this.unreadCount,
    required this.onNotificationsPressed,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = issues
        .where((issue) => issue.statusEnum == IssueStatus.resolved)
        .length;
    final open = issues
        .where(
          (issue) =>
              issue.statusEnum != IssueStatus.resolved &&
              issue.statusEnum != IssueStatus.rejected,
        )
        .length;
    final name = userName ?? 'Citizen';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onNotificationsPressed,
                icon: Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text('$unreadCount'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                color: Colors.white,
                tooltip: 'Notifications',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _StatTile(
                value: issues.length.toString(),
                label: 'Community',
                icon: Icons.report_gmailerrorred_outlined,
              ),
              const SizedBox(width: 12),
              _StatTile(
                value: '$open',
                label: 'Open',
                icon: Icons.pending_actions_outlined,
              ),
              const SizedBox(width: 12),
              _StatTile(
                value: resolved.toString(),
                label: 'Resolved',
                icon: Icons.check_circle_outline,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickReportCard extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickReportCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.add_a_photo_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report an Issue',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Snap a photo, add a description,\nwe\u2019ll route it to the right department',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
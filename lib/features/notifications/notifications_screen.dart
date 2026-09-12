import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/empty_state.dart';
import 'notification_center.dart';

/// In-app notification centre: status updates and submission confirmations.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final center = ref.watch(notificationCenterProvider);
    final notifications = center.notifications;
    final unread = center.unreadCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: unread == 0
                ? null
                : () =>
                    ref.read(notificationCenterProvider.notifier).markAllRead(),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: SafeArea(
        child: notifications.isEmpty
            ? const EmptyState(
                icon: Icons.notifications_none,
                title: 'No notifications yet',
                message:
                    'Status updates for your reports will appear here. '
                    'Submit a report to get started.',
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: notifications.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _NotificationTile(item: notifications[index]),
              ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final AppNotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final isUnread = !item.read;

    return ListTile(
      onTap: () {
        if (isUnread) {
          ref
              .read(notificationCenterProvider.notifier)
              .markRead(item.id);
        }
      },
      leading: CircleAvatar(
        backgroundColor: colorFor(item.type).withValues(alpha: 0.12),
        child: Icon(iconFor(item.type), color: colorFor(item.type), size: 20),
      ),
      title: Text(
        item.title,
        style: TextStyle(
          fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Text('${item.body}\n${_formatTime(item.timestamp)}'),
      isThreeLine: true,
      trailing: isUnread
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary,
              ),
            )
          : null,
      selected: isUnread,
    );
  }
}

Color colorFor(AppNotificationType type) {
  switch (type) {
    case AppNotificationType.submission:
      return Colors.blue.shade700;
    case AppNotificationType.statusChange:
      return Colors.orange.shade800;
    case AppNotificationType.info:
      return Colors.grey.shade600;
  }
}

IconData iconFor(AppNotificationType type) {
  switch (type) {
    case AppNotificationType.submission:
      return Icons.check_circle_outline;
    case AppNotificationType.statusChange:
      return Icons.update_outlined;
    case AppNotificationType.info:
      return Icons.info_outline;
  }
}

String _formatTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${time.day} ${_months[time.month - 1]} ${time.year}';
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
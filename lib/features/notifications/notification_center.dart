import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppNotificationType { submission, statusChange, info }

/// A single in-app notification entry shown in the notification centre.
class AppNotificationItem {
  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool read;

  const AppNotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.read = false,
  });

  AppNotificationItem copyWith({bool? read}) {
    return AppNotificationItem(
      id: id,
      type: type,
      title: title,
      body: body,
      timestamp: timestamp,
      read: read ?? this.read,
    );
  }
}

class NotificationCenterState {
  final List<AppNotificationItem> notifications;

  const NotificationCenterState({this.notifications = const []});

  int get unreadCount => notifications.where((n) => !n.read).length;
}

const int _maxNotifications = 50;

/// Holds in-app notifications. This is the local half of the notification
/// story: when a real push channel is configured, the [NotificationService]
/// implementation forwards the same events here (and to the device) instead.
final notificationCenterProvider = NotifierProvider<NotificationCenterNotifier,
    NotificationCenterState>(NotificationCenterNotifier.new);

class NotificationCenterNotifier extends Notifier<NotificationCenterState> {
  @override
  NotificationCenterState build() => const NotificationCenterState();

  void add(
    AppNotificationType type, {
    required String title,
    required String body,
  }) {
    final item = AppNotificationItem(
      id: 'n-${DateTime.now().microsecondsSinceEpoch}-'
          '${state.notifications.length}',
      type: type,
      title: title,
      body: body,
      timestamp: DateTime.now(),
    );
    final updated = [item, ...state.notifications];
    if (updated.length > _maxNotifications) {
      updated.removeRange(_maxNotifications, updated.length);
    }
    state = NotificationCenterState(notifications: updated);
  }

  void markAllRead() {
    if (state.unreadCount == 0) return;
    state = NotificationCenterState(
      notifications: state.notifications
          .map((n) => n.copyWith(read: true))
          .toList(),
    );
  }

  void markRead(String id) {
    state = NotificationCenterState(
      notifications: state.notifications
          .map((n) => n.id == id ? n.copyWith(read: true) : n)
          .toList(),
    );
  }
}
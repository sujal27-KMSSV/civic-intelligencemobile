import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notifications/notification_center.dart';
import '../models/issue.dart';

/// Build-time switch for real push notifications (FCM/APN or a websocket
/// channel). Off by default: the app runs fully on in-app notifications only.
/// Pass `--dart-define=PUSH_NOTIFICATIONS_ENABLED=true` once a push backend
/// is wired up (with credentials injected via secure config, not source).
const bool pushNotificationsEnabled =
    bool.fromEnvironment('PUSH_NOTIFICATIONS_ENABLED', defaultValue: false);

enum NotificationPermissionStatus { granted, denied, unsupported }

/// Contract for notifying a citizen about their reports.
///
/// The default implementation is [LocalNotificationService], which records
/// events in the in-app notification centre. A production build swaps in a
/// platform push implementation (Firebase Cloud Messaging etc.) that forwards
/// the same events to [notificationCenterProvider] and to the device.
abstract interface class NotificationService {
  Future<NotificationPermissionStatus> requestPermission();

  /// Called right after a report is accepted by the backend.
  void notifyIssueSubmitted(Issue issue);

  /// Called when a previously seen report moves to a new status.
  void notifyIssueStatusChanged(
    Issue issue, {
    required String from,
    required String to,
  });
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return LocalNotificationService(ref);
});

/// In-app implementation. No platform permissions or credentials required.
class LocalNotificationService implements NotificationService {
  LocalNotificationService(this._ref);

  final Ref _ref;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    // Nothing to request without a push channel; report the state so the UI
    // can show an honest permission banner if it wants to.
    return pushNotificationsEnabled
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.unsupported;
  }

  @override
  void notifyIssueSubmitted(Issue issue) {
    _ref.read(notificationCenterProvider.notifier).add(
          AppNotificationType.submission,
          title: 'Report ${issue.id} submitted',
          body:
              '${issue.analysis?.category ?? 'Your issue'} has been received. '
              'We will keep you updated as it is reviewed.',
        );
  }

  @override
  void notifyIssueStatusChanged(
    Issue issue, {
    required String from,
    required String to,
  }) {
    _ref.read(notificationCenterProvider.notifier).add(
          AppNotificationType.statusChange,
          title: 'Report ${issue.id} is now $to',
          body: 'Status changed from $from to $to.',
        );
  }
}
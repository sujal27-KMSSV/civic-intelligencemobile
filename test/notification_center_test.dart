import 'package:civic_intelligence/features/notifications/notification_center.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:civic_intelligence/services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const issue = Issue(id: 'CI-1042', description: 'Pothole', status: 'reported');

  ProviderContainer makeContainer() {
    return ProviderContainer();
  }

  test('notification centre records, orders and caps entries', () {
    final container = makeContainer();
    final notifier =
        container.read(notificationCenterProvider.notifier);

    for (var i = 0; i < 60; i++) {
      notifier.add(AppNotificationType.info,
          title: 'title $i', body: 'body $i');
    }

    final state = container.read(notificationCenterProvider);
    expect(state.notifications.length, 50);
    expect(state.notifications.first.title, 'title 59');
    expect(state.unreadCount, 50);
  });

  test('markAllRead and markRead clear unread flags', () {
    final container = makeContainer();
    final notifier = container.read(notificationCenterProvider.notifier);

    notifier.add(AppNotificationType.submission, title: 'a', body: 'b');
    notifier.add(AppNotificationType.info, title: 'c', body: 'd');
    final firstId = container.read(notificationCenterProvider)
        .notifications
        .first
        .id;

    notifier.markRead(firstId);
    var state = container.read(notificationCenterProvider);
    expect(state.unreadCount, 1);

    notifier.markAllRead();
    state = container.read(notificationCenterProvider);
    expect(state.unreadCount, 0);
  });

  test('notification service notifies about submissions and status changes',
      () {
    final container = makeContainer();
    final service = container.read(notificationServiceProvider);

    service.notifyIssueSubmitted(issue);
    service.notifyIssueStatusChanged(issue, from: 'Reported', to: 'In Progress');

    final state = container.read(notificationCenterProvider);
    expect(state.notifications.length, 2);
    expect(state.notifications[0].type, AppNotificationType.statusChange);
    expect(state.notifications[0].title, 'Report CI-1042 is now In Progress');
    expect(state.notifications[1].title, 'Report CI-1042 submitted');
  });

  test('local service reports push as unsupported unless enabled', () async {
    final container = makeContainer();
    final status = await container
        .read(notificationServiceProvider)
        .requestPermission();
    expect(status, pushNotificationsEnabled
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.unsupported);
  });
}
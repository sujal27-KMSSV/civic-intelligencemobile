import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IssueStatus.parse', () {
    test('maps every backend status to its enum value', () {
      expect(IssueStatus.parse('reported'), IssueStatus.reported);
      expect(IssueStatus.parse('submitted'), IssueStatus.reported);
      expect(IssueStatus.parse('pending'), IssueStatus.reported);
      expect(IssueStatus.parse('verified'), IssueStatus.verified);
      expect(IssueStatus.parse('in_review'), IssueStatus.verified);
      expect(IssueStatus.parse('assigned'), IssueStatus.assigned);
      expect(IssueStatus.parse('in_progress'), IssueStatus.inProgress);
      expect(IssueStatus.parse('resolved'), IssueStatus.resolved);
      expect(IssueStatus.parse('rejected'), IssueStatus.rejected);
      expect(IssueStatus.parse('cancelled'), IssueStatus.rejected);
      expect(IssueStatus.parse('something else'), IssueStatus.unknown);
      expect(IssueStatus.parse(null), IssueStatus.unknown);
    });

    test('parsing is case-insensitive', () {
      expect(IssueStatus.parse('REPORTED'), IssueStatus.reported);
      expect(IssueStatus.parse('In_Progress'), IssueStatus.inProgress);
    });
  });

  test('labels match the display names used across the app', () {
    expect(IssueStatus.reported.label, 'Reported');
    expect(IssueStatus.verified.label, 'Verified');
    expect(IssueStatus.assigned.label, 'Assigned');
    expect(IssueStatus.inProgress.label, 'In Progress');
    expect(IssueStatus.resolved.label, 'Resolved');
    expect(IssueStatus.rejected.label, 'Rejected');
    expect(IssueStatus.unknown.label, 'Unknown');
  });

  test('submission response defaults to reported status', () {
    final issue = Issue.fromSubmissionJson({
      'id': 42,
      'category': 'pothole',
      'confidence': 0.9,
      'severity': 'high',
      'duplicate': false,
      'duplicate_count': 0,
      'department': 'roads',
    });
    expect(issue.statusEnum, IssueStatus.reported);
  });
}
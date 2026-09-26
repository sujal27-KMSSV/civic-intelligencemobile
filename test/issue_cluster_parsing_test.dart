import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue cluster + priority parsing', () {
    test('fromListJson parses top-level cluster and priority fields', () {
      final issue = Issue.fromListJson({
        'id': 7,
        'category': 'Pothole',
        'duplicate_count': 4,
        'priority': 78.0,
        'priority_label': 'HIGH',
        'priority_reasons': ['High severity', '4 reports nearby'],
        'master_id': 7,
        'is_master': true,
        'cluster_size': 5,
      });

      expect(issue.priority, 78.0);
      expect(issue.priorityLabel, 'HIGH');
      expect(issue.priorityReasons, ['High severity', '4 reports nearby']);
      expect(issue.masterId, '7');
      expect(issue.isMaster, true);
      expect(issue.clusterSize, 5);
      expect(issue.analysis?.duplicateCount, 4);
    });

    test('fromListJson treats a child report via master_id', () {
      final child = Issue.fromListJson({
        'id': 8,
        'master_id': 7,
        'cluster_size': 5,
        'is_master': false,
      });

      expect(child.masterId, '7');
      expect(child.isMaster, false);
      expect(child.clusterSize, 5);
    });

    test('fromJson defaults gracefully when keys are absent', () {
      final sparse = Issue.fromJson({'id': 1});

      expect(sparse.priority, isNull);
      expect(sparse.priorityLabel, isNull);
      expect(sparse.priorityReasons, isEmpty);
      expect(sparse.masterId, isNull);
      expect(sparse.clusterSize, isNull);
      expect(sparse.isMaster, isNull);
    });

    test('fromSubmissionJson exposes priority and cluster from submission',
        () {
      final issue = Issue.fromSubmissionJson({
        'id': 9,
        'priority': 32.0,
        'priority_label': 'medium',
        'priority_reasons': ['3 reports nearby'],
        'duplicate': true,
        'duplicate_count': 3,
        'confidence': 0.86,
      });

      expect(issue.priority, 32.0);
      expect(issue.priorityLabel, 'medium');
      expect(issue.priorityReasons, ['3 reports nearby']);
      expect(issue.analysis?.isDuplicate, true);
      expect(issue.analysis?.duplicateCount, 3);
    });
  });
}
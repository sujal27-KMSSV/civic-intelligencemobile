import 'package:flutter_test/flutter_test.dart';

import 'package:civic_intelligence/models/issue.dart';

void main() {
  group('VisionInfo.fromJson', () {
    test('parses a full ok payload including priority model and detections',
        () {
      final vision = VisionInfo.fromJson({
        'status': 'ok',
        'models': {'embedding': 'mobilenet_v3_small', 'detection': 'yolov8n'},
        'detections': [
          {'label': 'car', 'confidence': 0.9, 'box': [1, 2, 3, 4]},
        ],
        'classifier_labels': ['street sign', 'car'],
        'priority_model': {
          'score': 88.5,
          'label': 'critical',
          'model': 'gradient-boosting-priority-v1',
          'honest_note': 'Prototype.',
        },
        'notes': ['YOLO detection uses COCO pretrained labels.'],
      });

      expect(vision.available, isTrue);
      expect(vision.models['embedding'], 'mobilenet_v3_small');
      expect(vision.detections.single.label, 'car');
      expect(vision.detections.single.confidence, 0.9);
      expect(vision.classifierLabels, ['street sign', 'car']);
      expect(vision.priorityModel!.score, 88.5);
      expect(vision.priorityModel!.label, 'critical');
      expect(vision.priorityModel!.honestNote, isNotNull);
    });

    test('degraded payload (unavailable) stays parseable and not available()',
        () {
      final vision = VisionInfo.fromJson({'status': 'unavailable'});
      expect(vision.available, isFalse);
      expect(vision.models, isEmpty);
      expect(vision.detections, isEmpty);
    });
  });

  group('Issue JSON parsing (vision fields)', () {
    Map<String, dynamic> baseJson() => {
          'id': 42,
          'status': 'reported',
          'priority': 74,
          'priority_model_score': 88.5,
          'vision': {
            'status': 'ok',
            'models': {'embedding': 'mobilenet_v3_small'},
            'detections': [],
            'classifier_labels': [],
            'priority_model': {'score': 88.5, 'label': 'critical'},
            'notes': [],
          },
        };

    test('fromJson parses vision + advisory ML priority', () {
      final issue = Issue.fromJson(baseJson());
      expect(issue.vision, isNotNull);
      expect(issue.vision!.available, isTrue);
      expect(issue.priorityModelScore, 88.5);
      expect(issue.priority, 74);
    });

    test('submission response parses vision + advisory priority', () {
      final issue = Issue.fromSubmissionJson(baseJson());
      expect(issue.vision, isNotNull);
      expect(issue.priorityModelScore, 88.5);
      expect(issue.priority, 74);
    });

    test('list payload parses vision + advisory priority', () {
      final issue = Issue.fromListJson(baseJson());
      expect(issue.vision, isNotNull);
      expect(issue.priorityModelScore, 88.5);
    });

    test('missing vision degrades gracefully', () {
      final issue = Issue.fromJson({'id': 1, 'status': 'reported'});
      expect(issue.vision, isNull);
      expect(issue.priorityModelScore, isNull);
    });
  });
}
enum IssueStatus {
  reported,
  verified,
  assigned,
  inProgress,
  resolved,
  rejected,
  unknown;

  static IssueStatus parse(String? value) {
    switch (value?.toLowerCase() ?? '') {
      case 'reported' || 'submitted' || 'pending':
        return IssueStatus.reported;
      case 'verified' || 'in_review' || 'in-review' || 'reviewing':
        return IssueStatus.verified;
      case 'assigned':
        return IssueStatus.assigned;
      case 'in_progress' || 'in-progress':
        return IssueStatus.inProgress;
      case 'resolved' || 'completed' || 'closed':
        return IssueStatus.resolved;
      case 'rejected' || 'cancelled' || 'canceled':
        return IssueStatus.rejected;
      default:
        return IssueStatus.unknown;
    }
  }
}

class Issue {
  final String id;
  final String? description;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final AiAnalysis? analysis;

  /// AI-sidecar insights (real models, labelled provenance). Null when the
  /// backend did not serve a vision block (sidecar off / degraded).
  final VisionInfo? vision;

  /// Advisory ML priority estimation (0..100) from the AI sidecar. NEVER the
  /// authoritative `priority` — always displayed with a prototype label.
  final double? priorityModelScore;

  /// Explainable, rule-based priority (0..100) computed by the civic engine.
  /// Only surfaced when the backend provides it.
  final double? priority;
  final String? priorityLabel;
  final List<String> priorityReasons;

  /// Duplicate-cluster context. A child report carries [masterId]; its cluster
  /// master is its own id. [clusterSize] counts every member (>= 1) and
  /// [isMaster] is true only for the cluster root. These are null whenever the
  /// backend did not include cluster fields (e.g. old cached data).
  final String? masterId;
  final int? clusterSize;
  final bool? isMaster;

  /// Server-authoritative flags: whether the current user may delete/edit this
  /// report right now. The backend derives them from its own clock and the
  /// report's permitted lifecycle, so the app never needs device-time math.
  final bool? canDelete;
  final bool? canEdit;

  const Issue({
    required this.id,
    this.description,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.address,
    this.status,
    this.createdAt,
    this.updatedAt,
    this.analysis,
    this.vision,
    this.priorityModelScore,
    this.priority,
    this.priorityLabel,
    this.priorityReasons = const [],
    this.masterId,
    this.clusterSize,
    this.isMaster,
    this.canDelete,
    this.canEdit,
  });

  factory Issue.fromJson(Map<String, dynamic> json) {
    return Issue(
      id: json['id'].toString(),
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      address: json['address'] as String?,
      status: json['status'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      analysis: json['analysis'] != null
          ? AiAnalysis.fromJson(json['analysis'] as Map<String, dynamic>)
          : null,
      vision: json['vision'] != null
          ? VisionInfo.fromJson(json['vision'] as Map<String, dynamic>)
          : null,
      priorityModelScore: _toDouble(json['priority_model_score']),
      priority: _toDouble(json['priority']),
      priorityLabel: json['priority_label'] as String?,
      priorityReasons: _stringList(json['priority_reasons']),
      masterId: json['master_id']?.toString(),
      clusterSize: (json['cluster_size'] as num?)?.toInt(),
      isMaster: json['is_master'] as bool?,
      canDelete: json['can_delete'] as bool?,
      canEdit: json['can_edit'] as bool?,
    );
  }

  /// Maps the submission response from POST /api/issues/ to an [Issue].
  ///
  /// The backend does not echo the uploaded photo or coordinates back, so
  /// optional local values (like [description]) can be layered on top for
  /// display purposes.
  factory Issue.fromSubmissionJson(
    Map<String, dynamic> json, {
    String? description,
  }) {
    final id = json['id'];
    return Issue(
      id: id is num ? '${id.toInt()}' : (id?.toString() ?? 'Unknown'),
      description: description,
      status: json['status']?.toString() ?? 'reported',
      priorityModelScore: _toDouble(json['priority_model_score']),
      vision: json['vision'] != null
          ? VisionInfo.fromJson(json['vision'] as Map<String, dynamic>)
          : null,
      priority: _toDouble(json['priority']),
      priorityLabel: json['priority_label'] as String?,
      priorityReasons: _stringList(json['priority_reasons']),
      masterId: json['master_id']?.toString(),
      clusterSize: (json['cluster_size'] as num?)?.toInt(),
      isMaster: json['is_master'] as bool?,
      analysis: AiAnalysis(
        category: _titleCase(json['category']?.toString()),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        severity: (json['severity']?.toString() ?? 'unknown').toUpperCase(),
        isDuplicate: json['duplicate'] as bool? ?? false,
        duplicateCount: (json['duplicate_count'] as num?)?.toInt() ?? 0,
        department: json['department']?.toString() ?? 'Unassigned',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'image_url': imageUrl,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'status': status,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'analysis': analysis?.toJson(),
        'vision': vision?.toJson(),
        'priority_model_score': priorityModelScore,
        'priority': priority,
        'priority_label': priorityLabel,
        'priority_reasons': priorityReasons,
        'master_id': masterId,
        'cluster_size': clusterSize,
        'is_master': isMaster,
      };

  /// Maps an item from `GET /api/my-reports/` to an [Issue].
  ///
  /// Tolerates both flattened analysis fields (`category`, `severity`,
  /// `duplicate_count`, …) and a nested `analysis` object.
  factory Issue.fromListJson(Map<String, dynamic> json) {
    final rawAnalysis = json['analysis'];
    final analysis = rawAnalysis is Map<String, dynamic>
        ? AiAnalysis.fromJson(rawAnalysis)
        : AiAnalysis(
            category: _titleCase(json['category']?.toString()),
            confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
            severity: (json['severity']?.toString() ?? 'unknown').toUpperCase(),
            isDuplicate: json['duplicate'] as bool? ?? false,
            duplicateCount: (json['duplicate_count'] as num?)?.toInt() ?? 0,
            department: json['department']?.toString() ?? 'Unassigned',
          );
    return Issue(
      id: json['id'].toString(),
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      address: json['address'] as String?,
      status: json['status']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      analysis: analysis,
      vision: json['vision'] != null
          ? VisionInfo.fromJson(json['vision'] as Map<String, dynamic>)
          : null,
      priorityModelScore: _toDouble(json['priority_model_score']),
      priority: _toDouble(json['priority']),
      priorityLabel: json['priority_label'] as String?,
      priorityReasons: _stringList(json['priority_reasons']),
      masterId: json['master_id']?.toString(),
      clusterSize: (json['cluster_size'] as num?)?.toInt(),
      isMaster: json['is_master'] as bool?,
      canDelete: json['can_delete'] as bool?,
      canEdit: json['can_edit'] as bool?,
    );
  }

  IssueStatus get statusEnum => IssueStatus.parse(status);
}

/// AI-sidecar insights for an issue. Every value is labelled with its real
/// provenance; nothing here should ever be shown as authoritative truth.
class VisionInfo {
  final String status; // ok | unavailable | not_analyzed
  final Map<String, String> models; // embedding / detection / classifier names
  final List<Detection> detections;
  final List<String> classifierLabels;
  final PriorityModelInfo? priorityModel;
  final List<String> notes;

  const VisionInfo({
    required this.status,
    this.models = const {},
    this.detections = const [],
    this.classifierLabels = const [],
    this.priorityModel,
    this.notes = const [],
  });

  bool get available => status == 'ok';

  factory VisionInfo.fromJson(Map<String, dynamic> json) {
    final modelsRaw = json['models'];
    final models = <String, String>{
      if (modelsRaw is Map<String, dynamic>)
        ...modelsRaw.map(
          (k, v) => MapEntry(k, v.toString()),
        ),
    };
    final detectionsRaw = json['detections'];
    final detections = detectionsRaw is List
        ? detectionsRaw
            .whereType<Map<String, dynamic>>()
            .map(Detection.fromJson)
            .toList()
        : const <Detection>[];
    final labels = json['classifier_labels'];
    return VisionInfo(
      status: json['status']?.toString() ?? 'unavailable',
      models: models,
      detections: detections,
      classifierLabels:
          labels is List ? labels.map((e) => e.toString()).toList() : const [],
      priorityModel: json['priority_model'] is Map<String, dynamic>
          ? PriorityModelInfo.fromJson(
              json['priority_model'] as Map<String, dynamic>)
          : null,
      notes: json['notes'] is List
          ? (json['notes'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'models': models,
        'detections': detections.map((d) => d.toJson()).toList(),
        'classifier_labels': classifierLabels,
        'priority_model': priorityModel?.toJson(),
        'notes': notes,
      };
}

class Detection {
  final String label;
  final double confidence;
  final List<double>? box;

  const Detection({
    required this.label,
    required this.confidence,
    this.box,
  });

  factory Detection.fromJson(Map<String, dynamic> json) {
    final boxRaw = json['box'];
    return Detection(
      label: json['label']?.toString() ?? 'object',
      confidence: ((json['confidence'] as num?)?.toDouble()) ?? 0.0,
      box: boxRaw is List
          ? boxRaw.whereType<num>().map((e) => e.toDouble()).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'confidence': confidence,
        'box': box,
      };
}

/// Advisory learned-priority estimate. Must always render next to its honest
/// note ("prototype") and never replace the rule-based [Issue.priority].
class PriorityModelInfo {
  final double? score;
  final String? label;
  final String? model;
  final String? honestNote;
  final Map<String, dynamic>? explanation;

  const PriorityModelInfo({
    this.score,
    this.label,
    this.model,
    this.honestNote,
    this.explanation,
  });

  factory PriorityModelInfo.fromJson(Map<String, dynamic> json) {
    return PriorityModelInfo(
      score: (json['score'] as num?)?.toDouble(),
      label: json['label']?.toString(),
      model: json['model']?.toString(),
      honestNote: json['honest_note']?.toString(),
      explanation: json['explanation'] is Map<String, dynamic>
          ? json['explanation'] as Map<String, dynamic>
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'score': score,
        'label': label,
        'model': model,
        'honest_note': honestNote,
        'explanation': explanation,
      };
}

double? _toDouble(dynamic value) => (value as num?)?.toDouble();

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((e) => e.toString())
      .toList(growable: false);
}

class AiAnalysis {
  final String category;
  final double confidence;
  final String severity;
  final bool isDuplicate;
  final int duplicateCount;
  final String department;

  const AiAnalysis({
    required this.category,
    required this.confidence,
    required this.severity,
    required this.isDuplicate,
    required this.duplicateCount,
    required this.department,
  });

  factory AiAnalysis.fromJson(Map<String, dynamic> json) {
    return AiAnalysis(
      category: json['category'] as String? ?? 'Unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      severity: json['severity'] as String? ?? 'LOW',
      isDuplicate: json['is_duplicate'] as bool? ?? false,
      duplicateCount: json['duplicate_count'] as int? ?? 0,
      department: json['department'] as String? ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'confidence': confidence,
        'severity': severity,
        'is_duplicate': isDuplicate,
        'duplicate_count': duplicateCount,
        'department': department,
      };
}

String _titleCase(String? value) {
  if (value == null || value.isEmpty) return 'Other';
  return value[0].toUpperCase() + value.substring(1);
}

/// Human-readable label for a status, shared by chips, timelines and
/// notification messages.
extension IssueStatusLabel on IssueStatus {
  String get label {
    switch (this) {
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

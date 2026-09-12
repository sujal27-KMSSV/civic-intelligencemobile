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
    );
  }

  IssueStatus get statusEnum => IssueStatus.parse(status);
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

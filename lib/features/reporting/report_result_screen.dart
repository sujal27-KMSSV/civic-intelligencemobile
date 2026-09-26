import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/issue.dart';
import '../../core/widgets/priority_chip.dart';
import 'report_draft_provider.dart';
import 'report_submission_provider.dart';
import 'widgets/report_photo_card.dart';

/// Shown immediately after the user taps Submit on the review screen.
///
/// Watches [reportSubmissionProvider] and renders the loading, API error and
/// Civic-analysis result states. Contains no network calls — the repository call
/// lives in the notifier.
class ReportResultScreen extends ConsumerStatefulWidget {
  const ReportResultScreen({super.key});

  @override
  ConsumerState<ReportResultScreen> createState() =>
      _ReportResultScreenState();
}

class _ReportResultScreenState extends ConsumerState<ReportResultScreen> {
  void _finish({required String path}) {
    ref.read(reportSubmissionProvider.notifier).reset();
    ref.read(reportDraftProvider.notifier).reset();
    Navigator.of(context).popUntil((route) => route.isFirst);
    context.go(path);
  }

  void _viewIssue() {
    final issue = ref.read(reportSubmissionProvider).issue;
    if (issue == null) return;
    ref.read(reportSubmissionProvider.notifier).reset();
    ref.read(reportDraftProvider.notifier).reset();
    Navigator.of(context).popUntil((route) => route.isFirst);
    // Landing on the home branch underneath makes the back arrow return to the
    // community feed instead of the half-finished report form.
    context.go('/');
    context.push('/issue/${issue.id}', extra: issue);
  }

  void _retry() {
    ref.read(reportSubmissionProvider.notifier).submit();
  }

  void _backToReview() {
    ref.read(reportSubmissionProvider.notifier).reset();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final submission = ref.watch(reportSubmissionProvider);

    return PopScope(
      // During submitting and failure the user may back out to the review
      // form; once a report is confirmed there is nothing to go back to (the
      // success screen's own buttons exit the flow).
      canPop: submission.phase != SubmitPhase.success,
      child: switch (submission.phase) {
        SubmitPhase.success => _ResultSuccess(
            issue: submission.issue!,
            onViewMyReports: () => _finish(path: '/my-reports'),
            onViewIssue: _viewIssue,
            onBackHome: () => _finish(path: '/'),
          ),
        SubmitPhase.failure => _ResultError(
            message: submission.errorMessage ?? 'Could not submit your report.',
            onRetry: _retry,
            onBack: _backToReview,
          ),
        SubmitPhase.submitting || SubmitPhase.idle => const _ResultLoading(),
      },
    );
  }
}

class _ResultLoading extends StatefulWidget {
  const _ResultLoading();

  @override
  State<_ResultLoading> createState() => _ResultLoadingState();
}

class _ResultLoadingState extends State<_ResultLoading> {
  static const List<String> _steps = [
    'Submitting your report…',
    'Uploading photo & details…',
    'Running rule-based civic checks…',
    'Still working… Finalizing the analysis.',
  ];

  Timer? _ticker;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 8), (_) {
      setState(() {
        if (_step < _steps.length - 1) _step++;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Submitted'),
        automaticallyImplyLeading: false,
        // Escape hatch for a slow / stalled submission: you can head back to
        // the review form while the submit keeps running in the background
        // (if the report lands, your My Reports will show it).
        leading: IconButton(
          tooltip: 'Back to review',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _steps[_step],
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 4),
              Text(
                'Keep the app open — this can take up to a minute.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultError extends StatelessWidget {
  const _ResultError({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Submitted'),
        automaticallyImplyLeading: false,
        // Mirror the loading-state close affordance so the failure screen is
        // never a dead end.
        leading: IconButton(
          tooltip: 'Back to review',
          icon: const Icon(Icons.close),
          onPressed: onBack,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 56, color: colors.error),
                const SizedBox(height: 16),
                Text(
                  "Couldn't submit your report",
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], height: 1.35),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onBack,
                  child: const Text('Back to Review'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultSuccess extends StatelessWidget {
  const _ResultSuccess({
    required this.issue,
    required this.onViewMyReports,
    required this.onViewIssue,
    required this.onBackHome,
  });

  final Issue issue;
  final VoidCallback onViewMyReports;
  final VoidCallback onViewIssue;
  final VoidCallback onBackHome;

  AiAnalysis get _analysis =>
      issue.analysis ??
      const AiAnalysis(
        category: 'Other',
        confidence: 0,
        severity: 'LOW',
        isDuplicate: false,
        duplicateCount: 0,
        department: 'Unassigned',
      );

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    final confidencePercent = (analysis.confidence * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Submitted'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Report ${issue.id} submitted',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Here is what the civic analysis found for your report.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  if (issue.imageUrl != null) ...[
                    const SizedBox(height: 20),
                    ReportPhotoCard(imagePath: issue.imageUrl!),
                  ],
                  const SizedBox(height: 20),
                  _AnalysisCard(
                    analysis: analysis,
                    confidencePercent: confidencePercent,
                  ),
                  if (issue.vision != null) ...[
                    const SizedBox(height: 12),
                    _AiTransparencyNote(issue: issue),
                  ],
                  if (issue.priority != null ||
                      issue.priorityLabel != null) ...[
                    const SizedBox(height: 12),
                    _PriorityCard(issue: issue),
                  ],
                  const SizedBox(height: 16),
                  if (analysis.isDuplicate)
                    _DuplicateBanner(count: analysis.duplicateCount)
                  else
                    const _NewIssueBanner(),
                  if (analysis.confidence < 0.70) ...[
                    const SizedBox(height: 12),
                    _LowConfidenceNote(percent: confidencePercent),
                  ],
                  const SizedBox(height: 16),
                  if (issue.address != null &&
                      issue.address!.trim().isNotEmpty) ...[
                    _DetailCard(
                      icon: Icons.location_on_outlined,
                      label: 'Address',
                      value: issue.address!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DetailCard(
                          icon: Icons.account_balance_outlined,
                          label: 'Responsible department',
                          value: analysis.department,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DetailCard(
                          icon: Icons.assignment_turned_in_outlined,
                          label: 'Status',
                          value: _statusLabel(issue.status),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: onViewIssue,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View Issue'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onViewMyReports,
                    icon: const Icon(Icons.list_alt),
                    label: const Text('View My Reports'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onBackHome,
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.analysis,
    required this.confidencePercent,
  });

  final AiAnalysis analysis;
  final int confidencePercent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconFor(analysis.category),
                size: 28,
                color: colors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      analysis.category,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              _SeverityBadge(severity: analysis.severity),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Text(
            'Similarity to existing reports',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$confidencePercent% similar',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: analysis.confidence.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiTransparencyNote extends StatelessWidget {
  const _AiTransparencyNote({required this.issue});

  final Issue issue;

  @override
  Widget build(BuildContext context) {
    final vision = issue.vision;
    if (vision == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;

    final summary = <String>[
      if (vision.models.isNotEmpty) vision.models.values.join(', '),
      if (vision.detections.isNotEmpty)
        '${vision.detections.length} object(s) detected',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            vision.available
                ? Icons.visibility_outlined
                : Icons.block_outlined,
            size: 18,
            color: colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vision.available
                      ? 'AI photo analysis (advisory)'
                      : 'AI photo analysis unavailable',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    summary,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  'Real models, all output labelled; never overrides the '
                  'explainable analysis above.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.issue});

  final Issue issue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final score = issue.priority;
    final reasons = issue.priorityReasons;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Explainable priority',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              PriorityChip(label: issue.priorityLabel),
            ],
          ),
          if (score != null) ...[
            const SizedBox(height: 10),
            Text(
              '${score.round()}/100',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: priorityColor(issue.priorityLabel),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reason,
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final supportingText = count > 0
        ? '$count supporting ${count == 1 ? 'report' : 'reports'}'
        : 'Similar reports are already being handled by the city.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.content_copy_outlined, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Possible duplicate',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  supportingText,
                  style: TextStyle(color: Colors.orange.shade800, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewIssueBanner extends StatelessWidget {
  const _NewIssueBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New issue',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No similar reports were found for this problem.',
                  style: TextStyle(color: Colors.green.shade800, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LowConfidenceNote extends StatelessWidget {
  const _LowConfidenceNote({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline, color: Colors.amber.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Low similarity ($percent%) — the analysis is not fully certain. '
              'A city team member will review it manually.',
              style: TextStyle(color: Colors.amber.shade900, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(String? status) {
  switch (status?.trim().toLowerCase()) {
    case 'reported' || 'submitted' || 'pending':
      return 'Reported';
    case 'in_review' || 'in-review' || 'reviewing':
      return 'In Review';
    case 'in_progress' || 'in-progress' || 'assigned':
      return 'In Progress';
    case 'resolved' || 'completed' || 'closed':
      return 'Resolved';
    default:
      return (status == null || status.trim().isEmpty) ? 'Reported' : status;
  }
}

Color _severityColor(String? severity) {
  switch (severity?.toUpperCase()) {
    case 'CRITICAL':
      return const Color(0xFFD32F2F);
    case 'HIGH':
      return const Color(0xFFEF6C00);
    case 'MEDIUM':
      return const Color(0xFFF9A825);
    case 'LOW':
      return const Color(0xFF2E7D32);
    default:
      return Colors.grey.shade700;
  }
}

IconData _iconFor(String category) {
  switch (category) {
    case 'Pothole':
      return Icons.speed_outlined;
    case 'Street Lighting':
      return Icons.light_outlined;
    case 'Garbage & Waste':
      return Icons.delete_outline;
    case 'Broken Footpath':
      return Icons.directions_walk_outlined;
    case 'Drainage / Sewage':
      return Icons.water_drop_outlined;
    case 'Traffic Signal':
      return Icons.traffic_outlined;
    case 'Illegal Dumping':
      return Icons.report_gmailerrorred_outlined;
    default:
      return Icons.category_outlined;
  }
}
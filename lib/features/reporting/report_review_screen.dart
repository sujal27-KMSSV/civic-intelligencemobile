import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'report_draft.dart';
import 'report_draft_provider.dart';
import 'report_result_screen.dart';
import 'report_submission_provider.dart';
import 'widgets/report_photo_card.dart';

/// Final step of the reporting flow: confirms the assembled draft and
/// submits it. Submission state (loading/success/error) is owned by
/// [reportSubmissionProvider] and rendered by [ReportResultScreen]; this
/// screen only watches the draft and triggers the submission.
class ReportReviewScreen extends ConsumerStatefulWidget {
  const ReportReviewScreen({super.key});

  @override
  ConsumerState<ReportReviewScreen> createState() =>
      _ReportReviewScreenState();
}

class _ReportReviewScreenState extends ConsumerState<ReportReviewScreen> {
  void _submit() {
    ref.read(reportSubmissionProvider.notifier).submit();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReportResultScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submission = ref.watch(reportSubmissionProvider);

    return PopScope(
      canPop: !submission.isSubmitting,
      child: _buildReview(submission),
    );
  }

  Widget _buildReview(ReportSubmissionState submission) {
    final draft = ref.watch(reportDraftProvider);
    final canSubmit = !submission.isSubmitting && draft.isReadyToSubmit;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Review Report')),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
              children: [
                if (!draft.isReadyToSubmit) ...[
                  _MissingBanner(draft: draft),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Check everything looks right before sending.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 20),
                if (draft.image != null)
                  ReportPhotoCard(imagePath: draft.image!.path),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                        icon: _iconFor(draft.category ?? 'Other'),
                        label: 'Category',
                        value: draft.category ?? 'Not selected',
                      ),
                      const Divider(height: 24),
                      _SummaryRow(
                        icon: Icons.place_outlined,
                        label: 'Location',
                        value: _locationLabel(draft),
                      ),
                      if (draft.accuracyInMeters != null) ...[
                        const Divider(height: 24),
                        _SummaryRow(
                          icon: Icons.speed_outlined,
                          label: 'Accuracy',
                          value:
                              '±${draft.accuracyInMeters!.toStringAsFixed(0)} m',
                        ),
                      ],
                      const Divider(height: 24),
                      _SummaryRow(
                        icon: Icons.notes_outlined,
                        label: 'Description',
                        value: _hasDescription(draft)
                            ? draft.description!
                            : 'No description added',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed:
                        canSubmit ? () => _submit() : null,
                    icon: submission.isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      submission.isSubmitting ? 'Submitting…' : 'Submit Report',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: submission.isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Edit Details'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasDescription(ReportDraft draft) =>
      draft.description != null && draft.description!.trim().isNotEmpty;

  String _locationLabel(ReportDraft draft) {
    if (draft.latitude == null || draft.longitude == null) {
      return 'Location not captured';
    }
    final address = draft.address;
    if (address != null && address.trim().isNotEmpty) return address;
    return '${draft.latitude!.toStringAsFixed(5)}, '
        '${draft.longitude!.toStringAsFixed(5)}';
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
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MissingBanner extends StatelessWidget {
  const _MissingBanner({required this.draft});

  final ReportDraft draft;

  @override
  Widget build(BuildContext context) {
    final missing = <String>[
      if (draft.category == null) 'category',
      if (draft.image == null) 'a photo',
      if (draft.latitude == null || draft.longitude == null) 'a location',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Missing: ${missing.join(', ')}. Go back to complete the report.',
            ),
          ),
        ],
      ),
    );
  }
}
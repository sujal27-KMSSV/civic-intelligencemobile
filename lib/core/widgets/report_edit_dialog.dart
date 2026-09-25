import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../features/reporting/report_repository.dart';
import '../../models/issue.dart';

/// Lets the citizen correct their own report's details.
///
/// Only the text the reporter is allowed to change (description, address) is
/// shown; coordinates, photo and the analysis are owned by the civic pipeline.
/// Returns the refreshed [Issue] from the backend, or `null` if the user
/// cancelled or the dialog failed (errors are shown inline inside the dialog).
Future<Issue?> showReportEditDialog(
  BuildContext context, {
  required ReportRepository repository,
  required Issue issue,
}) {
  final descriptionController =
      TextEditingController(text: issue.description ?? '');
  final addressController = TextEditingController(text: issue.address ?? '');
  String? error;
  var saving = false;

  return showDialog<Issue>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> save() async {
          setState(() {
            saving = true;
            error = null;
          });
          try {
            final updated = await repository.updateIssue(
              issue.id,
              description: descriptionController.text.trim(),
              address: addressController.text.trim(),
            );
            if (context.mounted) Navigator.of(context).pop(updated);
          } on AppException catch (e) {
            setState(() {
              saving = false;
              error = e.message;
            });
          } catch (_) {
            setState(() {
              saving = false;
              error = 'Could not update the report. Please try again.';
            });
          }
        }

        return AlertDialog(
          title: const Text('Edit report'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.id,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  enabled: !saving,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'What did you see?',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  enabled: !saving,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
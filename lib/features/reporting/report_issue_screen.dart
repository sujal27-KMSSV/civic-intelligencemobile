import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/location_service.dart';
import '../../services/media_service.dart';
import 'report_draft_provider.dart';
import 'report_review_screen.dart';

class ReportIssueScreen extends ConsumerStatefulWidget {
  const ReportIssueScreen({super.key});

  @override
  ConsumerState<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends ConsumerState<ReportIssueScreen> {
  final List<String> _commonIssues = [
    'Pothole',
    'Street Lighting',
    'Garbage & Waste',
    'Broken Footpath',
    'Drainage / Sewage',
    'Traffic Signal',
    'Illegal Dumping',
    'Other',
  ];

  bool _busy = false;
  bool _needsSettings = false;
  bool _busyLocation = false;
  bool _locationNeedsSettings = false;
  bool _locationServiceOff = false;

  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _descriptionFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final saved = ref.read(reportDraftProvider).description;
    if (saved != null && saved.isNotEmpty) {
      _descriptionController.text = saved;
    }
    _descriptionFocusNode.addListener(_onDescriptionFocusChanged);
  }

  @override
  void dispose() {
    _descriptionFocusNode.removeListener(_onDescriptionFocusChanged);
    _descriptionFocusNode.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Commits the description draft on focus loss instead of per keystroke,
  /// so typing in the field never rebuilds the whole screen.
  void _onDescriptionFocusChanged() {
    if (!_descriptionFocusNode.hasFocus) {
      _syncDescription();
    }
  }

  void _syncDescription() {
    final value = _descriptionController.text;
    final draft = ref.read(reportDraftProvider);
    if (draft.description == value) return;
    ref.read(reportDraftProvider.notifier).setDescription(value);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reportDraftProvider);
    ref.listen(reportDraftProvider, (previous, next) {
      if (next.description != _descriptionController.text) {
        _descriptionController.text = next.description ?? '';
      }
    });
    return PopScope(
      // Commit the description draft when the user leaves the screen (back
      // gesture / back button), since the field only syncs on focus loss.
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _syncDescription();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Report Issue')),
        body: SafeArea(
          child: Stack(
            children: [
              /// Scrollable content with a bottom offset for the action bar.
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  _StepIndicator(
                    firstDone: draft.category != null,
                    secondDone: draft.image != null,
                    thirdDone: draft.latitude != null,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'What did you find?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select an issue category, then add a photo.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final category in _commonIssues)
                        ChoiceChip(
                          label: Text(category),
                          selected: draft.category == category,
                          onSelected: (value) {
                            final notifier =
                                ref.read(reportDraftProvider.notifier);
                            notifier.selectCategory(value ? category : '');
                          },
                          avatar: Icon(
                            _iconFor(category),
                            size: 18,
                            color: draft.category == category
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer
                                : Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Text(
                        'Add a photo',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (draft.image == null)
                        Text(
                          'Step 2 of 3',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A clear photo speeds up review. You can retake it later.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  if (_needsSettings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _SettingsBanner(
                        onOpenSettings: () async {
                          await ref.read(mediaServiceProvider).openSettings();
                          setState(() => _needsSettings = false);
                        },
                      ),
                    ),
                  if (draft.image == null)
                    _PhotoPlaceholder(
                      busy: _busy,
                      onCapture: _handleCapture,
                      onGallery: _handleGallery,
                    )
                  else
                    _PhotoPreview(
                      imagePath: draft.image!.path,
                      busy: _busy,
                      onRetake: _handleCapture,
                      onGallery: _handleGallery,
                      onRemove: () {
                        ref.read(reportDraftProvider.notifier).clearImage();
                        setState(() => _needsSettings = false);
                      },
                    ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Text(
                        'Add location',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (draft.latitude == null)
                        Text(
                          'Step 3 of 3',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'GPS capture helps the city route your report to the right '
                    'ward.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  if (_locationNeedsSettings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _WarnBanner(
                        message:
                            'Location permission is blocked. Enable it in your '
                            'device settings to capture your position.',
                        actionLabel: 'Open Settings',
                        onAction: () async {
                          await ref
                              .read(locationServiceProvider)
                              .openAppSettings();
                          setState(() => _locationNeedsSettings = false);
                        },
                      ),
                    ),
                  if (_locationServiceOff)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _WarnBanner(
                        message:
                            'Location services are turned off. Turn them on '
                            'to capture your position.',
                        actionLabel: 'Open Location Settings',
                        onAction: () async {
                          await ref
                              .read(locationServiceProvider)
                              .openLocationSettings();
                          setState(() => _locationServiceOff = false);
                        },
                      ),
                    ),
                  if (draft.latitude == null)
                    _LocationPlaceholder(
                      busy: _busyLocation,
                      onCapture: _handleLocationCapture,
                    )
                  else
                    _LocationDisplay(
                      latitude: draft.latitude!,
                      longitude: draft.longitude!,
                      accuracy: draft.accuracyInMeters,
                      address: draft.address,
                      busy: _busyLocation,
                      onUpdate: _handleLocationCapture,
                      onRemove: () {
                        ref.read(reportDraftProvider.notifier).clearLocation();
                        setState(() {
                          _locationNeedsSettings = false;
                          _locationServiceOff = false;
                        });
                      },
                    ),
                  const SizedBox(height: 32),
                  Text(
                    'Add description',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Optional — tell officials what you noticed.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    focusNode: _descriptionFocusNode,
                    maxLines: 4,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'e.g. Large pothole near the crossing, '
                          'worsens after rain.',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),

              /// Bottom action bar.
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (draft.category != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${draft.category} selected',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : _primaryAction(
                              draft.category,
                              draft.image != null,
                              draft.latitude != null,
                            ),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_primaryIcon(
                              draft.category,
                              draft.image != null,
                              draft.latitude != null,
                            )),
                      label: Text(_primaryLabel(
                        draft.category,
                        draft.image != null,
                        draft.latitude != null,
                      )),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCapture() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref.read(mediaServiceProvider).capturePhoto();
    if (!mounted) return;
    setState(() => _busy = false);
    _applyResult(result);
  }

  Future<void> _handleGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref.read(mediaServiceProvider).pickFromGallery();
    if (!mounted) return;
    setState(() => _busy = false);
    _applyResult(result);
  }

  void _applyResult(MediaPickResult result) {
    final messenger = ScaffoldMessenger.of(context);
    switch (result.status) {
      case MediaPickStatus.success:
        ref.read(reportDraftProvider.notifier).setImage(result.file!);
        setState(() => _needsSettings = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Photo captured successfully')),
        );
      case MediaPickStatus.permissionDenied:
        setState(() => _needsSettings = true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Camera permission is needed to capture photos.'),
          ),
        );
      case MediaPickStatus.permanentlyDenied:
        setState(() => _needsSettings = true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Camera permission is blocked. Enable it in Settings to continue.',
            ),
          ),
        );
      case MediaPickStatus.cancelled:
        messenger.showSnackBar(
          const SnackBar(content: Text('Photo capture cancelled')),
        );
      case MediaPickStatus.unavailable:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ?? 'Could not access the camera right now.',
            ),
          ),
        );
    }
  }

  Future<void> _handleLocationCapture() async {
    if (_busyLocation) return;
    setState(() => _busyLocation = true);
    final result =
        await ref.read(locationServiceProvider).captureCurrentLocation();
    if (!mounted) return;
    setState(() => _busyLocation = false);
    _applyLocationResult(result);
  }

  void _applyLocationResult(LocationResult result) {
    final messenger = ScaffoldMessenger.of(context);
    switch (result.status) {
      case LocationStatus.success:
        ref.read(reportDraftProvider.notifier).setLocation(result.location!);
        setState(() {
          _locationNeedsSettings = false;
          _locationServiceOff = false;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Location captured successfully')),
        );
      case LocationStatus.permissionDenied:
        setState(() => _locationNeedsSettings = true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission is needed to find the issue location.',
            ),
          ),
        );
      case LocationStatus.permanentlyDenied:
        setState(() => _locationNeedsSettings = true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission is blocked. Enable it in Settings to '
              'continue.',
            ),
          ),
        );
      case LocationStatus.serviceDisabled:
        setState(() => _locationServiceOff = true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Location services are turned off.'),
          ),
        );
      case LocationStatus.timedOut:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not get your location. Try again in a moment.',
            ),
          ),
        );
      case LocationStatus.unavailable:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ?? 'Could not get your location right now.',
            ),
          ),
        );
    }
  }

  VoidCallback? _primaryAction(
      String? category, bool hasImage, bool hasLocation) {
    if (category == null) return null;
    if (!hasImage) return _handleCapture;
    if (!hasLocation) return _handleLocationCapture;
    return _openReview;
  }

  void _openReview() {
    _syncDescription();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReportReviewScreen()),
    );
  }

  IconData _primaryIcon(String? category, bool hasImage, bool hasLocation) {
    if (category == null) return Icons.category_outlined;
    if (!hasImage) return Icons.camera_alt_outlined;
    if (!hasLocation) return Icons.gps_fixed;
    return Icons.arrow_forward;
  }

  String _primaryLabel(String? category, bool hasImage, bool hasLocation) {
    if (category == null) return 'Select a category to continue';
    if (!hasImage) return 'Take a Photo';
    if (!hasLocation) return 'Add Location';
    return 'Review & Submit';
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

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({
    required this.busy,
    required this.onCapture,
    required this.onGallery,
  });

  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, size: 40, color: colors.primary),
              const SizedBox(height: 8),
              Text(
                'No photo yet',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                'Capture the issue as clearly as you can',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : onCapture,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Open Camera'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('From Gallery'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.imagePath,
    required this.busy,
    required this.onRetake,
    required this.onGallery,
    required this.onRemove,
  });

  final String imagePath;
  final bool busy;
  final VoidCallback onRetake;
  final VoidCallback onGallery;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              cacheWidth: 540,
              errorBuilder: (context, error, stack) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onRetake,
                icon: const Icon(Icons.refresh),
                label: const Text('Retake'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('From Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: busy ? null : onRemove,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove photo'),
          style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
        ),
      ],
    );
  }
}

class _SettingsBanner extends StatelessWidget {
  const _SettingsBanner({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.gpp_bad_outlined, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Camera access is blocked. Enable it in your device settings to '
              'take photos.',
            ),
          ),
          TextButton(
            onPressed: onOpenSettings,
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.firstDone,
    required this.secondDone,
    required this.thirdDone,
  });

  final bool firstDone;
  final bool secondDone;
  final bool thirdDone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepPill(
          label: 'Category',
          done: firstDone,
          active: !firstDone,
        ),
        const _StepConnector(),
        _StepPill(
          label: 'Photo',
          done: secondDone,
          active: firstDone && !secondDone,
        ),
        const _StepConnector(),
        _StepPill(
          label: 'Details',
          done: thirdDone,
          active: firstDone && secondDone && !thirdDone,
        ),
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill(
      {required this.label, required this.done, required this.active});

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final Color fg;
    final Color bg;
    if (done) {
      fg = colors.onPrimary;
      bg = colors.primary;
    } else if (active) {
      fg = colors.onSecondaryContainer;
      bg = colors.secondaryContainer;
    } else {
      fg = colors.onSurfaceVariant;
      bg = colors.surfaceContainerHighest;
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              done ? Icons.check_circle_outline : Icons.circle_outlined,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      active || done ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Icon(
        Icons.arrow_forward,
        size: 14,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _LocationPlaceholder extends StatelessWidget {
  const _LocationPlaceholder({
    required this.busy,
    required this.onCapture,
  });

  final bool busy;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.my_location, size: 40, color: colors.primary),
              const SizedBox(height: 8),
              Text(
                'No location yet',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                'Your position routes the report to the right ward',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: busy ? null : onCapture,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.gps_fixed),
          label: Text(busy ? 'Locating…' : 'Get My Location'),
        ),
      ],
    );
  }
}

class _LocationDisplay extends StatelessWidget {
  const _LocationDisplay({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.address,
    required this.busy,
    required this.onUpdate,
    required this.onRemove,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
  final String? address;
  final bool busy;
  final VoidCallback onUpdate;
  final VoidCallback onRemove;

  String get _label {
    if (address != null && address!.trim().isNotEmpty) return address!;
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  String get _detail {
    final parts = <String>[
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
    ];
    if (accuracy != null) {
      parts.add('Accuracy ±${accuracy!.toStringAsFixed(0)} m');
    }
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _detail,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onUpdate,
                  icon: const Icon(Icons.gps_fixed, size: 18),
                  label: const Text('Update'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: busy ? null : onRemove,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
                style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WarnBanner extends StatelessWidget {
  const _WarnBanner({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
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
          Expanded(child: Text(message)),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

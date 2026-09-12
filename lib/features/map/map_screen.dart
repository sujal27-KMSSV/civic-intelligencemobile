import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/severity_colors.dart';
import '../../core/widgets/severity_chip.dart';
import '../../core/widgets/status_chip.dart';
import '../../features/feed/issue_feed_repository.dart';
import '../../models/issue.dart';
import '../../services/location_service.dart';

/// Fallback viewport used until the device position is known.
const LatLng kDefaultMapCenter = LatLng(28.6139, 77.2090);

/// Interactive civic issues map.
///
/// UI only: markers come from the shared [issueFeedProvider], the user's
/// position from [currentLocationProvider], and detail navigation reuses the
/// issue route.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.tileProvider});

  /// Optional tile source override (used by tests to inject a fake HTTP
  /// client). When null, live OpenStreetMap tiles are used.
  final TileProvider? tileProvider;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  LatLng? _userLocation;
  bool _mapReady = false;
  bool _centeredOnUser = false;
  Issue? _selected;
  String? _locationNotice;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<LocationResult>>(
      currentLocationProvider,
      (_, next) {
        if (next.isLoading) return;
        next.when(
          data: (result) {
            final location = result.location;
            if (result.status == LocationStatus.success && location != null) {
              final latLng = LatLng(location.latitude, location.longitude);
              setState(() {
                _userLocation = latLng;
                _locationNotice = null;
              });
              if (!_centeredOnUser && mounted && _mapReady) {
                _mapController.move(latLng, 14);
                _centeredOnUser = true;
              }
            } else {
              setState(() {
                _locationNotice = result.errorMessage ??
                    _locationFailure(result.status);
              });
            }
          },
          error: (_, __) {
            setState(
              () => _locationNotice = 'Could not determine your location.',
            );
          },
          loading: () {},
        );
      },
    );
  }

  String _locationFailure(LocationStatus status) {
    switch (status) {
      case LocationStatus.permissionDenied:
        return 'Location permission denied.';
      case LocationStatus.permanentlyDenied:
        return 'Location permission is off. Enable it in settings.';
      case LocationStatus.serviceDisabled:
        return 'Location services are off.';
      case LocationStatus.timedOut:
        return 'Could not get your location. Try again.';
      case LocationStatus.unavailable:
      case LocationStatus.success:
        return 'Could not get your location.';
    }
  }

  void _centerOnUser() {
    final location = _userLocation;
    if (location != null) {
      if (_mapReady) _mapController.move(location, 15);
      return;
    }
    ref.invalidate(currentLocationProvider);
  }

  void _select(Issue issue) {
    setState(() {
      _selected = _selected?.id == issue.id ? null : issue;
    });
  }

  void _openDetails(Issue issue) {
    context.go('/issue/${issue.id}', extra: issue);
  }

  @override
  Widget build(BuildContext context) {
    final issuesAsync = ref.watch(issueFeedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Issue Map')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildMap(issuesAsync.valueOrNull ?? const [])),
          _buildTopOverlay(issuesAsync),
          if (_locationNotice != null)
            Positioned(
              top: 56,
              left: 12,
              right: 12,
              child: _MapNotice(
                icon: Icons.location_off_outlined,
                message: _locationNotice!,
              ),
            ),
          Positioned(
            left: 12,
            bottom: _selected == null ? 92 : 260,
            child: _Legend(),
          ),
          Positioned(
            right: 12,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: _centerOnUser,
              tooltip: 'My location',
              child: const Icon(Icons.my_location),
            ),
          ),
          if (_selected != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: _SelectedIssueCard(
                issue: _selected!,
                onClose: () => setState(() => _selected = null),
                onViewDetails: () => _openDetails(_selected!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(List<Issue> issues) {
    final markers = _markersFor(issues);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: kDefaultMapCenter,
        initialZoom: 13,
        minZoom: 3,
        maxZoom: 19,
        onMapReady: () => _mapReady = true,
        onTap: (_, __) {
          if (_selected != null) {
            setState(() => _selected = null);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.civicintelligence.civic_intelligence',
          tileProvider: widget.tileProvider,
        ),
        if (_userLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _userLocation!,
                width: 22,
                height: 22,
                child: const IgnorePointer(
                  child: _UserLocationMarker(
                    key: Key('user-location-marker'),
                  ),
                ),
              ),
            ],
          ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  List<Marker> _markersFor(List<Issue> issues) {
    return [
      for (final issue in issues)
        if (issue.latitude != null && issue.longitude != null)
          Marker(
            point: LatLng(issue.latitude!, issue.longitude!),
            width: 44,
            height: 44,
            child: _IssueMarker(
              issue: issue,
              selected: _selected?.id == issue.id,
              onTap: () => _select(issue),
            ),
          ),
    ];
  }

  Widget _buildTopOverlay(AsyncValue<List<Issue>> issuesAsync) {
    final issues = issuesAsync.valueOrNull;

    if (issuesAsync.isLoading && issues == null) {
      return _topNotice(
        icon: Icons.hourglass_top,
        message: 'Loading issues…',
      );
    }

    if (issuesAsync.hasError) {
      final message = issuesAsync.error.toString();
      return Positioned(
        top: 8,
        left: 12,
        right: 12,
        child: Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.cloud_off, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Could not load issues',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _friendlyError(message),
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(issueFeedProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (issues != null && issues.every((issue) =>
        issue.latitude == null || issue.longitude == null)) {
      return _topNotice(
        icon: Icons.place_outlined,
        message: 'No issues with locations in your area yet.',
      );
    }

    return const SizedBox.shrink();
  }

  Widget _topNotice({required IconData icon, required String message}) {
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: _MapNotice(icon: icon, message: message),
    );
  }

  String _friendlyError(String raw) {
    final cleaned = raw.replaceFirst('Exception: ', '').trim();
    if (cleaned.isEmpty) return 'Something went wrong.';
    return cleaned;
  }
}

class _IssueMarker extends StatelessWidget {
  final Issue issue;
  final bool selected;
  final VoidCallback onTap;

  const _IssueMarker({
    required this.issue,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = severityColor(issue.analysis?.severity);
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        Icons.location_on,
        size: 40,
        color: selected ? AppColors.primary : color,
        shadows: const [
          Shadow(color: Colors.black38, offset: Offset(0, 1), blurRadius: 3),
        ],
      ),
    );
  }
}

class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

class _SelectedIssueCard extends StatelessWidget {
  final Issue issue;
  final VoidCallback onClose;
  final VoidCallback onViewDetails;

  const _SelectedIssueCard({
    required this.issue,
    required this.onClose,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final analysis = issue.analysis;
    final category = analysis?.category ?? 'Other';

    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SeverityChip(
                  severity: analysis?.severity ?? 'Unknown',
                ),
                const SizedBox(width: 6),
                StatusChip(status: issue.statusEnum),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (issue.description != null &&
                issue.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  issue.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _locationLabel(issue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ),
                if ((analysis?.duplicateCount ?? 0) > 0) ...[
                  Icon(Icons.content_copy_outlined,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    '${analysis!.duplicateCount} duplicate'
                    '${analysis.duplicateCount == 1 ? '' : 's'}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onViewDetails,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View details'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _locationLabel(Issue issue) {
    final address = issue.address;
    if (address != null && address.trim().isNotEmpty) return address;
    if (issue.latitude != null && issue.longitude != null) {
      return '${issue.latitude!.toStringAsFixed(5)}, '
          '${issue.longitude!.toStringAsFixed(5)}';
    }
    return 'Location unavailable';
  }
}

class _MapNotice extends StatelessWidget {
  final IconData icon;
  final String message;

  const _MapNotice({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(message, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendItem(color: AppColors.critical, label: 'Critical'),
            _LegendItem(color: AppColors.high, label: 'High'),
            _LegendItem(color: AppColors.medium, label: 'Medium'),
            _LegendItem(color: AppColors.low, label: 'Low'),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
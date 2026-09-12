import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

import '../models/location_point.dart';

enum LocationStatus {
  success,
  permissionDenied,
  permanentlyDenied,
  serviceDisabled,
  timedOut,
  unavailable,
}

class LocationResult {
  const LocationResult._({required this.status, this.location, this.errorMessage});

  factory LocationResult.success(LocationPoint point) =>
      LocationResult._(status: LocationStatus.success, location: point);

  factory LocationResult.permissionDenied() =>
      const LocationResult._(status: LocationStatus.permissionDenied);

  factory LocationResult.permanentlyDenied() =>
      const LocationResult._(status: LocationStatus.permanentlyDenied);

  factory LocationResult.serviceDisabled() =>
      const LocationResult._(status: LocationStatus.serviceDisabled);

  factory LocationResult.timedOut() =>
      const LocationResult._(status: LocationStatus.timedOut);

  factory LocationResult.unavailable(String message) => LocationResult._(
      status: LocationStatus.unavailable, errorMessage: message);

  final LocationStatus status;
  final LocationPoint? location;
  final String? errorMessage;
}

class LocationService {
  static const _timeout = Duration(seconds: 20);

  /// Reads the device's current position and optionally resolves a readable
  /// address.
  ///
  /// [accuracy] and [resolveAddress] let callers trade precision for speed:
  /// the map only needs a coarse "where am I" marker, so it uses medium
  /// accuracy and skips reverse geocoding entirely; report capture keeps the
  /// highest accuracy with a full address.
  Future<LocationResult> captureCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    bool resolveAddress = true,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationResult.serviceDisabled();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return LocationResult.permissionDenied();
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationResult.permanentlyDenied();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: _timeout,
      );

      final point = LocationPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy.isFinite ? position.accuracy : null,
        address: resolveAddress
            ? await _reverseGeocode(position.latitude, position.longitude)
            : null,
        capturedAt: position.timestamp,
      );
      return LocationResult.success(point);
    } on TimeoutException {
      return LocationResult.timedOut();
    } on LocationServiceDisabledException {
      return LocationResult.serviceDisabled();
    } on PlatformException catch (e) {
      return LocationResult.unavailable(e.message ?? 'Location unavailable');
    } catch (e) {
      return LocationResult.unavailable(e.toString());
    }
  }

  Future<String?> _reverseGeocode(double latitude, double longitude) async {
    try {
      final places = await geocoding.placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (places.isEmpty) return null;
      final p = places.first;
      final parts = [
        p.street,
        p.subLocality,
        p.locality,
        p.administrativeArea,
        p.country,
      ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      // Reverse geocoding is best-effort; fall back to coordinates only.
      return null;
    }
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

/// The device's position as a one-shot read, tuned for map rendering:
/// balanced accuracy and no reverse geocode (the marker doesn't need a street
/// address). Report capture calls [LocationService.captureCurrentLocation]
/// directly with full accuracy.
final currentLocationProvider =
    FutureProvider<LocationResult>((ref) async {
  return ref
      .watch(locationServiceProvider)
      .captureCurrentLocation(
        accuracy: LocationAccuracy.medium,
        resolveAddress: false,
      );
});
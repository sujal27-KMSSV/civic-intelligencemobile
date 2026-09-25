import 'dart:io';
import 'dart:ui' show instantiateImageCodec;

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of a media picking attempt.
enum MediaPickStatus {
  success,
  permissionDenied,
  permanentlyDenied,
  cancelled,
  unavailable,
}

class MediaPickResult {
  const MediaPickResult._({
    required this.status,
    this.file,
    this.errorMessage,
    this.source,
  });

  factory MediaPickResult.success(File file, {String? source}) =>
      MediaPickResult._(
        status: MediaPickStatus.success,
        file: file,
        source: source,
      );

  factory MediaPickResult.permissionDenied() =>
      const MediaPickResult._(status: MediaPickStatus.permissionDenied);

  factory MediaPickResult.permanentlyDenied() =>
      const MediaPickResult._(status: MediaPickStatus.permanentlyDenied);

  factory MediaPickResult.cancelled() =>
      const MediaPickResult._(status: MediaPickStatus.cancelled);

  factory MediaPickResult.unavailable(String message) =>
      MediaPickResult._(status: MediaPickStatus.unavailable, errorMessage: message);

  final MediaPickStatus status;
  final File? file;
  final String? errorMessage;

  /// Provenance of the picked photo: "camera" or "gallery".
  final String? source;
}

/// Handles camera/gallery capture and permission requests.
///
/// Kept free of any UI concern so it can be unit-tested and swapped for a
/// custom in-app camera later without touching widgets.
class MediaService {
  MediaService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Requests camera permission, then opens the system camera.
  Future<MediaPickResult> capturePhoto() async {
    final permission = await Permission.camera.request();
    if (permission.isPermanentlyDenied) {
      return MediaPickResult.permanentlyDenied();
    }
    if (permission.isDenied) {
      return MediaPickResult.permissionDenied();
    }
    return _pick(ImageSource.camera);
  }

  /// Opens the system photo picker (no permission required on modern
  /// Android / iOS).
  Future<MediaPickResult> pickFromGallery() => _pick(ImageSource.gallery);

  Future<MediaPickResult> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
        requestFullMetadata: false,
      );
      if (picked == null) {
        return MediaPickResult.cancelled();
      }
      final file = await _compressIfLarge(File(picked.path));
      final dimensionError = await _dimensionError(file);
      if (dimensionError != null) {
        return MediaPickResult.unavailable(dimensionError);
      }
      return MediaPickResult.success(file, source: source.name);
    } on PlatformException catch (e) {
      return MediaPickResult.unavailable(e.message ?? 'Camera unavailable');
    } catch (e) {
      return MediaPickResult.unavailable(e.toString());
    }
  }

  static const int _compressThresholdBytes = 400 * 1024;

  /// Smallest accepted photo dimension (shorter side). Matches the backend
  /// guard so a photo that passes locally is never rejected remotely.
  static const int _minPickDimension = 320;

  /// Human, honest reason for rejecting a photo — no model/CV claims.
  static const String _photoRejectionMessage =
      'Please upload a clear photo of the reported civic issue.';

  /// Decodes the picked file and rejects blank/tiny/corrupt images locally,
  /// instead of letting an invalid photo fail only after a 2-minute upload.
  Future<String?> _dimensionError(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final decoded = frame.image;
      final width = decoded.width;
      final height = decoded.height;
      decoded.dispose();
      codec.dispose();
      if (file.lengthSync() == 0 ||
          width < _minPickDimension ||
          height < _minPickDimension) {
        return _photoRejectionMessage;
      }
      return null;
    } catch (_) {
      return _photoRejectionMessage;
    }
  }

  /// Recompresses picked photos that are larger than ~400KB (image_picker
  /// already caps width at 2048px), shrinking upload payloads. Returns the
  /// original file if compression fails or doesn't actually shrink it.
  Future<File> _compressIfLarge(File file) async {
    try {
      if (await file.length() <= _compressThresholdBytes) return file;
      final tempDir = await getTemporaryDirectory();
      final sourceBasename = p.basenameWithoutExtension(file.path);
      final outPath = p.join(tempDir.path, '${sourceBasename}_compressed.jpg');
      final result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        outPath,
        quality: 72,
      );
      if (result == null) return file;
      final compressed = File(result.path);
      if (await compressed.length() >= await file.length()) return file;
      return compressed;
    } catch (_) {
      return file;
    }
  }

  Future<void> openSettings() async {
  await openAppSettings();
}
}

final mediaServiceProvider = Provider<MediaService>((ref) => MediaService());
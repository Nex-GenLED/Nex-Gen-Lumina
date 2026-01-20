import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Service for handling house photo uploads to Firebase Storage.
///
/// Provides methods to:
/// - Pick images from camera or gallery
/// - Compress images before upload
/// - Upload to Firebase Storage
/// - Return download URLs for profile storage
class ImageUploadService {
  final FirebaseStorage _storage;
  final ImagePicker _picker;

  ImageUploadService({
    FirebaseStorage? storage,
    ImagePicker? picker,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _picker = picker ?? ImagePicker();

  /// Pick an image from the specified source and upload it.
  /// Returns the download URL on success, null on failure or cancellation.
  Future<String?> pickAndUploadHousePhoto(
    String userId, {
    ImageSource source = ImageSource.gallery,
  }) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        debugPrint('ImageUploadService: User cancelled image picker');
        return null;
      }

      final bytes = await pickedFile.readAsBytes();
      return await uploadImage(userId, bytes);
    } catch (e, stackTrace) {
      debugPrint('ImageUploadService: Failed to pick/upload image: $e');
      debugPrint('ImageUploadService: Stack trace: $stackTrace');
      // Rethrow so the caller can handle it with a proper error message
      rethrow;
    }
  }

  /// Upload raw image bytes to Firebase Storage.
  /// Returns the download URL on success, null on failure.
  Future<String?> uploadImage(String userId, Uint8List bytes) async {
    try {
      // Compress the image if it's too large
      final compressedBytes = await _compressImage(bytes);

      final ref = _storage.ref().child('users/$userId/house_photo.jpg');

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      final uploadTask = ref.putData(compressedBytes, metadata);

      // Monitor upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        debugPrint('ImageUploadService: Upload progress: ${(progress * 100).toStringAsFixed(1)}%');
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint('ImageUploadService: Upload complete, URL: $downloadUrl');
      return downloadUrl;
    } catch (e, stackTrace) {
      debugPrint('ImageUploadService: Upload failed: $e');
      debugPrint('ImageUploadService: Stack trace: $stackTrace');
      // Rethrow so the caller can handle it with a proper error message
      rethrow;
    }
  }

  /// Delete the user's house photo from Firebase Storage.
  Future<bool> deleteHousePhoto(String userId) async {
    try {
      final ref = _storage.ref().child('users/$userId/house_photo.jpg');
      await ref.delete();
      debugPrint('ImageUploadService: Deleted house photo for user $userId');
      return true;
    } catch (e) {
      debugPrint('ImageUploadService: Failed to delete house photo: $e');
      return false;
    }
  }

  /// Compress image bytes to reduce file size.
  /// Note: image_picker already handles compression via maxWidth/maxHeight/imageQuality
  /// parameters, so this method simply passes through the bytes and logs the size.
  Future<Uint8List> _compressImage(Uint8List bytes) async {
    // image_picker already compresses with maxWidth: 1920, maxHeight: 1080, imageQuality: 85
    // No additional compression needed - just log and return
    debugPrint('ImageUploadService: Image size ${bytes.length} bytes (${(bytes.length / 1024).toStringAsFixed(1)} KB)');
    return bytes;
  }

  /// Get the current house photo URL for a user (if exists).
  Future<String?> getHousePhotoUrl(String userId) async {
    try {
      final ref = _storage.ref().child('users/$userId/house_photo.jpg');
      return await ref.getDownloadURL();
    } catch (e) {
      // File doesn't exist or other error
      return null;
    }
  }
}

/// Provider for ImageUploadService
final imageUploadServiceProvider = Provider<ImageUploadService>((ref) {
  return ImageUploadService();
});

/// State for tracking upload progress
class UploadProgress {
  final bool isUploading;
  final double progress;
  final String? error;
  final String? downloadUrl;

  const UploadProgress({
    this.isUploading = false,
    this.progress = 0.0,
    this.error,
    this.downloadUrl,
  });

  UploadProgress copyWith({
    bool? isUploading,
    double? progress,
    String? error,
    String? downloadUrl,
  }) {
    return UploadProgress(
      isUploading: isUploading ?? this.isUploading,
      progress: progress ?? this.progress,
      error: error,
      downloadUrl: downloadUrl ?? this.downloadUrl,
    );
  }
}

/// Notifier for managing upload state
class UploadProgressNotifier extends Notifier<UploadProgress> {
  @override
  UploadProgress build() => const UploadProgress();

  void startUpload() {
    state = const UploadProgress(isUploading: true, progress: 0.0);
  }

  void updateProgress(double progress) {
    state = state.copyWith(progress: progress);
  }

  void completeUpload(String downloadUrl) {
    state = UploadProgress(
      isUploading: false,
      progress: 1.0,
      downloadUrl: downloadUrl,
    );
  }

  void failUpload(String error) {
    state = UploadProgress(
      isUploading: false,
      progress: 0.0,
      error: error,
    );
  }

  void reset() {
    state = const UploadProgress();
  }
}

/// Provider for upload progress state
final uploadProgressProvider = NotifierProvider<UploadProgressNotifier, UploadProgress>(() {
  return UploadProgressNotifier();
});

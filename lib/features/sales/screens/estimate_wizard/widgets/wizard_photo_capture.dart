import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:nexgen_command/theme.dart';

/// Pick an image from camera or gallery, upload to Firebase Storage at
/// `sales_jobs/{jobId}/wizard/{subPath}`, and return the download URL.
///
/// Returns null if the user cancels or the upload fails.
Future<String?> pickAndUploadWizardPhoto({
  required BuildContext context,
  required String jobId,
  required String subPath,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: NexGenPalette.gunmetal,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera, color: NexGenPalette.cyan),
            title: const Text(
              'Take photo',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: NexGenPalette.cyan),
            title: const Text(
              'Choose from gallery',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );

  if (source == null) return null;

  final picker = ImagePicker();
  final image = await picker.pickImage(
    source: source,
    maxWidth: 1920,
    maxHeight: 1080,
    imageQuality: 85,
  );
  if (image == null) return null;

  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref().child(
          'sales_jobs/$jobId/wizard/${subPath}_$timestamp.jpg',
        );
    final bytes = await image.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo upload failed: $e')),
      );
    }
    return null;
  }
}

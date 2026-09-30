import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

// +110 package E2, audit rows 113 and 123 — what to say when the microphone
// cannot be used. Shared by the Design Studio's voice button and both Lumina
// surfaces so the three say the same thing.

/// Why the microphone cannot be used right now.
enum MicUnavailableReason {
  /// The customer denied microphone access; the fix is in Settings.
  permissionDenied,

  /// Speech recognition is not available on this device at all.
  notAvailable,
}

/// The sentence for a [MicUnavailableReason]. Pure, so it is testable.
String micUnavailableMessage(MicUnavailableReason reason) => switch (reason) {
      MicUnavailableReason.permissionDenied =>
        'Microphone access is off — enable it in Settings to talk to Lumina.',
      MicUnavailableReason.notAvailable =>
        'Mic unavailable — voice input is not available on this device. '
            'You can still type.',
    };

/// Tells a denied permission apart from a device that has no speech
/// recognition. [hasPermission] is what the speech plugin reports AFTER a
/// failed initialize; [lastError] is its last error code, if any.
MicUnavailableReason classifyMicFailure({
  required bool hasPermission,
  String? lastError,
}) {
  final err = (lastError ?? '').toLowerCase();
  if (!hasPermission || err.contains('permission') || err.contains('denied')) {
    return MicUnavailableReason.permissionDenied;
  }
  return MicUnavailableReason.notAvailable;
}

/// Shows the toast for [reason]. A denied permission gets a Settings action.
void showMicUnavailableSnackBar(BuildContext context, MicUnavailableReason reason) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(micUnavailableMessage(reason)),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 6),
        action: reason == MicUnavailableReason.permissionDenied
            ? SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () {
                  ph.openAppSettings();
                },
              )
            : null,
      ),
    );
}

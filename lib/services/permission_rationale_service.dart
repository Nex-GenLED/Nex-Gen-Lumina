import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for explaining why permissions are needed before requesting them
///
/// SECURITY & PRIVACY:
/// - Shows clear explanations before requesting permissions
/// - Helps users understand data usage
/// - Complies with Android 12+ permission best practices
class PermissionRationaleService {
  /// Show rationale dialog for location permission
  static Future<bool> showLocationRationale(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.cyan),
            SizedBox(width: 12),
            Text('Location Permission'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lumina needs location access for:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _PermissionReason(
              icon: Icons.wifi,
              title: 'Network Discovery',
              description: 'Find your WLED controllers on your local WiFi network',
            ),
            SizedBox(height: 8),
            _PermissionReason(
              icon: Icons.location_city,
              title: 'Geofencing',
              description: 'Automatically control lights when you arrive home or leave',
            ),
            SizedBox(height: 8),
            _PermissionReason(
              icon: Icons.wb_sunny,
              title: 'Sunrise/Sunset',
              description: 'Calculate accurate sun times for your schedules',
            ),
            SizedBox(height: 16),
            Text(
              '🔒 Privacy: Your location is stored locally and used only for these features.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// Show rationale dialog for background location permission
  static Future<bool> showBackgroundLocationRationale(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gps_fixed, color: Colors.orange),
            SizedBox(width: 12),
            Text('Background Location'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Background location enables:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _PermissionReason(
              icon: Icons.home_work,
              title: 'Arrival/Departure Automation',
              description: 'Turn lights on when you arrive home, off when you leave',
            ),
            SizedBox(height: 16),
            Text(
              '⚠️ This requires "Allow all the time" location access.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 8),
            Text(
              '🔒 Privacy: Location is only checked when entering/leaving your defined geofence area.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// Show rationale dialog for camera permission
  static Future<bool> showCameraRationale(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.camera_alt, color: Colors.cyan),
            SizedBox(width: 12),
            Text('Camera Permission'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Camera access is used for:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _PermissionReason(
              icon: Icons.photo_camera,
              title: 'House Photo',
              description: 'Take a photo of your house for the AR Preview feature',
            ),
            SizedBox(height: 8),
            _PermissionReason(
              icon: Icons.view_in_ar,
              title: 'AR Pattern Preview',
              description: 'See lighting patterns overlaid on your house in real-time',
            ),
            SizedBox(height: 16),
            Text(
              '🔒 Privacy: Photos are stored locally on your device and never uploaded without your permission.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// Show rationale dialog for microphone permission
  static Future<bool> showMicrophoneRationale(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.mic, color: Colors.cyan),
            SizedBox(width: 12),
            Text('Microphone Permission'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Microphone access enables:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _PermissionReason(
              icon: Icons.mic_none,
              title: 'Voice Commands',
              description: 'Control your lights with voice ("Lumina, turn on the lights")',
            ),
            SizedBox(height: 8),
            _PermissionReason(
              icon: Icons.chat_bubble_outline,
              title: 'Lumina AI Chat',
              description: 'Talk to Lumina AI instead of typing',
            ),
            SizedBox(height: 16),
            Text(
              '🔒 Privacy: Voice is processed locally on your device, not recorded or stored.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// Show rationale dialog for Bluetooth permission
  static Future<bool> showBluetoothRationale(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bluetooth, color: Colors.cyan),
            SizedBox(width: 12),
            Text('Bluetooth Permission'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bluetooth is used for:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _PermissionReason(
              icon: Icons.settings_input_antenna,
              title: 'Controller Setup',
              description: 'Connect to new WLED controllers and configure their WiFi settings',
            ),
            SizedBox(height: 8),
            _PermissionReason(
              icon: Icons.router,
              title: 'BLE Provisioning',
              description: 'Set up controllers without needing to know your WiFi password on the device',
            ),
            SizedBox(height: 16),
            Text(
              '🔒 Privacy: Bluetooth is only used during initial controller setup.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// Request permission with rationale
  ///
  /// Shows explanation dialog first, then requests permission if user agrees
  static Future<PermissionStatus> requestWithRationale(
    BuildContext context,
    Permission permission,
  ) async {
    // Check current status
    final status = await permission.status;
    if (status.isGranted) {
      return status;
    }

    // Show appropriate rationale
    bool shouldRequest = false;
    if (permission == Permission.location || permission == Permission.locationWhenInUse) {
      shouldRequest = await showLocationRationale(context);
    } else if (permission == Permission.locationAlways) {
      shouldRequest = await showBackgroundLocationRationale(context);
    } else if (permission == Permission.camera) {
      shouldRequest = await showCameraRationale(context);
    } else if (permission == Permission.microphone) {
      shouldRequest = await showMicrophoneRationale(context);
    } else if (permission == Permission.bluetooth || permission == Permission.bluetoothScan) {
      shouldRequest = await showBluetoothRationale(context);
    } else {
      // For other permissions, request directly
      shouldRequest = true;
    }

    if (!shouldRequest) {
      return PermissionStatus.denied;
    }

    // Request the permission
    return await permission.request();
  }

  /// Show settings dialog if permission is permanently denied
  static Future<void> showSettingsDialog(
    BuildContext context,
    String permissionName,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$permissionName Required'),
        content: Text(
          'Please enable $permissionName in your device settings to use this feature.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

/// Widget for displaying permission reason with icon
class _PermissionReason extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _PermissionReason({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.cyan),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                description,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

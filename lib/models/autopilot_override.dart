import 'package:uuid/uuid.dart';

/// Sources that can request an override of the autopilot scheduler.
enum OverrideSource {
  sportsScoreAlert,
  manualUser,
  geofence,
}

/// An ephemeral token granting temporary control of the WLED device
/// while the autopilot scheduler is paused.
///
/// Created by [AutopilotScheduler.requestOverride] and consumed by
/// [AutopilotScheduler.releaseOverride]. Lives only in memory — no
/// Firestore persistence needed.
class OverrideToken {
  final String id;
  final OverrideSource source;
  final Duration duration;
  final DateTime grantedAt;

  /// WLED device state captured at the moment the override was granted.
  /// Used by the scheduler to restore state when the override ends.
  final Map<String, dynamic>? capturedState;

  OverrideToken({
    String? id,
    required this.source,
    required this.duration,
    this.capturedState,
  })  : id = id ?? const Uuid().v4(),
        grantedAt = DateTime.now();

  DateTime get expiresAt => grantedAt.add(duration);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

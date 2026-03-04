/// Types of entries in the autopilot activity log.
enum ActivityEntryType {
  patternApplied,
  overrideStarted,
  overrideEnded,
  gameDetected,
  backgroundServiceActivated,
  preGameLightingApplied,
}

/// A single entry in the autopilot decision / activity log.
///
/// Ephemeral — kept in memory for the current session only,
/// surfaced in the autopilot UI so users can see what decisions
/// the scheduler is making.
class AutopilotActivityEntry {
  final DateTime timestamp;
  final ActivityEntryType type;
  final String source;
  final String message;
  final Map<String, dynamic>? metadata;

  const AutopilotActivityEntry({
    required this.timestamp,
    required this.type,
    required this.source,
    required this.message,
    this.metadata,
  });
}

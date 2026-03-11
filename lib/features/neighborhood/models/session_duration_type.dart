import '../models/sync_event.dart';

/// Duration classification for sync sessions.
///
/// Short-form events (under 8 hours) automatically take temporary priority
/// over long-form events (over 24 hours). Manual priority ranking only
/// applies to conflicts between events of the same duration type.
enum SessionDurationType {
  /// Under 8 hours — Game Day, short custom events.
  shortForm,

  /// Over 24 hours — Holiday, Seasonal, General.
  longForm,
}

extension SessionDurationTypeX on SessionDurationType {
  String get displayName {
    switch (this) {
      case SessionDurationType.shortForm:
        return 'Short-form';
      case SessionDurationType.longForm:
        return 'Long-form';
    }
  }

  String toJson() => name;

  static SessionDurationType fromJson(String? value) {
    if (value == null) return SessionDurationType.longForm;
    return SessionDurationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SessionDurationType.longForm,
    );
  }
}

/// Determines the [SessionDurationType] for a sync event automatically
/// based on its category and optional explicit duration.
///
/// Rules:
///   - gameDay → always shortForm
///   - customEvent → shortForm if duration < 8 hours, else longForm
///   - holiday / seasonal / general → always longForm
SessionDurationType classifySessionDuration({
  required SyncEventCategory category,
  Duration? eventDuration,
}) {
  switch (category) {
    case SyncEventCategory.gameDay:
      return SessionDurationType.shortForm;
    case SyncEventCategory.customEvent:
      if (eventDuration != null && eventDuration.inHours < 8) {
        return SessionDurationType.shortForm;
      }
      return SessionDurationType.longForm;
    case SyncEventCategory.holiday:
      return SessionDurationType.longForm;
  }
}

/// Extension on [SyncEventCategory] for default duration classification.
extension SyncEventCategoryDuration on SyncEventCategory {
  /// The default duration type for this category (without explicit duration).
  SessionDurationType get defaultDurationType {
    return classifySessionDuration(category: this);
  }
}

/// Returns true if a short-form event should automatically override
/// a long-form event (duration-aware priority logic).
///
/// - Short vs Long → short wins (automatic)
/// - Short vs Short → use manual rank
/// - Long vs Long → use manual rank
bool shouldAutoOverride({
  required SessionDurationType incoming,
  required SessionDurationType active,
}) {
  return incoming == SessionDurationType.shortForm &&
      active == SessionDurationType.longForm;
}

/// Returns true if both events are the same duration type,
/// meaning manual priority ranking should be used.
bool requiresManualPriorityRank({
  required SessionDurationType a,
  required SessionDurationType b,
}) {
  return a == b;
}

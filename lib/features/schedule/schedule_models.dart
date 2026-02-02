import 'package:flutter/foundation.dart';

/// Represents a single automation schedule for lights/patterns.
///
/// Each schedule has an "on" time when the pattern/action starts
/// and an optional "off" time when the lights turn off.
///
/// The [wledPayload] field stores the actual WLED JSON state to apply
/// (effects, colors, brightness, etc.). This is saved as a preset on the
/// device so that WLED timers can reliably trigger the intended state.
class ScheduleItem {
  final String id;
  /// Display label for ON time, e.g., "7:00 PM" or "Sunset".
  final String timeLabel;
  /// Display label for OFF time, e.g., "11:00 PM" or "Sunrise". Null if no off time.
  final String? offTimeLabel;
  /// Abbreviated repeat days, e.g., ["Mon","Wed","Fri"].
  final List<String> repeatDays;
  /// Action label, e.g., "Pattern: Candy Cane" or "Turn Off".
  final String actionLabel;
  final bool enabled;

  /// The actual WLED JSON payload to apply when this schedule triggers.
  /// Contains effect IDs, colors, brightness, segment configuration, etc.
  /// When null, the schedule will use legacy preset-based behavior.
  final Map<String, dynamic>? wledPayload;

  /// The preset ID assigned to this schedule (10-250).
  /// WLED timers reference this preset ID to load the saved state.
  /// Assigned automatically during sync if not set.
  final int? presetId;

  const ScheduleItem({
    required this.id,
    required this.timeLabel,
    this.offTimeLabel,
    required this.repeatDays,
    required this.actionLabel,
    required this.enabled,
    this.wledPayload,
    this.presetId,
  });

  /// Returns true if this schedule has an off time configured.
  bool get hasOffTime => offTimeLabel != null && offTimeLabel!.isNotEmpty;

  /// Returns true if this schedule has a WLED payload to apply.
  bool get hasWledPayload => wledPayload != null && wledPayload!.isNotEmpty;

  ScheduleItem copyWith({
    String? id,
    String? timeLabel,
    String? offTimeLabel,
    bool clearOffTime = false,
    List<String>? repeatDays,
    String? actionLabel,
    bool? enabled,
    Map<String, dynamic>? wledPayload,
    bool clearWledPayload = false,
    int? presetId,
    bool clearPresetId = false,
  }) =>
      ScheduleItem(
        id: id ?? this.id,
        timeLabel: timeLabel ?? this.timeLabel,
        offTimeLabel: clearOffTime ? null : (offTimeLabel ?? this.offTimeLabel),
        repeatDays: repeatDays ?? this.repeatDays,
        actionLabel: actionLabel ?? this.actionLabel,
        enabled: enabled ?? this.enabled,
        wledPayload: clearWledPayload ? null : (wledPayload ?? this.wledPayload),
        presetId: clearPresetId ? null : (presetId ?? this.presetId),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timeLabel': timeLabel,
        if (offTimeLabel != null) 'offTimeLabel': offTimeLabel,
        'repeatDays': repeatDays,
        'actionLabel': actionLabel,
        'enabled': enabled,
        if (wledPayload != null) 'wledPayload': wledPayload,
        if (presetId != null) 'presetId': presetId,
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        id: json['id'] as String,
        timeLabel: json['timeLabel'] as String,
        offTimeLabel: json['offTimeLabel'] as String?,
        repeatDays: (json['repeatDays'] as List).map((e) => e.toString()).toList(),
        actionLabel: json['actionLabel'] as String,
        enabled: json['enabled'] as bool,
        wledPayload: json['wledPayload'] as Map<String, dynamic>?,
        presetId: json['presetId'] as int?,
      );

  @override
  String toString() => describeIdentity(this);
}

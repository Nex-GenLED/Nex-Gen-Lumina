import 'package:flutter/foundation.dart';

/// Represents a single automation schedule for lights/patterns.
///
/// Each schedule has an "on" time when the pattern/action starts
/// and an optional "off" time when the lights turn off.
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

  const ScheduleItem({
    required this.id,
    required this.timeLabel,
    this.offTimeLabel,
    required this.repeatDays,
    required this.actionLabel,
    required this.enabled,
  });

  /// Returns true if this schedule has an off time configured.
  bool get hasOffTime => offTimeLabel != null && offTimeLabel!.isNotEmpty;

  ScheduleItem copyWith({
    String? id,
    String? timeLabel,
    String? offTimeLabel,
    bool clearOffTime = false,
    List<String>? repeatDays,
    String? actionLabel,
    bool? enabled,
  }) =>
      ScheduleItem(
        id: id ?? this.id,
        timeLabel: timeLabel ?? this.timeLabel,
        offTimeLabel: clearOffTime ? null : (offTimeLabel ?? this.offTimeLabel),
        repeatDays: repeatDays ?? this.repeatDays,
        actionLabel: actionLabel ?? this.actionLabel,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timeLabel': timeLabel,
        if (offTimeLabel != null) 'offTimeLabel': offTimeLabel,
        'repeatDays': repeatDays,
        'actionLabel': actionLabel,
        'enabled': enabled,
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        id: json['id'] as String,
        timeLabel: json['timeLabel'] as String,
        offTimeLabel: json['offTimeLabel'] as String?,
        repeatDays: (json['repeatDays'] as List).map((e) => e.toString()).toList(),
        actionLabel: json['actionLabel'] as String,
        enabled: json['enabled'] as bool,
      );

  @override
  String toString() => describeIdentity(this);
}

import 'package:flutter/foundation.dart';

/// Represents a single automation schedule for lights/patterns.
class ScheduleItem {
  final String id;
  /// Display label for time, e.g., "7:00 PM" or "Sunset".
  final String timeLabel;
  /// Abbreviated repeat days, e.g., ["Mon","Wed","Fri"].
  final List<String> repeatDays;
  /// Action label, e.g., "Pattern: Candy Cane" or "Turn Off".
  final String actionLabel;
  final bool enabled;

  const ScheduleItem({required this.id, required this.timeLabel, required this.repeatDays, required this.actionLabel, required this.enabled});

  ScheduleItem copyWith({String? id, String? timeLabel, List<String>? repeatDays, String? actionLabel, bool? enabled}) => ScheduleItem(
        id: id ?? this.id,
        timeLabel: timeLabel ?? this.timeLabel,
        repeatDays: repeatDays ?? this.repeatDays,
        actionLabel: actionLabel ?? this.actionLabel,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timeLabel': timeLabel,
        'repeatDays': repeatDays,
        'actionLabel': actionLabel,
        'enabled': enabled,
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        id: json['id'] as String,
        timeLabel: json['timeLabel'] as String,
        repeatDays: (json['repeatDays'] as List).map((e) => e.toString()).toList(),
        actionLabel: json['actionLabel'] as String,
        enabled: json['enabled'] as bool,
      );

  @override
  String toString() => describeIdentity(this);
}

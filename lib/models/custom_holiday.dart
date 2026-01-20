import 'package:flutter/material.dart';

/// User-defined custom holiday for Autopilot scheduling.
///
/// Allows users to add personal events (birthdays, anniversaries, religious
/// holidays) that aren't in the US Federal Holiday calendar.
class CustomHoliday {
  final String id;
  final String name;
  final int month; // 1-12
  final int day; // 1-31
  final bool recurring; // true = repeats every year
  final List<Color>? suggestedColors;
  final int? suggestedEffectId;

  const CustomHoliday({
    required this.id,
    required this.name,
    required this.month,
    required this.day,
    this.recurring = true,
    this.suggestedColors,
    this.suggestedEffectId,
  });

  /// Check if this holiday falls on a specific date
  bool isOnDate(DateTime date) {
    if (recurring) {
      return date.month == month && date.day == day;
    } else {
      // For non-recurring, we'd need to store the year too
      // For now, treat all as recurring
      return date.month == month && date.day == day;
    }
  }

  /// Get the next occurrence of this holiday from a reference date
  DateTime getNextOccurrence(DateTime from) {
    var nextDate = DateTime(from.year, month, day);
    if (nextDate.isBefore(from) || nextDate.isAtSameMomentAs(from)) {
      nextDate = DateTime(from.year + 1, month, day);
    }
    return nextDate;
  }

  factory CustomHoliday.fromJson(Map<String, dynamic> json) {
    return CustomHoliday(
      id: json['id'] as String? ?? '',
      name: json['name'] as String,
      month: (json['month'] as num).toInt(),
      day: (json['day'] as num).toInt(),
      recurring: (json['recurring'] as bool?) ?? true,
      suggestedColors: (json['suggested_colors'] as List?)
          ?.map((c) => Color((c as num).toInt()))
          .toList(),
      suggestedEffectId: (json['suggested_effect_id'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'month': month,
      'day': day,
      'recurring': recurring,
      if (suggestedColors != null)
        'suggested_colors': suggestedColors!.map((c) => c.value).toList(),
      if (suggestedEffectId != null) 'suggested_effect_id': suggestedEffectId,
    };
  }

  CustomHoliday copyWith({
    String? id,
    String? name,
    int? month,
    int? day,
    bool? recurring,
    List<Color>? suggestedColors,
    int? suggestedEffectId,
  }) {
    return CustomHoliday(
      id: id ?? this.id,
      name: name ?? this.name,
      month: month ?? this.month,
      day: day ?? this.day,
      recurring: recurring ?? this.recurring,
      suggestedColors: suggestedColors ?? this.suggestedColors,
      suggestedEffectId: suggestedEffectId ?? this.suggestedEffectId,
    );
  }

  @override
  String toString() => 'CustomHoliday($name, $month/$day)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomHoliday &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          month == other.month &&
          day == other.day;

  @override
  int get hashCode => Object.hash(id, name, month, day);
}

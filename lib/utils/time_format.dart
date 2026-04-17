import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';

/// Valid values for [UserModel.timeFormat].
const String kTimeFormat12h = '12h';
const String kTimeFormat24h = '24h';
const String kTimeFormatDefault = kTimeFormat12h;

String _normalizeTimeFormat(String? value) {
  return value == kTimeFormat24h ? kTimeFormat24h : kTimeFormat12h;
}

/// Format a [DateTime] for display, respecting the user's time format pref.
///
/// Always converts to local time first so callers don't need to remember
/// `.toLocal()` for UTC-origin values (e.g. ESPN game times parsed from
/// ISO8601 with a `Z` suffix, or Firestore Timestamps).
String formatTime(DateTime dt, {String timeFormat = kTimeFormatDefault}) {
  final local = dt.toLocal();
  final fmt = _normalizeTimeFormat(timeFormat);
  final minute = local.minute.toString().padLeft(2, '0');
  if (fmt == kTimeFormat24h) {
    final hour = local.hour.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final rawHour = local.hour;
  final hour = rawHour % 12 == 0 ? 12 : rawHour % 12;
  final period = rawHour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

/// Format a [TimeOfDay] respecting the user's time format pref.
String formatTimeOfDay(TimeOfDay t, {String timeFormat = kTimeFormatDefault}) {
  final fmt = _normalizeTimeFormat(timeFormat);
  final minute = t.minute.toString().padLeft(2, '0');
  if (fmt == kTimeFormat24h) {
    final hour = t.hour.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:$minute $period';
}

/// Exposes the current user's [UserModel.timeFormat] preference.
/// Falls back to 12-hour when the profile is unloaded or unset.
final timeFormatPreferenceProvider = Provider<String>((ref) {
  final profile = ref.watch(currentUserProfileProvider);
  return _normalizeTimeFormat(profile.valueOrNull?.timeFormat);
});

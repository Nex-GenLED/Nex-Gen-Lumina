// #170 — a celebration must always end.
//
// Before a celebration plays, the coordinator records WHAT to put back and
// WHEN it must have ended (its clamped length plus [kCelebrationRevertMargin]).
// If iOS suspends or kills the app mid-way, the timers that would have
// reverted it never run; the next resume or cold start finds this marker and
// finishes the job. Cleared once the revert lands. Stored on the phone only.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// How long past its clamped length a celebration may run before it is
/// stopped and reverted: room for a slow write, never more.
const Duration kCelebrationRevertMargin = Duration(seconds: 10);

class CelebrationMarker {
  /// The team whose celebration this is (served teams are left to the
  /// server on recovery).
  final String teamSlug;

  /// The controller state captured before the celebration; null when it could
  /// not be read — the revert then puts the base look up instead.
  final Map<String, dynamic>? revertTo;

  final DateTime startedAt;

  /// The latest moment the celebration may still be playing.
  final DateTime endBy;

  const CelebrationMarker({
    required this.teamSlug,
    required this.revertTo,
    required this.startedAt,
    required this.endBy,
  });

  Map<String, dynamic> toJson() => {
        'team_slug': teamSlug,
        'revert_to': revertTo,
        'started_at': startedAt.toUtc().toIso8601String(),
        'end_by': endBy.toUtc().toIso8601String(),
      };

  /// Null for anything unreadable — a corrupt marker must not block recovery
  /// forever (it is cleared by the caller).
  static CelebrationMarker? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final slug = raw['team_slug'];
    final started = DateTime.tryParse('${raw['started_at']}');
    final end = DateTime.tryParse('${raw['end_by']}');
    if (slug is! String || started == null || end == null) return null;
    final revert = raw['revert_to'];
    return CelebrationMarker(
      teamSlug: slug,
      revertTo: revert is Map ? Map<String, dynamic>.from(revert) : null,
      startedAt: started,
      endBy: end,
    );
  }
}

/// Where the marker lives.
abstract class CelebrationMarkerStore {
  Future<CelebrationMarker?> load();
  Future<void> save(CelebrationMarker marker);
  Future<void> clear();
}

/// For tests and for a coordinator built without storage.
class InMemoryCelebrationMarkerStore implements CelebrationMarkerStore {
  CelebrationMarker? marker;

  @override
  Future<CelebrationMarker?> load() async => marker;
  @override
  Future<void> save(CelebrationMarker m) async => marker = m;
  @override
  Future<void> clear() async => marker = null;
}

/// The phone's store: one SharedPreferences key, survives a kill.
class SharedPrefsCelebrationMarkerStore implements CelebrationMarkerStore {
  static const String key = 'celebration_in_progress.v1';

  @override
  Future<CelebrationMarker?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final m = CelebrationMarker.fromJson(jsonDecode(raw));
      if (m == null) await prefs.remove(key);
      return m;
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  @override
  Future<void> save(CelebrationMarker marker) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(marker.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

// lib/features/neighborhood/sync_fire_status.dart
//
// Neighborhood Sync v1 — the per-house outcome of one Start tap (a "fire").
//
// applySyncPattern writes one relay command per member controller and a fire
// record; pollSyncFire reads the commands back and returns this shape. The
// initiator's app polls it while it waits (see syncFireStatusProvider) so the
// user is told what actually happened at each house, never just "sent".
//
// PURE: no Firebase imports. Everything here is unit-testable with maps.

import 'package:flutter/foundation.dart';

/// Identity of a fire the app is currently watching.
@immutable
class SyncFireRef {
  final String groupId;
  final String fireId;
  final DateTime startedAt;

  const SyncFireRef({
    required this.groupId,
    required this.fireId,
    required this.startedAt,
  });

  @override
  bool operator ==(Object other) =>
      other is SyncFireRef &&
      other.groupId == groupId &&
      other.fireId == fireId &&
      other.startedAt == startedAt;

  @override
  int get hashCode => Object.hash(groupId, fireId, startedAt);
}

/// Target statuses that mean "a command was written and it did not land".
const Set<String> kSyncFireProblemStatuses = {
  'failed',
  'timeout',
  'superseded',
  'expired',
  'no_response',
  'no_address',
  'no_bridge',
  'plan_failed',
};

const Set<String> kSyncFireWaitingStatuses = {'pending', 'executing'};

/// One member controller in a fire.
@immutable
class SyncFireTarget {
  final String key;
  final String uid;
  final String displayName;
  final String controllerId;
  final String route;
  final String status;
  final String reason;
  final String error;

  const SyncFireTarget({
    required this.key,
    required this.uid,
    required this.displayName,
    required this.controllerId,
    required this.route,
    required this.status,
    required this.reason,
    required this.error,
  });

  factory SyncFireTarget.fromJson(Map<String, dynamic> j) => SyncFireTarget(
        key: _str(j['key']),
        uid: _str(j['uid']),
        displayName: _str(j['displayName']),
        controllerId: _str(j['controllerId']),
        route: _str(j['route']),
        status: _str(j['status']),
        reason: _str(j['reason']),
        error: _str(j['error']),
      );

  String get label => displayName.isNotEmpty ? displayName : 'A house';
  bool get isWaiting => kSyncFireWaitingStatuses.contains(status);
  bool get isConfirmed => status == 'completed';
  bool get isProblem => kSyncFireProblemStatuses.contains(status);
  bool get isSkipped => status == 'skipped';

  /// Plain-language reason for a house that did not change.
  String get problemText {
    switch (status) {
      case 'no_bridge':
        return 'bridge offline — only changes if their app is open';
      case 'no_address':
        return 'no controller address on file';
      case 'no_response':
      case 'expired':
        return 'no response (bridge offline?)';
      case 'failed':
        return error.contains('HTTP -1')
            ? 'controller not reachable from their bridge'
            : 'failed${error.isNotEmpty ? ' ($error)' : ''}';
      case 'timeout':
        return 'timed out';
      case 'superseded':
        return 'replaced by a newer sync';
      case 'plan_failed':
        return 'could not be planned';
      case 'skipped':
        return reason == 'paused' ? 'paused' : 'opted out';
      default:
        return status;
    }
  }
}

/// The fire's current view: per-target rows plus a per-HOUSE roll-up.
///
/// A house is one member uid. Multi-controller homes have several targets;
/// the house counts as confirmed only when every commanded target completed,
/// as waiting while any is open, and as a problem otherwise.
@immutable
class SyncFireStatus {
  final String fireId;
  final String groupId;
  final DateTime? expiresAt;
  final List<SyncFireTarget> targets;
  final bool settled;

  const SyncFireStatus({
    required this.fireId,
    required this.groupId,
    required this.expiresAt,
    required this.targets,
    required this.settled,
  });

  /// Tolerant of the `Map<Object?, Object?>` shape a callable result arrives in.
  factory SyncFireStatus.fromJson(Map<dynamic, dynamic> raw) {
    final j = _deep(raw) as Map<String, dynamic>;
    final rawTargets = j['targets'];
    final targets = <SyncFireTarget>[];
    if (rawTargets is List) {
      for (final t in rawTargets) {
        if (t is Map<String, dynamic>) targets.add(SyncFireTarget.fromJson(t));
      }
    }
    final summary = j['summary'];
    final settledFromServer =
        summary is Map<String, dynamic> ? summary['settled'] : null;
    final exp = j['expiresAtMs'];
    return SyncFireStatus(
      fireId: _str(j['fireId']),
      groupId: _str(j['groupId']),
      expiresAt: exp is num
          ? DateTime.fromMillisecondsSinceEpoch(exp.toInt())
          : null,
      targets: targets,
      settled: settledFromServer is bool
          ? settledFromServer
          : !targets.any((t) => t.isWaiting),
    );
  }

  /// Houses that were addressed by this fire (skipped members excluded).
  List<String> get houseUids => targets
      .where((t) => !t.isSkipped)
      .map((t) => t.uid)
      .toSet()
      .toList(growable: false);

  String houseLabel(String uid) {
    final t = targets.firstWhere((t) => t.uid == uid,
        orElse: () => targets.first);
    return t.label;
  }

  /// waiting | confirmed | problem
  String houseState(String uid) {
    final mine = targets.where((t) => t.uid == uid && !t.isSkipped).toList();
    if (mine.any((t) => t.isWaiting)) return 'waiting';
    if (mine.any((t) => t.isProblem)) return 'problem';
    if (mine.isNotEmpty && mine.every((t) => t.isConfirmed)) return 'confirmed';
    return 'problem';
  }

  int get houses => houseUids.length;
  int get confirmedHouses =>
      houseUids.where((u) => houseState(u) == 'confirmed').length;
  int get waitingHouses =>
      houseUids.where((u) => houseState(u) == 'waiting').length;
  int get problemHouses =>
      houseUids.where((u) => houseState(u) == 'problem').length;
  int get skippedHouses =>
      targets.where((t) => t.isSkipped).map((t) => t.uid).toSet().length;

  /// One line for the banner. Never claims more than the read-back shows.
  String get headline {
    if (houses == 0) {
      return skippedHouses > 0
          ? 'No houses to sync — $skippedHouses paused or opted out'
          : 'No houses to sync';
    }
    final h = houses == 1 ? 'house' : 'houses';
    if (waitingHouses > 0) {
      return '$confirmedHouses of $houses $h confirmed · $waitingHouses waiting…';
    }
    if (problemHouses == 0) {
      return '$confirmedHouses of $houses $h confirmed';
    }
    return '$confirmedHouses of $houses $h confirmed · '
        '$problemHouses did not change';
  }

  /// One line per house that did not change (or is paused), for the banner.
  List<String> get houseNotes {
    final out = <String>[];
    final seen = <String>{};
    for (final t in targets) {
      if (!(t.isProblem || t.isSkipped)) continue;
      final line = '${t.label} — ${t.problemText}';
      if (seen.add(line)) out.add(line);
    }
    return out;
  }
}

String _str(Object? v) => v is String ? v : (v == null ? '' : v.toString());

/// Recursively converts `Map<Object?, Object?>` / `List<Object?>` (the shape a
/// callable result arrives in) into `Map<String, dynamic>` / `List<dynamic>`.
Object? _deep(Object? v) {
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) e.key.toString(): _deep(e.value),
    };
  }
  if (v is List) return v.map(_deep).toList();
  return v;
}

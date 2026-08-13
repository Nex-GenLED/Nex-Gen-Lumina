// W1 — a server refusal the customer can actually see.
//
// THE GAP. `initiateSyncSession` now refuses legibly: consent_missing,
// consent_blocked, skip_next_active, each naming the category. Its ONLY caller
// is the background worker, which reads `result['sessionId']` on 200 (null for
// a refusal) and `debugPrint`s on non-200. Both discard the reason. There is no
// foreground caller at all, so at the moment of refusal there is no user, no
// BuildContext and no Riverpod — a snackbar is structurally impossible.
//
// THE SHAPE, decided 2026-08-13: persist ALWAYS, notify for the two causes the
// customer can act on. `skip_next_active` is silent — they asked to skip this
// one, and telling them would be the bug rather than the fix.
//
// TWO CONSTRAINTS, both load-bearing:
//
//   NON-REPEATING PER CAUSE. The notification announces the TRANSITION into a
//   refusal state; the banner shows the standing state. The worker retries on
//   its own cadence, so without a dedup key one blocked game night would be a
//   stream of identical notifications. Keyed (eventId, reason): a different
//   event, or the same event failing a different way, is news again.
//
//   PERMISSION IS NOT LEGIBILITY. If notifications are denied, persistence and
//   the banner still work completely. The permission gates IMMEDIACY, never
//   whether the customer can ever find out. Option 2 is option 3's floor.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server reason strings — a wire contract with `initiateSyncSession`.
const String kRefusalConsentMissing = 'consent_missing';
const String kRefusalConsentBlocked = 'consent_blocked';
const String kRefusalSkipNext = 'skip_next_active';

const String _kStandingKey = 'sync_refusal_standing';
const String _kAnnouncedKey = 'sync_refusal_announced';

/// One refusal, as the customer needs to understand it.
@immutable
class SyncRefusal {
  final String eventId;
  final String reason;
  final String category;
  final String message;
  final int atMillis;

  const SyncRefusal({
    required this.eventId,
    required this.reason,
    required this.category,
    required this.message,
    required this.atMillis,
  });

  /// Identity for dedup: the same event failing the same way is one event.
  String get dedupKey => '$eventId::$reason';

  /// Only causes the customer can act on are worth interrupting them for.
  /// `skip_next_active` is their own instruction being honoured.
  bool get warrantsNotification =>
      reason == kRefusalConsentMissing || reason == kRefusalConsentBlocked;

  /// Short enough for a notification body.
  String get title => reason == kRefusalSkipNext
      ? 'Sync skipped'
      : 'Neighborhood Sync did not start';

  Map<String, Object?> toJson() => {
        'eventId': eventId,
        'reason': reason,
        'category': category,
        'message': message,
        'atMillis': atMillis,
      };

  static SyncRefusal? fromJson(Map<String, Object?> j) {
    final e = j['eventId'], r = j['reason'];
    if (e is! String || r is! String) return null;
    return SyncRefusal(
      eventId: e,
      reason: r,
      category: j['category'] is String ? j['category'] as String : '',
      message: j['message'] is String ? j['message'] as String : '',
      atMillis: j['atMillis'] is int ? j['atMillis'] as int : 0,
    );
  }

  /// Parse a refusal out of the Cloud Function's 200 body.
  ///
  /// Returns null for a SUCCESS or an unrecognised shape — a refusal is only
  /// ever constructed from an explicit `success:false` plus a reason, so a
  /// transport hiccup can never manufacture one.
  static SyncRefusal? fromResponseBody(
    Map<String, Object?> body, {
    required String eventId,
    required int nowMillis,
  }) {
    if (body['success'] != false) return null;
    final reason = body['reason'];
    if (reason is! String || reason.isEmpty) return null;
    return SyncRefusal(
      eventId: eventId,
      reason: reason,
      category: body['category'] is String ? body['category'] as String : '',
      message: body['message'] is String ? body['message'] as String : '',
      atMillis: nowMillis,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncRefusal &&
      other.eventId == eventId &&
      other.reason == reason &&
      other.category == category &&
      other.message == message &&
      other.atMillis == atMillis;

  @override
  int get hashCode => Object.hash(eventId, reason, category, message, atMillis);
}

/// PURE. Should this refusal be announced now?
///
/// True only when it warrants a notification AND this exact (eventId, reason)
/// has not been announced. One blocked game night is one notification,
/// however many times the worker retries.
bool shouldAnnounce(SyncRefusal refusal, Set<String> alreadyAnnounced) =>
    refusal.warrantsNotification && !alreadyAnnounced.contains(refusal.dedupKey);

/// Device-local store. SharedPreferences because the background isolate has it
/// and has neither Riverpod nor a Firestore listener.
class SyncRefusalStore {
  const SyncRefusalStore();

  /// The standing refusal the banner shows, or null.
  Future<SyncRefusal?> standing() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kStandingKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SyncRefusal.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> announced() async {
    try {
      final l = (await SharedPreferences.getInstance()).getStringList(_kAnnouncedKey);
      return (l ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Record a refusal. Returns true when the caller should NOTIFY.
  ///
  /// Persistence happens first and unconditionally: if anything below fails,
  /// the customer still learns about it on next open. Never throws — this runs
  /// inside a fire-and-forget worker.
  Future<bool> record(SyncRefusal refusal) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStandingKey, jsonEncode(refusal.toJson()));

      final seen = (prefs.getStringList(_kAnnouncedKey) ?? const <String>[]).toSet();
      if (!shouldAnnounce(refusal, seen)) return false;

      seen.add(refusal.dedupKey);
      // Bounded: a device that syncs nightly for years must not accumulate an
      // unbounded key list in prefs.
      final trimmed = seen.length > 50 ? seen.skip(seen.length - 50).toSet() : seen;
      await prefs.setStringList(_kAnnouncedKey, trimmed.toList());
      return true;
    } catch (e) {
      debugPrint('[SyncRefusal] record failed (non-fatal): $e');
      return false;
    }
  }

  /// A successful initiation clears the standing refusal — the banner must not
  /// outlive the condition it describes.
  Future<void> clearStanding() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_kStandingKey);
    } catch (_) {
      /* cosmetic */
    }
  }
}

// lib/features/wled/controller_facts_writer.dart
//
// THE SHARED WRITER for DEVICE-ONLY FACTS — values a phone on the customer's
// LAN can read and the server structurally cannot.
//
// Two families use it, and they are the same shape:
//
//   participating_channels  — needs the hardware BUS list (`/json/cfg hw.led.ins`)
//   base_boundaries         — the controller's timer table (`/json/cfg timers.ins`)
//
// Both are LAN-only reads. Both feed a server-side planner that has no way to
// see the device: the bridge resolves only `/json/state` and `/json/info`, so
// `/json/cfg` is unreachable off-LAN and no Cloud Function can manufacture
// either value. Both land on `users/{uid}/controllers/{controllerId}` — the
// document `dispatchFireJobs` already reads before every fire, so the server
// gets them for free.
//
// WHY ONE WRITER AND NOT TWO. Not tidiness. Sharing is the only way the two
// families get the same TIMESTAMP DISCIPLINE and the same PUBLISH HISTORY: a
// second hand-rolled writer drifts on exactly the fields an auditor needs, and
// it doubles the per-connect write cost for two values read from a single cfg
// fetch. One `set(merge: true)` carries both.
//
// EVERY WRITE IS FIRE-AND-FORGET AND NEVER FATAL. This is data for planning,
// not for on-device behaviour; the local SharedPreferences participation cache
// remains the sole authority for what the phone does. A failed publish costs
// the planner one stale interval and nothing else — and because the memo is
// only committed on success, the next publish retries.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ── Field naming — one convention, derived, never spelled out per family ─────

/// When the family was last written (server clock).
String factAtField(String field) => '${field}_at';

/// Which call site wrote it (`healer`, `game_day`, `neighborhood_sync`).
String factSourceField(String field) => '${field}_source';

/// **Publish history, part 1** — total writes to this family, ever.
///
/// WHY THIS EXISTS. Every field here is last-wins, and last-wins cannot
/// distinguish "the value was deduped and not rewritten" from "the value was
/// rewritten with the same content". Until this counter there was no way to
/// audit, from production data, whether dedup actually held — and the publish
/// rate is about to go from "twice a fortnight, when someone runs a sync by
/// hand" to once per app session per controller. Tolerable at the old rate;
/// not something to fly blind on at the new one.
///
/// How to read it: divide the delta by the number of app sessions in the
/// window. Dedup is holding at roughly 1 write per session per controller.
/// Anything scaling with resolves-per-session means a memo is not being
/// consulted or is being reset mid-session.
String factPublishCountField(String field) => '${field}_publish_count';

/// **Publish history, part 2** — the value the most recent write superseded.
///
/// Present ⇒ this process had already published for this controller and the
/// value CHANGED (dedup would have suppressed an identical one).
/// Absent ⇒ the write was the first of an app session, so there was no
/// in-process predecessor to compare against.
///
/// The absence is not a gap in the record, it is the honest reading of a
/// process-scoped memo: nothing reads Firestore before writing, deliberately
/// (see `shouldPublishParticipation`), so the app genuinely does not know what
/// the previous session left. The key is DELETED rather than left stale on
/// those writes — a `_previous` from two sessions ago sitting next to a fresh
/// `_at` would read as a change that never happened.
String factPreviousField(String field) => '${field}_previous';

/// Stamp the timestamp + history fields for one family onto [fields].
///
/// Every family goes through here. That is the point: no publisher gets to
/// invent its own `_at` semantics, skip the counter, or spell `_previous`
/// differently.
void stampFactFamily(
  Map<String, Object?> fields, {
  required String field,
  required String source,
  required Object? previous,
  required bool previousKnown,
}) {
  fields[factAtField(field)] = FieldValue.serverTimestamp();
  fields[factSourceField(field)] = source;
  fields[factPublishCountField(field)] = FieldValue.increment(1);
  fields[factPreviousField(field)] =
      previousKnown ? previous : FieldValue.delete();
}

// ── The unit of publishing ───────────────────────────────────────────────────

/// One family's contribution to a publish: the fields to merge, and the memo
/// update to run **only if the write lands**.
///
/// Splitting prepare from commit is what lets two families ride one write while
/// each keeps its own dedup: a family with nothing to say contributes
/// [PreparedFacts.none] and costs nothing, and a family whose write failed does
/// not poison its memo into suppressing the retry.
@immutable
class PreparedFacts {
  final Map<String, Object?> fields;

  /// Runs after a successful write. Records what was published so the next
  /// call can dedup against it.
  final void Function() commit;

  const PreparedFacts(this.fields, this.commit);

  /// Nothing to publish — deduped, unavailable, or "no opinion".
  static final PreparedFacts none = PreparedFacts(const {}, _noCommit);

  bool get isEmpty => fields.isEmpty;

  static void _noCommit() {}
}

/// Merge every non-empty family into **one** `set(merge: true)` on the
/// controller document, then commit their memos.
///
/// Returns true when a write actually went out. Returns false — without
/// throwing, ever — when there is nothing to write, no controller id, or no
/// signed-in user. All three are normal states (demo mode, cold start before
/// discovery, a healthy dedup hit), not errors.
Future<bool> writeControllerFacts({
  required String? controllerId,
  required List<PreparedFacts> families,
  required String label,
  FirebaseFirestore? firestore,
  String? uidOverride,
}) async {
  try {
    if (controllerId == null || controllerId.isEmpty) return false;

    final pending = families.where((f) => !f.isEmpty).toList();
    if (pending.isEmpty) return false; // every family deduped — zero writes

    final uid = uidOverride ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;

    final doc = <String, Object?>{};
    for (final f in pending) {
      doc.addAll(f.fields);
    }

    await (firestore ?? FirebaseFirestore.instance)
        .collection('users')
        .doc(uid)
        .collection('controllers')
        .doc(controllerId)
        .set(doc, SetOptions(merge: true));

    // Commit each family independently. The write has already landed, so one
    // family's bookkeeping failing must not skip another's — that would leave a
    // memo claiming nothing was published when it was, and republish forever.
    for (final f in pending) {
      try {
        f.commit();
      } catch (e) {
        debugPrint('[ControllerFacts] $label memo commit failed: $e');
      }
    }
    debugPrint('[ControllerFacts] $label → $controllerId '
        '(${pending.length} famil${pending.length == 1 ? 'y' : 'ies'}, '
        '${doc.length} fields)');
    return true;
  } catch (e) {
    // Never throw. The memos stay uncommitted, so the next publish retries.
    debugPrint('[ControllerFacts] $label publish failed: $e');
    return false;
  }
}

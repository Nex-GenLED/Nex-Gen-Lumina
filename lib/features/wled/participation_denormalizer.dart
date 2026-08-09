// lib/features/wled/participation_denormalizer.dart
//
// S3b — denormalize the RESOLVED participating-channel set to Firestore so a
// server-side fire can honour it.
//
// WHY THIS EXISTS
// ---------------
// `resolveParticipatingChannels` needs `allDeviceChannelIds`, which comes from
// the controller's hardware BUS list — read over `/json/cfg`, which is LAN-only
// (the bridge has no cfg dispatch branch; `CloudRelayRepository.applyConfig`
// throws). Its OUTPUT is then cached in SharedPreferences, on the phone. So the
// server has neither the input nor the output.
//
// Without this, a cloud-fired Game Day either lights every channel — including
// the patio a customer deliberately excluded — or falls back to segment 0 only.
// Both are visible regressions against the #29 fix.
//
// THE APPROACH — the `controller_ips` precedent, with one difference.
// `controller_ips` is maintained by a Cloud Function trigger because its source
// (the controllers subcollection) is server-visible. This set's source is NOT:
// only a phone on the LAN can compute it. So this is APP-WRITTEN, on every
// successful resolve, to the same document the server already reads.
//
// WHAT THIS FILE DOES NOT DO: it does not change what participates. The
// resolver is untouched; this only publishes its answer.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Firestore field names. snake_case, matching the user/controller doc
/// convention (`controller_ips`, `dealer_code`, `display_name`).
const String kParticipatingChannelsField = 'participating_channels';
const String kParticipatingChannelsAtField = 'participating_channels_at';
const String kParticipatingChannelsDeviceIdsField =
    'participating_channels_device_ids';
const String kParticipatingChannelsSourceField = 'participating_channels_source';

/// How old a denormalized set may be before a server-side fire refuses it.
///
/// WHY 90 DAYS, and why an age check at all. The set is only correct for the
/// device shape it was computed against. The app already self-heals:
/// [ParticipationReconciler] clears the cache whenever the live bus list stops
/// matching, and the next resolve republishes. So a stale value implies the app
/// has not been opened since the hardware changed.
///
/// That leaves exactly one dangerous case — hardware changed AND the customer
/// has not opened the app since — which nothing server-side can detect, because
/// the bus list is not visible off-LAN. An age bound is the only available
/// backstop.
///
/// 90 days is deliberately long. A customer using the system normally
/// republishes constantly and never approaches it; a shorter horizon would
/// strand people who simply do not open the app, which is most of them. It is a
/// bound on ABANDONED data, not a freshness requirement.
const Duration kParticipationMaxAge = Duration(days: 90);

/// What the app writes. Pure — no Firestore types, so it is unit-testable.
///
/// `deviceChannelIds` is recorded alongside the resolved set deliberately: it is
/// the SHAPE the resolution was computed against, and it is the only provenance
/// a future reader has for judging whether the answer still applies. Without it
/// the stored list is an assertion with no basis.
@visibleForTesting
Map<String, Object?> buildParticipationDoc({
  required List<int> resolved,
  required List<int> deviceChannelIds,
  required String source,
}) {
  return <String, Object?>{
    kParticipatingChannelsField: List<int>.from(resolved),
    kParticipatingChannelsDeviceIdsField: List<int>.from(deviceChannelIds),
    kParticipatingChannelsSourceField: source,
    // The caller substitutes a server timestamp for this key; it is named here
    // so the shape is complete and testable in one place.
    kParticipatingChannelsAtField: null,
  };
}

/// Should this resolution be published?
///
/// **On change only.** A resolve happens on every Game Day payload build and on
/// every sync command applied, which for an active session is a handful per
/// minute — publishing each one would be a write per apply, per user, forever,
/// for a value that changes when hardware changes. That is noise with a cost.
///
/// `lastPublished` is the last value this process published for this controller.
/// It is in-memory only and therefore empty on every cold start, so each app
/// launch republishes once. That is intentional and cheap: it is the mechanism
/// that heals drift if a write was ever lost, without needing a read-back.
///
/// An empty [resolved] IS published — `[]` means "the user excluded everything",
/// which is a real, actionable answer and must not be confused with "unknown".
bool shouldPublishParticipation({
  required List<int> resolved,
  required List<int>? lastPublished,
}) {
  if (lastPublished == null) return true;
  if (lastPublished.length != resolved.length) return true;
  for (var i = 0; i < resolved.length; i++) {
    if (lastPublished[i] != resolved[i]) return true;
  }
  return false;
}

/// Process-lifetime memo of what has already been published, keyed by
/// controller id. Not persisted — see [shouldPublishParticipation].
@visibleForTesting
final Map<String, List<int>> publishedParticipationMemo = <String, List<int>>{};

/// Clears the memo. Tests only.
@visibleForTesting
void resetParticipationMemo() => publishedParticipationMemo.clear();

/// Record a publish in the memo.
@visibleForTesting
void rememberPublishedParticipation(String controllerId, List<int> resolved) {
  publishedParticipationMemo[controllerId] = List<int>.from(resolved);
}

/// Publish the resolved set to
/// `users/{uid}/controllers/{controllerId}.participating_channels`.
///
/// WHY THAT DOCUMENT. It is the one the dispatcher **already reads** to resolve
/// `controllerIp` before every fire (`dispatchFireJobs`), so the server gets
/// this for free — no extra read, no new collection, no rules change (the
/// controllers subcollection is already owner-readable and server-readable).
/// Putting it on the user doc instead would have forced a choice for
/// multi-controller accounts; putting it in its own collection would have cost
/// a read per fire.
///
/// FIRE-AND-FORGET, and never fatal. This is telemetry for a feature that does
/// not exist yet (S5). It must never block a payload build or fail an apply —
/// the local SharedPreferences cache remains the authority for on-device
/// behaviour and is written independently by
/// `saveLocalParticipatingChannels`.
///
/// Silently does nothing when there is no signed-in user or no controller id;
/// both are normal states (demo mode, cold start before controller discovery).
Future<void> publishParticipatingChannels({
  required String? controllerId,
  required List<int>? resolved,
  required List<int> deviceChannelIds,
  required String source,
  FirebaseFirestore? firestore,
  String? uidOverride,
}) async {
  try {
    // A null resolution means "no opinion" — the resolver could not determine a
    // set. Publishing that would be indistinguishable from "excluded
    // everything". Leave whatever is already there; the server treats an absent
    // field as unknown and skips, which is the correct outcome either way.
    if (resolved == null) return;
    if (controllerId == null || controllerId.isEmpty) return;

    final uid = uidOverride ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    if (!shouldPublishParticipation(
      resolved: resolved,
      lastPublished: publishedParticipationMemo[controllerId],
    )) {
      return;
    }

    final db = firestore ?? FirebaseFirestore.instance;
    final doc = buildParticipationDoc(
      resolved: resolved,
      deviceChannelIds: deviceChannelIds,
      source: source,
    );
    doc[kParticipatingChannelsAtField] = FieldValue.serverTimestamp();

    await db
        .collection('users')
        .doc(uid)
        .collection('controllers')
        .doc(controllerId)
        .set(doc, SetOptions(merge: true));

    rememberPublishedParticipation(controllerId, resolved);
    debugPrint(
      '[Participation] published $resolved for $controllerId (source=$source)',
    );
  } catch (e) {
    // Never throw. A failed publish costs S5 one stale day, not the customer
    // anything — and the next resolve retries because the memo was not updated.
    debugPrint('[Participation] publish failed: $e');
  }
}

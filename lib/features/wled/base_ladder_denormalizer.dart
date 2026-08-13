// R2 — does this controller's base ladder assert per-segment state?
//
// WHY THE SERVER NEEDS THIS. The Game Day readiness gate (functions/src/
// gameDayGate.ts) has three checks. Two are readable server-side; this one was
// not, so every account evaluates to `unknown` — allowed, but unverified. That
// asymmetry is deliberate and temporary: the gate treats absent as
// unknown-and-allowed precisely because nothing published it yet. This file is
// what turns unknown into a per-account fact, one customer at a time, as each
// opens the app on their LAN. No server change is needed to consume it.
//
// WHAT IT ANSWERS, exactly. #67 made an excluded channel go dark for an event,
// and the end-of-event restore is a PRESET LOAD (`baseRestorePayload` emits
// `{ps:N}`). If that preset does not assert `on` for every segment, the channel
// stays dark afterwards — the exclusion leaks past the event that asked for it.
// So the question is narrow: do presets 1 and 2, the two the restore can load,
// each carry a `seg` array with an explicit `on` for every channel the device
// has?
//
// WHY 1 AND 2 SPECIFICALLY. `baseRestorePayload` chooses solarly between
// BASE_ON_PRESET (1) and BASE_OFF_PRESET (2). Those are the only two a restore
// can land on, so they are the only two that matter. Presets 3/4/5 are part of
// the same NGL ladder and share its history, but a fire never restores to them.
//
// THIS IS A DEVICE FACT WITH A KNOWN BAD HISTORY. The base ladder was observed
// psaving with NO `seg` key at all (`audit/BASE_LADDER.md`); the bench was
// repaired 2026-08-09, which makes the bench NON-REPRESENTATIVE of the fleet.
// That is the whole reason this must be measured per account rather than
// assumed from the rig.

import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/wled/controller_facts_writer.dart';

/// `true` verified good, `false` verified BAD, absent = never measured.
///
/// The server reads this tri-state directly: absent is unknown-and-allowed,
/// `false` fails closed, `true` passes. Publishing `false` therefore MOVES AN
/// ACCOUNT INTO LOG-ONLY — which is the point, and why the predicate below
/// refuses to guess.
const String kBaseLadderAssertsSegmentsField = 'base_ladder_asserts_segments';

/// The two presets a base restore can load. See the header.
const List<int> kBaseRestorePresetIds = <int>[1, 2];

/// Process-scoped dedup memo, mirroring the participation family. Never reads
/// Firestore; a relaunch republishing is by design.
final Map<String, bool> publishedBaseLadderMemo = <String, bool>{};

/// PURE. Does one preset assert `on` for every device channel?
///
/// Requires an explicit boolean `on` per segment: a segment present but silent
/// about `on` is exactly the inherited-state case #67 exists to eliminate, so
/// it is not good enough. A preset missing `seg` entirely — the observed
/// failure — is false by the same rule.
bool presetAssertsAllChannels(
  Map<String, dynamic>? preset,
  List<int> deviceChannelIds,
) {
  if (preset == null) return false;
  final raw = preset['seg'];
  if (raw is! List || raw.isEmpty) return false;

  final asserted = <int>{};
  for (final entry in raw) {
    if (entry is! Map) continue;
    final id = entry['id'];
    final on = entry['on'];
    if (id is int && on is bool) asserted.add(id);
  }
  return deviceChannelIds.every(asserted.contains);
}

/// PURE. The tri-state verdict for a controller.
///
/// Returns `null` — NOT `false` — when the inputs cannot answer the question:
/// no device channel list, or presets unreadable. `false` is a claim that the
/// ladder is broken and puts the account in log-only; making it also mean "we
/// could not look" would gate the fleet on a failed HTTP GET.
bool? ladderAssertsSegments({
  required Map<int, Map<String, dynamic>>? presets,
  required List<int> deviceChannelIds,
}) {
  if (presets == null) return null;
  if (deviceChannelIds.isEmpty) return null;

  for (final id in kBaseRestorePresetIds) {
    if (!presetAssertsAllChannels(presets[id], deviceChannelIds)) return false;
  }
  return true;
}

/// PURE. Publish only when the verdict is known AND changed.
bool shouldPublishBaseLadder({
  required bool? verdict,
  required bool? lastPublished,
}) {
  if (verdict == null) return false;
  return verdict != lastPublished;
}

/// Build this family's contribution to a publish, or [PreparedFacts.none].
///
/// ZERO-MUTATION ON A SECOND CONNECT. An unchanged verdict contributes nothing,
/// so a healthy controller reconnecting produces no write from this family —
/// the guarantee the participation family already holds, and the one the #67
/// disposition mirror nearly broke by stamping unconditionally.
PreparedFacts prepareBaseLadderFacts({
  required String controllerId,
  required bool? verdict,
  required String source,
}) {
  final last = publishedBaseLadderMemo[controllerId];
  if (!shouldPublishBaseLadder(verdict: verdict, lastPublished: last)) {
    return PreparedFacts.none;
  }

  final fields = <String, Object?>{
    kBaseLadderAssertsSegmentsField: verdict,
  };
  stampFactFamily(
    fields,
    field: kBaseLadderAssertsSegmentsField,
    source: source,
    previous: last,
    previousKnown: last != null,
  );

  final snapshot = verdict!;
  return PreparedFacts(
    fields,
    () => publishedBaseLadderMemo[controllerId] = snapshot,
  );
}

/// Test seam: forget what this process published.
@visibleForTesting
void resetBaseLadderMemo() => publishedBaseLadderMemo.clear();

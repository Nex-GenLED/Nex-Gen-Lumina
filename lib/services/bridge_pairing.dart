import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';

/// Relay eligibility — does this account have a Lumina Bridge at all?
///
/// THE DEFECT THIS EXISTS FOR (read-only analysis, 2026-09-30). The relay
/// path was chosen by the network heuristic alone: any "remote" verdict built
/// a `CloudRelayRepository`, and nothing on the client, in the rules, or in
/// Cloud Functions asked whether a bridge existed to pick the command up. Five
/// live accounts with no bridge wrote 124 relay commands in a week from cellular,
/// every one of which sat in the queue until the sweeper expired it, and the
/// customer waited 45 s to be told to "check your connection".
///
/// TWO QUESTIONS, KEPT APART (owner decision, 2026-09-30):
///
///  * [hasPairedBridge] — a `bridge_registry` row with `pairedUid == uid`
///    EXISTS. This alone decides whether a relay repository may be built. It
///    deliberately ignores `lastSeen`: a paired customer whose bridge is
///    briefly offline must still take the relay path, get the "can't reach"
///    message, and recover the moment the bridge returns. They must never be
///    told remote access isn't set up.
///
///  * [bridgeFreshness] — how long since the bridge last reported. Used ONLY
///    to choose the wording of a failure. Never to block routing.
///
/// NEVER read from `users/{uid}.bridge_paired` or `bridge_ip`. One live account
/// carries `bridge_paired: true` for a bridge whose registry row was deleted on
/// 2026-09-18; the user-doc flags go stale, the
/// registry row is the durable identity the bridge itself re-asserts on every
/// heartbeat.
///
/// COST. The lookup is a Firestore `snapshots()` stream, cached by Riverpod and
/// by the SDK's local persistence. The routing check reads the last emission;
/// it adds no network round-trip to any command.

/// The Firestore [pairedBridgeProvider] reads. Overridden in tests.
final bridgeRegistryFirestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

/// What the registry says about this account's bridge.
enum PairedBridgeState {
  /// No answer yet (stream loading, or an empty from-cache snapshot on a cold
  /// install). Routing treats this exactly as before this change: fail OPEN.
  unknown,

  /// The registry has no row paired to this uid.
  none,

  /// At least one registry row is paired to this uid.
  paired,
}

/// One paired registry row, as far as routing and messaging need it.
@immutable
class PairedBridge {
  const PairedBridge({
    required this.deviceId,
    required this.status,
    required this.lastSeen,
    required this.ip,
  });

  final String deviceId;
  final String? status;

  /// Null when the row has never carried a heartbeat.
  final DateTime? lastSeen;
  final String? ip;

  @override
  String toString() => 'PairedBridge($deviceId, lastSeen=$lastSeen)';
}

/// The registry answer for this account.
@immutable
class PairedBridgeLookup {
  const PairedBridgeLookup(this.state, this.bridge);

  const PairedBridgeLookup.unknown()
      : state = PairedBridgeState.unknown,
        bridge = null;

  const PairedBridgeLookup.none()
      : state = PairedBridgeState.none,
        bridge = null;

  final PairedBridgeState state;

  /// The freshest paired row, when [state] is [PairedBridgeState.paired].
  final PairedBridge? bridge;

  bool get isPaired => state == PairedBridgeState.paired;
}

/// Reduce one registry query result to a [PairedBridgeLookup].
///
/// Pure, so the cold-cache and multi-row shapes are unit-tested without
/// Firestore. When an account has two paired rows (the 2026-08-05
/// replaced-bridge shape: a live replacement beside a superseded unit) the row with
/// the newest heartbeat is reported, so freshness messaging follows the live
/// one.
PairedBridgeLookup reducePairedBridgeSnapshot({
  required List<Map<String, dynamic>> rows,
  required List<String> ids,
  required bool fromCache,
}) {
  if (rows.isEmpty) {
    // A cold local cache answers an unseen query with an empty from-cache
    // snapshot before the server has been asked. That is not "no bridge"; it
    // is "not known yet", and the server snapshot follows within the second.
    return fromCache
        ? const PairedBridgeLookup.unknown()
        : const PairedBridgeLookup.none();
  }
  PairedBridge? best;
  for (var i = 0; i < rows.length; i++) {
    final data = rows[i];
    final lastSeenRaw = data['lastSeen'];
    final lastSeen = lastSeenRaw is Timestamp ? lastSeenRaw.toDate() : null;
    final candidate = PairedBridge(
      deviceId: ids[i],
      status: data['status'] as String?,
      lastSeen: lastSeen,
      ip: data['ip'] as String?,
    );
    if (best == null) {
      best = candidate;
      continue;
    }
    final bestSeen = best.lastSeen;
    if (bestSeen == null || (lastSeen != null && lastSeen.isAfter(bestSeen))) {
      best = candidate;
    }
  }
  return PairedBridgeLookup(PairedBridgeState.paired, best);
}

/// Streams the registry's answer for the signed-in account.
///
/// Keyed on the AUTH uid, not the installer-impersonation uid, because the
/// relay writes its commands under the auth uid
/// (`buildRoutedRepository` → `CloudRelayRepository.userId`).
final pairedBridgeProvider = StreamProvider<PairedBridgeLookup>((ref) {
  final uid = ref.watch(authStateProvider).maybeWhen(
        data: (user) => user?.uid,
        orElse: () => null,
      );
  if (uid == null) {
    return Stream<PairedBridgeLookup>.value(const PairedBridgeLookup.none());
  }
  final query = ref
      .watch(bridgeRegistryFirestoreProvider)
      .collection('bridge_registry')
      .where('pairedUid', isEqualTo: uid);
  return query.snapshots(includeMetadataChanges: true).map((snap) {
    final lookup = reducePairedBridgeSnapshot(
      rows: snap.docs.map((d) => d.data()).toList(),
      ids: snap.docs.map((d) => d.id).toList(),
      fromCache: snap.metadata.isFromCache,
    );
    debugPrint('BridgePairing: uid=$uid state=${lookup.state.name} '
        'bridge=${lookup.bridge?.deviceId ?? '-'} fromCache=${snap.metadata.isFromCache}');
    return lookup;
  });
});

/// The current registry answer, with a stream gap or error read as
/// [PairedBridgeState.unknown] — never as "no bridge". A lookup failure must
/// not strand a paired customer.
final pairedBridgeStateProvider = Provider<PairedBridgeState>((ref) {
  return ref.watch(pairedBridgeProvider).maybeWhen(
        data: (lookup) => lookup.state,
        orElse: () => PairedBridgeState.unknown,
      );
});

/// The freshest paired row, or null.
final pairedBridgeInfoProvider = Provider<PairedBridge?>((ref) {
  return ref.watch(pairedBridgeProvider).maybeWhen(
        data: (lookup) => lookup.bridge,
        orElse: () => null,
      );
});

/// `hasPairedBridge(uid)` for the signed-in account: true, false, or null
/// while the registry has not answered.
final hasPairedBridgeProvider = Provider<bool?>((ref) {
  switch (ref.watch(pairedBridgeStateProvider)) {
    case PairedBridgeState.paired:
      return true;
    case PairedBridgeState.none:
      return false;
    case PairedBridgeState.unknown:
      return null;
  }
});

/// A bridge that has not reported for this long is described as offline in
/// failure messages. The registry heartbeat is every 30 s, so this is many
/// missed beats, not one.
const Duration kBridgeStaleAfter = Duration(minutes: 10);

/// How long since the bridge last reported. Null when there is no paired
/// bridge or it has never reported. MESSAGING ONLY — see the file header.
Duration? bridgeFreshness(PairedBridge? bridge, {DateTime? now}) {
  final seen = bridge?.lastSeen;
  if (seen == null) return null;
  final age = (now ?? DateTime.now()).difference(seen);
  return age.isNegative ? Duration.zero : age;
}

/// The sentence for a relay command that did not land, chosen by freshness.
///
/// A paired bridge that has been silent for [kBridgeStaleAfter] or longer gets
/// named as the likely cause; anything fresher keeps the generic wording,
/// because the bridge was heard from and the controller or the network is the
/// more probable culprit.
String relayUnreachableMessage({
  required PairedBridge? bridge,
  required String fallback,
  DateTime? now,
}) {
  final age = bridgeFreshness(bridge, now: now);
  if (age == null || age < kBridgeStaleAfter) return fallback;
  return "Your Lumina Bridge hasn't checked in for ${describeAge(age)}. "
      "Check that it's powered on and online at home.";
}

/// `4 minutes`, `3 hours`, `2 days` — the coarsest unit that is at least 1.
String describeAge(Duration age) {
  if (age.inDays >= 1) {
    final d = age.inDays;
    return d == 1 ? '1 day' : '$d days';
  }
  if (age.inHours >= 1) {
    final h = age.inHours;
    return h == 1 ? '1 hour' : '$h hours';
  }
  final m = age.inMinutes < 1 ? 1 : age.inMinutes;
  return m == 1 ? '1 minute' : '$m minutes';
}

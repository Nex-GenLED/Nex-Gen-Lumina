import 'package:cloud_firestore/cloud_firestore.dart';

/// The pairing wizard's verification ping (`bridge_setup_screen.dart`,
/// Step 3).
///
/// EXEMPT from the relay-eligibility gate that `BridgeHealthService` and the
/// routed repository apply. Those refuse to queue a relay command for an
/// account with no paired bridge, because such a command can only expire.
/// This ping is different: it is written right after the bridge flipped the
/// registry row to `paired`, to prove that round trip, and the app's cached
/// registry answer may not have caught up yet. Gating it would make a
/// successful pairing look like a failed one.
///
/// The server-side fail-fast (`functions/src/relayEligibility.ts`) recognises
/// the same shape — `type: ping` with an empty `controllerIp` — and leaves it
/// alone for the same reason.
///
/// Deliberately untargeted (`controllerId`/`controllerIp` empty). The
/// /commands create rule DENIES any controllerIp not in the user's
/// `controller_ips`, and the selected IP on an installer's phone can be stale
/// or mDNS-picked — which surfaced as "Verification error: permission-denied"
/// on a bridge that was paired and healthy (field install, 2026-09-18). A ping
/// proves the bridge round trip; it needs no controller target.
Map<String, dynamic> pairingPingDoc() => {
      'type': 'ping',
      'payload': '{}',
      'controllerId': '',
      'controllerIp': '',
      'webhookUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    };

/// True for a command doc of the pairing-ping shape.
bool isPairingPing(Map<String, dynamic> doc) =>
    doc['type'] == 'ping' && (doc['controllerIp'] ?? '') == '';

/// Writes the ping under `users/{uid}/commands` and returns its reference.
/// Always writes — see the file header for why there is no gate here.
Future<DocumentReference<Map<String, dynamic>>> writePairingPing(
  FirebaseFirestore firestore,
  String uid,
) =>
    firestore
        .collection('users')
        .doc(uid)
        .collection('commands')
        .add(pairingPingDoc());

import 'dart:convert';
// Two-node fanout verification — PURE logic.
//
// Proves the claim the crew-fanout activation actually rests on: a sync
// initiated by member A reaches member B, where B is NOT the initiator and
// never runs the app. Per docs/neighborhood_fanout_activation_runbook.md
// §TWO-NODE VERIFICATION (runbook step 4), which gates the `enabled:true` flip.
//
// TOPOLOGY
//   Node A  — the real bench controller (192.168.1.150).
//   Node B  — a stub WLED endpoint: GET /json/state returns current state,
//             POST records the applied payload. B has no app and no phone.
//   Bridge  — a simulator that drains /users/{B_uid}/commands exactly as the
//             ESP32 bridge does and POSTs each applyJson to B.
//
// WHY B IS A STUB: the runbook's point is that closed-app delivery is a
// SERVER property — the CF writes into B's command queue and the bridge
// executes it. Nothing in that chain needs a second phone or a second house,
// so the whole thing is verifiable on one bench.
//
// This file holds only the decision logic, so every assertion is unit-testable
// with canned fixtures and no hardware. The I/O half (stub HTTP server, queue
// drain, live POSTs) lives in bench/bin/bench.dart behind [CommandQueue].
//
// STATUS: built, unit-tested, NOT YET RUN against hardware — running it is
// runbook step 5 and waits on the F-3 rules deploy plus a scoped fanout flag.

/// The pattern being broadcast, reduced to the fields that decide convergence.
///
/// Deliberately narrow: a WLED state blob carries dozens of fields that drift
/// for reasons unrelated to a fanout (uptime, wifi rssi, live-mode flags).
/// Comparing whole blobs would produce false failures, so convergence is
/// judged on what the broadcast actually sets.
class PatternSpec {
  final int effectId;
  final int paletteId;
  final List<List<int>> colors;

  const PatternSpec({
    required this.effectId,
    required this.paletteId,
    required this.colors,
  });

  Map<String, dynamic> toSegPayload() => {
        'seg': [
          {
            'fx': effectId,
            'pal': paletteId,
            'col': colors,
          }
        ],
      };
}

/// The observable slice of a controller's `/json/state`.
class ControllerSnapshot {
  final bool on;
  final int? effectId;
  final int? paletteId;
  final List<List<int>> colors;

  const ControllerSnapshot({
    required this.on,
    this.effectId,
    this.paletteId,
    this.colors = const [],
  });

  /// Reads the first segment out of a `/json/state` body.
  ///
  /// `seg` is a List on some firmwares and a Map on others — the documented
  /// WLED variability that has bitten this codebase before, so both are
  /// handled rather than assumed.
  static ControllerSnapshot fromState(Map<String, dynamic> state) {
    final rawSeg = state['seg'];
    Map<String, dynamic>? seg0;
    if (rawSeg is List && rawSeg.isNotEmpty) {
      final first = rawSeg.first;
      if (first is Map) seg0 = Map<String, dynamic>.from(first);
    } else if (rawSeg is Map && rawSeg.isNotEmpty) {
      final first = rawSeg.values.first;
      if (first is Map) seg0 = Map<String, dynamic>.from(first);
    }

    final rawCol = seg0?['col'];
    final colors = <List<int>>[];
    if (rawCol is List) {
      for (final c in rawCol) {
        if (c is List) {
          colors.add(c.whereType<num>().map((n) => n.toInt()).toList());
        }
      }
    }

    return ControllerSnapshot(
      on: state['on'] == true,
      effectId: (seg0?['fx'] as num?)?.toInt(),
      paletteId: (seg0?['pal'] as num?)?.toInt(),
      colors: colors,
    );
  }

  /// True when this snapshot carries the broadcast pattern.
  ///
  /// Colors compare on the leading channels only: a broadcast specifies RGB
  /// while an RGBW controller reports RGBW, and a trailing W of 0 is not a
  /// mismatch.
  bool reflects(PatternSpec p) {
    if (effectId != p.effectId) return false;
    if (paletteId != p.paletteId) return false;
    if (colors.length < p.colors.length) return false;
    for (var i = 0; i < p.colors.length; i++) {
      final want = p.colors[i];
      final got = colors[i];
      if (got.length < want.length) return false;
      for (var c = 0; c < want.length; c++) {
        if (got[c] != want[c]) return false;
      }
    }
    return true;
  }
}

/// A command as it sits in `/users/{uid}/commands`.
class QueuedCommand {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final String status;

  /// Where the bridge is told to POST. Empty means the command names no
  /// destination and cannot be executed — see [executableCommands].
  final String controllerIp;

  const QueuedCommand({
    required this.id,
    required this.type,
    required this.payload,
    this.status = 'pending',
    this.controllerIp = '127.0.0.1',
  });
}

/// What the bridge simulator will actually execute, in order.
///
/// Mirrors the real bridge: only pending `applyJson` commands are executed, and
/// a command with no usable payload is skipped rather than POSTed as an empty
/// body (posting an empty `seg` is the skip-apply hazard the sync engine
/// already guards).
///
/// A command with an EMPTY `controllerIp` is also not executable, and this is
/// the harness's most important fidelity rule. The simulator POSTs to its own
/// stub and never reads `controllerIp`, so without this filter it happily
/// "delivers" a command that names no destination — which is exactly what
/// happened on 2026-08-12: `resolveMemberTargets` returned `ip:""` for every
/// member with a denormalized `controllerId` array, the real bridge answered
/// `ERROR: HTTP -1`, and the stub reported success for a command byte-identical
/// to the one that failed. A simulator that is more capable than the thing it
/// simulates does not verify it.
List<QueuedCommand> executableCommands(List<QueuedCommand> queue) {
  return queue
      .where((c) => c.status == 'pending')
      .where((c) => c.type == 'applyJson')
      .where((c) => c.controllerIp.isNotEmpty)
      .where((c) => c.payload.isNotEmpty)
      .where((c) {
    final seg = c.payload['seg'];
    return !(seg is List && seg.isEmpty);
  }).toList();
}

/// Applies an `applyJson` payload to a snapshot — the stub controller's model
/// of a POST to `/json/state`.
ControllerSnapshot applyPayload(
  ControllerSnapshot current,
  Map<String, dynamic> payload,
) {
  final rawSeg = payload['seg'];
  Map<String, dynamic>? seg0;
  if (rawSeg is List && rawSeg.isNotEmpty && rawSeg.first is Map) {
    seg0 = Map<String, dynamic>.from(rawSeg.first as Map);
  }

  final rawCol = seg0?['col'];
  var colors = current.colors;
  if (rawCol is List) {
    colors = [
      for (final c in rawCol)
        if (c is List) c.whereType<num>().map((n) => n.toInt()).toList()
    ];
  }

  return ControllerSnapshot(
    on: payload.containsKey('on') ? payload['on'] == true : current.on,
    effectId: (seg0?['fx'] as num?)?.toInt() ?? current.effectId,
    paletteId: (seg0?['pal'] as num?)?.toInt() ?? current.paletteId,
    colors: colors,
  );
}

/// Outcome of the CF call, as the harness sees it.
class FanoutResponse {
  final int statusCode;
  final bool ok;
  final String? reason;
  final int retryAfterMs;

  const FanoutResponse({
    required this.statusCode,
    required this.ok,
    this.reason,
    this.retryAfterMs = 0,
    this.memberCount,
    this.commandCount,
    this.skipped,
  });

  /// The rate limiter answers 200 with `{ok:false, reason:"rate_limited"}` —
  /// NOT an HTTP error. Treating a non-200 as "rate limited" would let a
  /// genuine 500 masquerade as working anti-strobe protection, which is the
  /// exact false-green this assertion exists to prevent.
  bool get isRateLimited =>
      statusCode == 200 && !ok && reason == 'rate_limited';

  /// The fanout loop's own accounting: how many roster members it served, how
  /// many command docs it wrote, and how many it SKIPPED. The 2026-08-12 run
  /// returned `members=1 commands=1 skipped=1` and the harness discarded all
  /// three, so a silently-skipped initiator surfaced only as an unexplained
  /// convergence failure. A number the server volunteers is never dropped.
  final int? memberCount;
  final int? commandCount;
  final int? skipped;

  static FanoutResponse fromBody(int statusCode, Map<String, dynamic> body) {
    // A 400 MUST NOT be blind. The CF reports a rejected field in `error`, but
    // this only ever read `reason` — so the 2026-08-12 run printed
    // `reason=null` four times while the server was naming the exact problem
    // ("Missing required field: initiatorUid.") in a field nobody looked at.
    // Fall back to `error`, then to the whole body, so a failure can never be
    // less informative than the response that caused it.
    final r = body['reason'] as String?;
    final e = body['error'] as String?;
    final ok = body['ok'] == true;
    return FanoutResponse(
      statusCode: statusCode,
      ok: ok,
      // The whole-body fallback is for FAILURES only. On a success there is
      // nothing to explain, and dumping the body into `reason` made a healthy
      // fanout#1 print `reason={"ok":true,...}` — noise that reads like a
      // problem.
      reason: r ?? e ?? (ok || body.isEmpty ? null : jsonEncode(body)),
      retryAfterMs: (body['retryAfterMs'] as num?)?.toInt() ?? 0,
      memberCount: (body['memberCount'] as num?)?.toInt(),
      commandCount: (body['commandCount'] as num?)?.toInt(),
      skipped: (body['skipped'] as num?)?.toInt(),
    );
  }
}

/// One assertion's verdict.
class FanoutCheck {
  final String name;
  final bool pass;
  final String evidence;

  const FanoutCheck(this.name, this.pass, this.evidence);

  @override
  String toString() => '${pass ? "✓" : "✗"} $name — $evidence';
}

/// Inputs gathered by the runner for one two-node run.
class FanoutRunObservation {
  /// Commands present in B's queue after the fanout (B is NOT the initiator).
  final List<QueuedCommand> bQueueAfterFanout;

  /// The initiator's uid, so "landed on a non-initiator" is provable rather
  /// than assumed.
  final String initiatorUid;
  final String nodeBUid;

  /// A's state BEFORE the broadcast. Without a baseline, convergence cannot be
  /// distinguished from a resting value that already happened to match — see
  /// the inconclusive branch in [evaluateFanoutRun].
  final ControllerSnapshot nodeABefore;

  /// Snapshots taken after the bridge-sim drained and applied.
  final ControllerSnapshot nodeAAfter;
  final ControllerSnapshot nodeBAfter;

  /// The pattern A broadcast.
  final PatternSpec broadcast;

  /// Response to the FIRST fanout — carries the server's own member/skip
  /// accounting, which explains a non-converging node without a log dive.
  final FanoutResponse firstFanout;

  /// Response to a SECOND fanout fired inside the 18s initiator cooldown.
  final FanoutResponse secondFanout;

  const FanoutRunObservation({
    required this.bQueueAfterFanout,
    required this.initiatorUid,
    required this.nodeBUid,
    required this.nodeABefore,
    required this.nodeAAfter,
    required this.nodeBAfter,
    required this.broadcast,
    required this.firstFanout,
    required this.secondFanout,
  });
}

/// Evaluates the runbook's four assertions, in order.
///
/// Order matters and is preserved deliberately: delivery is meaningless if the
/// server never wrote the command, and convergence is meaningless if delivery
/// did not happen. A failure early makes the later checks uninformative rather
/// than independently interesting, so they are reported but should be read
/// top-down.
List<FanoutCheck> evaluateFanoutRun(FanoutRunObservation o) {
  final checks = <FanoutCheck>[];

  // 1. SERVER — the CF wrote into a NON-INITIATOR's queue.
  final executable = executableCommands(o.bQueueAfterFanout);
  final bIsNotInitiator = o.nodeBUid != o.initiatorUid;
  checks.add(FanoutCheck(
    'server: fanout landed in B\'s command queue',
    executable.isNotEmpty && bIsNotInitiator,
    bIsNotInitiator
        ? '${executable.length} executable command(s) for B=${o.nodeBUid}'
        : 'B uid equals the initiator — this run proves nothing about fanout',
  ));

  // 2. DELIVERY — the bridge-sim drained it and B's state moved.
  checks.add(FanoutCheck(
    'delivery: B reflects the broadcast pattern',
    o.nodeBAfter.reflects(o.broadcast),
    'B fx=${o.nodeBAfter.effectId} pal=${o.nodeBAfter.paletteId} '
        'col=${o.nodeBAfter.colors} want fx=${o.broadcast.effectId} '
        'pal=${o.broadcast.paletteId} col=${o.broadcast.colors}',
  ));

  // 3. CONVERGENCE — A shows it too, so the two nodes agree.
  //
  // Two traps this check learned the hard way on 2026-08-12:
  //
  //   (a) A's resting palette was ALREADY pal=5, the broadcast's palette. The
  //       run reported "A fx=0 pal=5" and it read as a partial apply — palette
  //       landed, effect didn't — when in truth NOTHING was delivered to A and
  //       one field coincided. A convergence claim resting on a value that was
  //       there beforehand is not evidence, in either direction, so a baseline
  //       match is reported INCONCLUSIVE rather than passed or failed.
  //   (b) The server had already said why, in `skipped`. Surfaced below.
  final aReflects = o.nodeAAfter.reflects(o.broadcast);
  final aWasAlreadyThere = o.nodeABefore.reflects(o.broadcast);
  final f = o.firstFanout;
  final serverAccounting = f.memberCount == null
      ? ''
      : ' · server served=${f.memberCount} wrote=${f.commandCount} '
          'skipped=${f.skipped}'
          '${(f.skipped ?? 0) > 0 ? " (a SKIPPED member receives no command — "
              "check participationStatus on the roster)" : ""}';
  checks.add(FanoutCheck(
    'convergence: A and B match',
    !aWasAlreadyThere && aReflects && o.nodeBAfter.reflects(o.broadcast),
    aWasAlreadyThere
        ? 'INCONCLUSIVE: A already carried the broadcast pattern BEFORE the '
            'fanout — pick a pattern A is not resting on$serverAccounting'
        : 'A before fx=${o.nodeABefore.effectId} pal=${o.nodeABefore.paletteId} '
            '-> after fx=${o.nodeAAfter.effectId} pal=${o.nodeAAfter.paletteId} · '
            'B fx=${o.nodeBAfter.effectId} pal=${o.nodeBAfter.paletteId} · '
            'want fx=${o.broadcast.effectId} pal=${o.broadcast.paletteId}'
            '$serverAccounting',
  ));

  // 4. RATE LIMIT — a second fanout inside the cooldown is refused, and
  //    nothing new is delivered.
  checks.add(FanoutCheck(
    'rate limit: 2nd fanout <18s is refused',
    o.secondFanout.isRateLimited,
    'status=${o.secondFanout.statusCode} ok=${o.secondFanout.ok} '
        'reason=${o.secondFanout.reason} retryAfterMs=${o.secondFanout.retryAfterMs}',
  ));

  return checks;
}

/// Abstraction over B's command queue so the runner can back it with Firestore
/// REST, the admin SDK via a helper, or a fake in tests.
abstract class CommandQueue {
  Future<List<QueuedCommand>> pending(String uid);
  Future<void> markComplete(String uid, String commandId);
}

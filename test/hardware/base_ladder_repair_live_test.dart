// HARDWARE test — audit/BASE_LADDER.md §6 bench verification.
//
// Closes the §4b caveat. The rig's ladder was HAND-BUILT, which proved what a
// correct ladder looks like but NOT that the app can produce one. This test
// deliberately re-damages a slot the way the ambient-capture defect did, then
// repairs it using the REAL shipping code — ScheduleSyncService's own predicate
// and payload builder — against real hardware.
//
// Run explicitly:
//   flutter test test/hardware/base_ladder_repair_live_test.dart --dart-define=RUN_HW=true
//
// ⚠️ THIS TEST WRITES TO REAL HARDWARE — it deliberately damages preset slot 3
// (`NGL Dim`) on the bench controller and repairs it. Real POSTs, real flash.
//
// HOW IT USED TO GUARD ITSELF, AND WHY THAT WAS WORSE THAN NO GUARD (fixed
// 2026-08-18):
//
//   1. `@Tags(['hardware'])` — INERT. There is **no `dart_test.yaml`** in this
//      repo, so nothing acts on the tag and this file ran in every default
//      `flutter test`. The annotation is kept below because it is correct
//      intent and would start working the moment a `dart_test.yaml` lands, but
//      it must never again be relied on as the guard.
//   2. `if (!reachable) return;` — an early return, which the runner reports as
//      a **PASS**. So on a machine that could not see the bench, this test
//      could not fail; and on a machine that could — the dev box, where
//      192.168.1.150 answers — it silently wrote to the live rig on every
//      suite run. A test that cannot fail, inverted twice.
//
// The guard is now `skip: !kRunHw`, the same mechanism the three cases in
// `preset_heal_live_test.dart` already use, so the ledger's skip-count
// invariant holds: 4 skips is this file and that one, hardware-gated as
// designed, and any OTHER number is a signal.
//
// Reachability is now a HARD FAILURE inside the body, not a silent exit. If a
// run was explicitly requested with RUN_HW=true, a missing bench is the thing
// the run needed to tell you about.

@Tags(['hardware'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

/// Opt-in switch for hardware runs. Identical to the one in
/// `preset_heal_live_test.dart` — same name, same default — so the two files
/// are enabled by the one `--dart-define=RUN_HW=true`.
const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);

const String kIp = '192.168.1.150';
const int kSlot = 3; // NGL Dim — the least visually disruptive ON slot
const String kName = 'NGL Dim';
const int kBri = 51;

final HttpClient _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 10);

Future<Map<String, dynamic>?> _getJson(String path) async {
  try {
    final req = await _client.getUrl(Uri.parse('http://$kIp$path'));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    if (body.trim().isEmpty) return null;
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// ⚠️ contentLength MUST be set. Without it Dart's HttpClient sends the body
/// with chunked transfer-encoding, which WLED's HTTP server rejects — the POST
/// fails while GETs on the same client succeed, which reads as "the controller
/// ignored my write". Same gotcha the bench harness hit.
Future<bool> _postState(Map<String, dynamic> payload) async {
  try {
    final bytes = utf8.encode(jsonEncode(payload));
    final req = await _client.postUrl(Uri.parse('http://$kIp/json/state'));
    req.headers.contentType = ContentType.json;
    req.contentLength = bytes.length;
    req.add(bytes);
    final res = await req.close().timeout(const Duration(seconds: 20));
    await res.drain<void>();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<Map<String, dynamic>?> _storedPreset(int id) async {
  final all = await _getJson('/presets.json');
  final p = all?['$id'];
  return p is Map ? Map<String, dynamic>.from(p) : null;
}

void main() {
  // No setUpAll reachability probe: it would fire a live GET on every default
  // suite run just to decide whether to do nothing.
  test('the app repairs a deliberately damaged ladder slot', () async {
    // ── 0. REACHABILITY IS AN ASSERTION, NOT AN EXIT. Reaching this line means
    //       RUN_HW=true was passed deliberately, so a missing bench is a failed
    //       run — the thing the operator needs told. The old `return` here
    //       reported that same state as a pass.
    final live = await _getJson('/json/state');
    expect(
      live,
      isNotNull,
      reason: 'RUN_HW=true was requested but the bench controller at $kIp did '
          'not answer /json/state. A hardware run with no hardware is a '
          'FAILURE, not a pass.',
    );

    // ── 1. DAMAGE IT the way the defect did: psave with NO seg key, from a
    //       strip whose segments are off. This is the exact ambient capture.
    final segs = (live?['seg'] as List?) ?? const [];
    expect(segs.length, greaterThanOrEqualTo(2),
        reason: 'rig should expose both channels');

    final darkOk = await _postState({
      'on': true,
      'seg': [
        for (var i = 0; i < segs.length; i++) {'id': i, 'on': false},
      ],
    });
    expect(darkOk, isTrue, reason: 'could not darken segments to stage damage');
    await Future<void>.delayed(const Duration(milliseconds: 800));

    // PRECONDITION: the strip must actually be dark, or the psave below
    // captures healthy segments and the test proves nothing.
    final staged = await _getJson('/json/state');
    final stagedSegs = (staged?['seg'] as List?) ?? const [];
    for (final s in stagedSegs) {
      expect((s as Map)['on'], isFalse,
          reason: 'damage not staged — segments still lit');
    }
    // The defective payload — bare {on, bri, ib}, exactly what shipped before.
    final saveOk = await _postState(
        {'on': true, 'bri': kBri, 'ib': true, 'psave': kSlot, 'n': kName});
    expect(saveOk, isTrue, reason: 'damaging psave did not POST');
    await Future<void>.delayed(const Duration(milliseconds: 1600));

    final damaged = await _storedPreset(kSlot);
    expect(damaged, isNotNull);
    // ── 2. The REAL predicate must SEE the damage. This is the half that was
    //       missing: without it psaveIfChanged skips and the fix is inert.
    expect(
      ScheduleSyncService.isNglOnPresetSatisfied(damaged!, kName),
      isFalse,
      reason: 'ambient-captured preset must read as UNSATISFIED',
    );
    // And the OLD bar would have called it healthy — the regression proof.
    expect(
      ScheduleSyncService.isNglOnPresetSatisfied(damaged, kName,
          repairSegments: false),
      isTrue,
      reason: 'pre-fix predicate skipped this preset forever',
    );

    // ── 3. REPAIR using the REAL shipping builder — no hand-written payload.
    final liveNow = await _getJson('/json/state');
    final repair = ScheduleSyncService.buildNglOnPresetState(kBri, liveNow);
    await _postState({...repair, 'psave': kSlot, 'n': kName});
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    // ── 4. The stored def must now satisfy the REAL predicate.
    final repaired = await _storedPreset(kSlot);
    expect(repaired, isNotNull);
    expect(repaired!['on'], isTrue);
    expect(repaired['bri'], kBri);
    for (final s in (repaired['seg'] as List)) {
      expect((s as Map)['on'], isTrue, reason: 'every channel must be on');
    }
    expect(ScheduleSyncService.isNglOnPresetSatisfied(repaired, kName), isTrue);

    // ── 5. IDEMPOTENT: a second pass must decide to write nothing.
    expect(
      ScheduleSyncService.isNglOnPresetSatisfied(repaired, kName),
      isTrue,
      reason: 'a satisfied preset is skipped — no needless psave, no flash',
    );

    // ── 6. Leave the house dark, as found.
    await _postState({'ps': 2});
  }, timeout: const Timeout(Duration(minutes: 2)), skip: !kRunHw);
}

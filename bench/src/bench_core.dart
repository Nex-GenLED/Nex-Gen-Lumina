// Pure assertion / diff logic for the bench harness — NO hardware I/O, so it is
// unit-testable with canned fixtures (this week's real /json/cfg + presets.json
// dumps). The hardware commands in bench.dart feed parsed JSON into these.
//
// Reuses the app's REAL builders (imported, not reinvented):
//   - timersInsLanded / isRealEnabledTimer  (schedule cfg readback comparator)
//   - buildCfgPayload                        (schedule → /json/cfg timers)
//   - buildChannelPowerPayload               (P1-43 per-channel power shapes)
//   - deviceChannelsFromConfig               (hw.led.ins → channels)
// All are pure-Dart (extracted to Flutter-free files), so this runs under
// `dart run` with no dart:ui.
//
// ── ASSERTION DISCIPLINE (added 2026-07-30 after the presetIsOn audit) ──
// A check must verify the property its NAME claims. The original presetIsOn
// claimed "asserts master power" and tested segment-level `on`, so it reported
// PASS on presets that load into a dark strip. Rules now enforced here:
//   1. NEVER hardcode `true` into a CheckResult. If there is nothing to assert,
//      it is a log line, not a check.
//   2. A skipped/absent subject must still emit a check, or the denominator
//      silently shrinks and 2/2 reads as green.
//   3. Prefer asserting the FUNCTIONAL property (does loading this preset light
//      the strip) over a structural proxy (does a key exist).

import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_cfg_gamma.dart';

/// One assertion outcome. [evidence] is the readback proof (for a pass) or the
/// expected-vs-actual (for a fail) — printed verbatim so a green claim always
/// cites what was observed.
class CheckResult {
  final String name;
  final bool pass;
  final String evidence;
  const CheckResult(this.name, this.pass, this.evidence);

  /// VERIFIED-BY-BENCH on pass (with readback evidence) / FAIL on failure.
  String render() => pass
      ? 'VERIFIED-BY-BENCH: $name — $evidence'
      : 'FAIL: $name — $evidence';
}

/// Parse a GET /json/cfg body's `hw.led` into a [WledHardwareConfig] — the same
/// shape the app derives channels from. Tolerant of missing keys.
WledHardwareConfig parseHwLedFromCfg(Map<String, dynamic> cfg) {
  final hw = cfg['hw'];
  final led = (hw is Map) ? hw['led'] : null;
  final ledMap = (led is Map) ? led : const {};
  final rawIns = ledMap['ins'];
  final buses = <WledLedBus>[];
  if (rawIns is List) {
    for (final e in rawIns) {
      if (e is Map) buses.add(WledLedBus.fromMap(e.cast<String, dynamic>()));
    }
  }
  final total = (ledMap['total'] is num)
      ? (ledMap['total'] as num).toInt()
      : buses.fold<int>(0, (a, b) => a + b.len);
  return WledHardwareConfig(totalLeds: total, buses: buses);
}

/// Layout-drift detector (P1-42).
class LayoutDrift {
  final String summary;
  const LayoutDrift(this.summary);
}

/// Compares a known layout against the live one. Returns null when identical.
///
/// AUDIT FIX (2026-07-30): previously compared only `totalLeds` and per-bus
/// `start`/`len`, so a bus whose REVERSE flag, GPIO pin, LED type, colour order
/// or skip count changed read as "no drift" — while the name claims the layout
/// matches. `rev` in particular is load-bearing: it is the per-channel wiring
/// direction the app preserves across every cfg write, and a silent flip
/// reverses a chase on that channel.
LayoutDrift? detectLayoutDrift(
    WledHardwareConfig known, WledHardwareConfig actual) {
  final diffs = <String>[];
  if (known.totalLeds != actual.totalLeds) {
    diffs.add('total ${known.totalLeds}→${actual.totalLeds}');
  }
  if (known.buses.length != actual.buses.length) {
    diffs.add('bus count ${known.buses.length}→${actual.buses.length}');
  }
  final n = known.buses.length < actual.buses.length
      ? known.buses.length
      : actual.buses.length;
  for (var i = 0; i < n; i++) {
    final k = known.buses[i], a = actual.buses[i];
    if (k.start != a.start || k.len != a.len) {
      diffs.add('bus$i [${k.start},${k.len}]→[${a.start},${a.len}]');
    }
    if (k.rev != a.rev) diffs.add('bus$i rev ${k.rev}→${a.rev}');
    if (k.type != a.type) diffs.add('bus$i type ${k.type}→${a.type}');
    if (k.order != a.order) diffs.add('bus$i order ${k.order}→${a.order}');
    if (k.skip != a.skip) diffs.add('bus$i skip ${k.skip}→${a.skip}');
    if (k.pin.join(',') != a.pin.join(',')) {
      diffs.add('bus$i pin ${k.pin}→${a.pin}');
    }
  }
  return diffs.isEmpty ? null : LayoutDrift(diffs.join('; '));
}

/// Serialize a [WledHardwareConfig] to the known_layout.json shape.
/// AUDIT FIX: now round-trips rev/type/order/skip/pin so drift in those fields
/// is detectable. The old form stored only start/len and rehydrated pin as [0],
/// which made pin drift structurally impossible to detect.
Map<String, dynamic> layoutToJson(WledHardwareConfig c) => {
      'totalLeds': c.totalLeds,
      'buses': [
        for (final b in c.buses)
          {
            'start': b.start,
            'len': b.len,
            'rev': b.rev,
            'type': b.type,
            'order': b.order,
            'skip': b.skip,
            'pin': b.pin,
          }
      ],
    };

WledHardwareConfig layoutFromJson(Map<String, dynamic> j) {
  final buses = <WledLedBus>[];
  final raw = j['buses'];
  int asInt(Object? v, [int d = 0]) => (v is num) ? v.toInt() : d;
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        final rawPin = e['pin'];
        buses.add(WledLedBus(
          // Legacy known_layout.json files have no pin — fall back to [0], but
          // only when the key is genuinely absent (so old files still load).
          pin: (rawPin is List)
              ? rawPin.map((p) => asInt(p)).toList()
              : const [0],
          start: asInt(e['start']),
          len: asInt(e['len']),
          rev: e['rev'] == true,
          // Defaults MUST mirror WledLedBus's own (type 30 = SK6812 RGBW,
          // order 1 = GRB). A legacy known_layout.json predating this change
          // has no type/order/skip keys; defaulting them to 0 would report
          // permanent false drift against any live device. Run
          // `probe --update` once to capture the full layout.
          type: asInt(e['type'], 30),
          order: asInt(e['order'], 1),
          skip: asInt(e['skip']),
        ));
      }
    }
  }
  final total = (j['totalLeds'] is num)
      ? (j['totalLeds'] as num).toInt()
      : buses.fold<int>(0, (a, b) => a + b.len);
  return WledHardwareConfig(totalLeds: total, buses: buses);
}

/// Extract the timer `ins` array from a /json/cfg (or /json/state) body.
List<Map<String, dynamic>> timerInsFrom(Map<String, dynamic> body) {
  final timers = body['timers'];
  final ins = (timers is Map) ? timers['ins'] : null;
  if (ins is List) {
    return ins.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
  return const [];
}

/// The en-type-strict truth table (curl-proven 2026-07-22): WLED stores an INT
/// `en:1` as enabled (1) and a JSON BOOL `en:true` as DISABLED (0).
///
/// AUDIT FIX (2026-07-30) — two defects closed:
///  1. The old check normalized bool `true` → 1 before comparing, erasing the
///     very type distinction it exists to detect.
///  2. `stored == null` (the scratch never appeared in readback) normalized to
///     0, so the BOOL half PASSED on a total write failure — a dead controller,
///     a dropped POST or a network error all read as "correctly disabled".
///     [intWriteLanded] is now required: if the INT write did not land, the
///     mechanism is unproven and the whole check FAILS as inconclusive rather
///     than half-passing.
///
/// `absent` is a legitimate BOOL-write outcome on this firmware (WLED compacts
/// disabled entries out of `timers.ins`), so it is accepted there — but only
/// once the int write has proven the write path works.
CheckResult checkEnTruthTable({
  required bool intWriteLanded,
  required Object? storedForIntWrite,
  required Object? storedForBoolWrite,
}) {
  String describe(Object? v) =>
      v == null ? 'ABSENT(compacted-out)' : '$v (${v.runtimeType})';

  if (!intWriteLanded) {
    return CheckResult(
      'en truth table (int→1, bool→0)',
      false,
      'INCONCLUSIVE: the en:1(int) control write never landed '
          '(stored=${describe(storedForIntWrite)}). Cannot distinguish firmware '
          'polarity from a failed write — check connectivity/compaction first.',
    );
  }

  // Type-strict: only a real int 1 counts as "stored enabled". A bool `true`
  // here would mean the firmware preserved the bool, which is a DIFFERENT
  // behaviour from the one this table asserts and must not silently pass.
  final intOk = storedForIntWrite == 1;
  // Disabled = stored int 0, or compacted out of the array entirely.
  final boolOk = storedForBoolWrite == null || storedForBoolWrite == 0;

  return CheckResult(
    'en truth table (int→1, bool→0)',
    intOk && boolOk,
    'en:1(int) stored as ${describe(storedForIntWrite)} (want int 1); '
        'en:true(bool) stored as ${describe(storedForBoolWrite)} '
        '(want int 0 or absent)',
  );
}

/// Bounds for app-managed schedule preset slots and the lease slots that must
/// NEVER be touched by the harness's scratch writes.
const int kSchedulePresetMin = 10;
const int kSchedulePresetMax = 25;
const Set<int> kLeaseSlots = {26, 28, 41};
const Set<int> kSystemSlots = {1, 2, 3, 4, 5};
const int kWledPresetCeiling = 250;

/// Lease-preset band (macro 26-41) — reserved, never harness-written.
const int kLeaseBandMin = 26;
const int kLeaseBandMax = 41;

/// The app's OFF preset slot (ScheduleSyncService.kNglOffPresetId). fire-test
/// parks `ps` here before arming so the fire discriminator is non-degenerate,
/// and because loading it enforces the required start-dark precondition.
const int kNglOffPresetIdForBench = 2;

/// User-pattern band (see lib/features/wled/wled_preset_ranges.dart).
const int kUserPatternBandMin = 100;

/// **THE authoritative "will loading this preset power the strip" signal.**
///
/// Only a root `on: true` asserts MASTER power. WLED writes root `on`/`bri`
/// into a stored preset only when the save carried `ib: true` — that is exactly
/// what 9158c00 added and what this check exists to protect.
///
/// ⚠️ `ib` itself is a REQUEST flag to `psave`, NOT a stored field. WLED never
/// writes it back into presets.json, so `ib: ABSENT` is expected on every
/// preset, healthy or broken. **Never treat `ib` presence as a signal.**
///
/// ⚠️ Segment-level `on` is NOT a substitute. A preset whose segments are all
/// `on: true` still loads into a master-off strip and leaves the lights dark —
/// that is the exact failure this harness reported as PASS for weeks.
bool presetAssertsMasterPower(Map<String, dynamic> def) => def['on'] == true;

/// True when the preset explicitly asserts master OFF (root `on: false`).
/// Distinct from "no segment is lit": a preset can have all segments off and
/// still leave the master ON, which is the pre-769d6e9 OFF-preset bug shape.
bool presetAssertsMasterOff(Map<String, dynamic> def) => def['on'] == false;

/// Does ANY segment in this preset render? Honestly named replacement for the
/// old `presetIsOn`, which claimed to test master power and tested this.
/// Useful as supporting evidence — NEVER as the master-power assertion.
bool presetAnySegmentOn(Map<String, dynamic> def) {
  final seg = def['seg'];
  if (seg is! List) return false;
  for (final s in seg) {
    if (s is Map && s['on'] == true) return true;
  }
  return false;
}

/// Preset-invariant checks over a parsed presets.json (id→def map).
///
/// AUDIT FIXES (2026-07-30):
///  - ON presets now assert ROOT `on` ([presetAssertsMasterPower]), not
///    segment-any-on. This is the defect that made the harness green on presets
///    that load dark.
///  - An ABSENT system preset no longer emits NOTHING. Silently skipping shrank
///    the denominator, so a controller missing presets could score 2/2 green.
///  - OFF preset 2 now requires an explicit root `on: false`, not merely
///    "no segment lit".
///  - The slot-band invariant promised in the old doc comment but never
///    implemented is now a real check.
List<CheckResult> checkPresetInvariants(Map<int, Map<String, dynamic>> presets) {
  final out = <CheckResult>[];

  const onPresets = [1, 3, 4, 5];
  final anySystemPresent = kSystemSlots.any(presets.containsKey);

  if (!anySystemPresent) {
    // A genuinely un-synced controller. Emit ONE explicit check so the run
    // still records that the invariant was evaluated and why it was vacuous.
    out.add(const CheckResult(
      'system presets 1-5 present (controller synced)',
      true,
      'none present — controller has never run a schedule sync; ON/OFF '
          'invariants not applicable',
    ));
  } else {
    for (final id in onPresets) {
      final def = presets[id];
      if (def == null) {
        // Partial sync: some system presets exist and this one does not. That
        // IS a violation — a timer whose macro targets it would load nothing.
        out.add(CheckResult(
          'ON-preset $id present',
          false,
          'ABSENT while other system presets exist (partial sync) — a timer '
              'firing macro:$id would load nothing',
        ));
        continue;
      }
      final asserts = presetAssertsMasterPower(def);
      out.add(CheckResult(
        'ON-preset $id asserts MASTER power (root on:true)',
        asserts,
        'preset $id root on=${def['on'] ?? 'ABSENT'} (want true) · '
            'anySegmentOn=${presetAnySegmentOn(def)} · '
            'segs=${(def['seg'] is List) ? (def['seg'] as List).length : 0}'
            '${asserts ? '' : ' — loading this preset from a master-off strip '
                'leaves the lights DARK (the 9158c00 failure mode)'}',
      ));
    }

    final off = presets[2];
    if (off == null) {
      out.add(const CheckResult(
        'OFF-preset 2 present',
        false,
        'ABSENT while other system presets exist — OFF timers fire macro:2 and '
            'would load nothing',
      ));
    } else {
      final assertsOff = presetAssertsMasterOff(off);
      final noSegLit = !presetAnySegmentOn(off);
      out.add(CheckResult(
        'OFF-preset 2 asserts MASTER off (root on:false)',
        assertsOff && noSegLit,
        'preset 2 root on=${off['on'] ?? 'ABSENT'} (want false) · '
            'anySegmentOn=${presetAnySegmentOn(off)} (want false)',
      ));
    }
  }

  final overCeiling = presets.keys.where((id) => id > kWledPresetCeiling).toList()
    ..sort();
  out.add(CheckResult(
    'all preset slots ≤ $kWledPresetCeiling',
    overCeiling.isEmpty,
    overCeiling.isEmpty ? 'max id ${_maxId(presets)}' : 'over-ceiling: $overCeiling',
  ));

  out.add(checkPresetSlotBands(presets));

  return out;
}

/// The slot-band invariant the old doc comment promised ("No app-managed slots
/// outside 10-25 that look schedule-owned") but never implemented — it was
/// printed as a log line and never asserted.
///
/// Reserved bands: 1-5 system · 10-25 schedule designs · 26-41 leases ·
/// 100+ user patterns. Anything in the gaps (6-9, 42-99) is unaccounted-for and
/// usually an orphan from a superseded write path.
CheckResult checkPresetSlotBands(Map<int, Map<String, dynamic>> presets) {
  final strays = presets.keys.where((id) {
    if (id <= 5) return false; // system
    if (id >= kSchedulePresetMin && id <= kSchedulePresetMax) return false;
    if (id >= kLeaseBandMin && id <= kLeaseBandMax) return false;
    if (id >= kUserPatternBandMin) return false;
    return true; // 6-9 or 42-99
  }).toList()
    ..sort();
  return CheckResult(
    'no preset slots outside the reserved bands',
    strays.isEmpty,
    strays.isEmpty
        ? 'bands clean (1-5 system, 10-25 schedule, 26-41 lease, 100+ user)'
        : 'unaccounted slots: $strays (expected none in 6-9 or 42-99)',
  );
}

/// Lease slots must be present and byte-comparable against a prior capture.
/// AUDIT FIX: the old harness recorded this with a HARDCODED `true` — the check
/// could never fail and verified nothing at all.
CheckResult checkLeaseSlotsIntact({
  required Map<int, Map<String, dynamic>> before,
  required Map<int, Map<String, dynamic>> after,
}) {
  final changed = <String>[];
  for (final id in kLeaseSlots) {
    final b = before[id], a = after[id];
    if (b == null && a == null) continue;
    if (b == null) {
      changed.add('$id APPEARED');
    } else if (a == null) {
      changed.add('$id DISAPPEARED');
    } else if (b['n'] != a['n'] || b['on'] != a['on']) {
      changed.add('$id MUTATED (n/on)');
    }
  }
  final present = kLeaseSlots.where(after.containsKey).toList()..sort();
  return CheckResult(
    'lease slots (26/28/41) untouched by this run',
    changed.isEmpty,
    changed.isEmpty
        ? 'present: $present, unchanged across the run'
        : 'CHANGED: ${changed.join(', ')}',
  );
}

int _maxId(Map<int, Map<String, dynamic>> presets) =>
    presets.keys.isEmpty ? 0 : presets.keys.reduce((a, b) => a > b ? a : b);

/// Convert a presets.json body ({"1":{...},"2":{...}}) to an int-keyed map,
/// dropping the "0" bootloader slot WLED always emits. Empty slot objects are
/// dropped too — WLED emits `{}` for a never-written slot, and counting those
/// as "present" inflates the ceiling/band checks.
Map<int, Map<String, dynamic>> parsePresets(Map<String, dynamic> body) {
  final out = <int, Map<String, dynamic>>{};
  body.forEach((k, v) {
    final id = int.tryParse(k);
    if (id != null && id != 0 && v is Map && v.isNotEmpty) {
      out[id] = v.cast<String, dynamic>();
    }
  });
  return out;
}

/// WLED dow bit for a weekday index where Monday=0..Sunday=6 (matches wled_dow).
int dowBitForMondayZeroIndex(int mondayZero) => 1 << mondayZero;

/// Parse WLED's `info.time` ("2026-7-30, 14:29:23" — NOT zero-padded) into a
/// DateTime in the CONTROLLER's local timezone.
///
/// AUDIT FIX: fire-test computed its target minute and dow bit from the HOST
/// clock, with a comment claiming "WLED 0.15.1 does not expose wall time over
/// JSON". It does — `/json` → `info.time`. Any host/controller clock or
/// timezone skew silently armed the timer for the wrong minute and the test
/// failed for a reason that had nothing to do with the app.
DateTime? parseControllerTime(Object? infoTime) {
  if (infoTime is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2}),\s*(\d{1,2}):(\d{2}):(\d{2})$')
      .firstMatch(infoTime.trim());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  try {
    return DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
  } catch (_) {
    return null;
  }
}

/// Split the single conflated fire-test assertion into its two independent
/// failure modes (VERIFICATION_REPORT.md §6).
///
/// The old harness asserted only `state.on == true` after the fire minute, which
/// fails IDENTICALLY when the timer never fired (firmware) and when the timer
/// fired but loaded a preset that does not assert master power (app). Both were
/// true on the bench rig simultaneously, which is why the failure stayed
/// ambiguous for weeks.
///
/// `state.ps` is the discriminator: it records the last preset LOADED and
/// persists until state is modified. [psBefore] is captured before arming.
List<CheckResult> checkFireTestSplit({
  required int expectedMacro,
  required Object? psBefore,
  required Object? psAfter,
  required Object? onAfter,
}) {
  int? asInt(Object? v) => (v is num) ? v.toInt() : null;
  final psA = asInt(psAfter);

  // DEGENERATE PRECONDITION: if ps already equalled the target macro before
  // arming, "ps changed to the target" cannot distinguish a fire from a
  // leftover. Say so rather than silently reporting a false negative — the
  // caller is expected to park ps on a different preset before arming.
  if (asInt(psBefore) == expectedMacro) {
    return [
      CheckResult(
        'fire-test A: timer FIRED (preset $expectedMacro loaded)',
        false,
        'INCONCLUSIVE: ps was ALREADY $expectedMacro before arming '
            '(ps ${psBefore ?? 'null'}→${psAfter ?? 'null'}), so the '
            'discriminator is degenerate. Park ps on a different preset before '
            'arming and re-run.',
      ),
      CheckResult(
        'fire-test B: fired preset asserts MASTER power',
        false,
        'NOT EVALUATED — check A was inconclusive. state.on=${onAfter ?? 'null'}',
      ),
    ];
  }

  final fired = psA == expectedMacro && psAfter != psBefore;

  final out = <CheckResult>[
    CheckResult(
      'fire-test A: timer FIRED (preset $expectedMacro loaded)',
      fired,
      'ps ${psBefore ?? 'null'}→${psAfter ?? 'null'} (want $expectedMacro)'
          '${fired ? '' : ' — the timer never fired. FIRMWARE/device side: '
              'WLED did not evaluate a persisted, correctly-armed timer. '
              'The app is NOT implicated by this check.'}',
    ),
  ];

  if (fired) {
    out.add(CheckResult(
      'fire-test B: fired preset asserts MASTER power',
      onAfter == true,
      'post-fire state.on=${onAfter ?? 'null'} (want true)'
          '${onAfter == true ? '' : ' — the timer FIRED but preset '
              '$expectedMacro left the master OFF. APP side: the 9158c00 '
              'ib/root-on class.'}',
    ));
  } else {
    // Do not emit a masked B. Record explicitly that it could not be evaluated
    // so the denominator stays honest and nobody reads silence as a pass.
    out.add(CheckResult(
      'fire-test B: fired preset asserts MASTER power',
      false,
      'NOT EVALUATED — check A failed (timer never fired), so the preset was '
          'never loaded. Fix the firing failure before attributing anything to '
          'the preset. state.on=${onAfter ?? 'null'}',
    ));
  }
  return out;
}

// ───────────────────────────────────────────────────────────────────────────
// Timer-table RESTORE, EXACT comparison, PRE-FLIGHT dirty detection, and the
// durable run ledger — added 2026-09-22 after a harness run left two armed
// timer slots and a wiped gamma value on the live controller and every later
// check called it clean. Root cause and the five stacked failures are in the
// memory note "harness restore CANNOT clear timer slots"; the rules below are
// verified-by-source against WLED v0.15.1 cfg.cpp.
// ───────────────────────────────────────────────────────────────────────────

/// WLED general timer slots (0-7). Slots 8/9 are sunrise/sunset and are
/// addressed on the wire by `hour:255`, never by array index.
const int kWledGeneralTimerSlots = 8;

/// The row that CLEARS a general slot. deserializeConfig merges `timers.ins`
/// by array index and never clears a slot the body does not mention;
/// serializeConfig drops a slot from readback only when macro, hour AND min
/// are all 0. So "not mentioning" a slot keeps it, and only this row empties it.
const Map<String, dynamic> kEmptyTimerRow = <String, dynamic>{
  'en': 0,
  'hour': 0,
  'min': 0,
  'macro': 0,
  'dow': 0,
};

/// A sunrise/sunset row as WLED serializes it (`hour == 255`).
bool isSolarTimerRow(Map<String, dynamic> t) =>
    (t['hour'] is num) && (t['hour'] as num).toInt() == 255;

/// One readback row in a canonical string form so two tables can be compared
/// field-for-field. `en` is normalised to 0/1; `start`/`end` (absent on solar
/// rows) default to 0/0 on both sides.
String canonicalTimerRow(Map<String, dynamic> t) {
  int f(String k) => (t[k] is num) ? (t[k] as num).toInt() : 0;
  final en = (t['en'] == true || t['en'] == 1) ? 1 : 0;
  int sub(Object? m, String k) =>
      (m is Map && m[k] is num) ? (m[k] as num).toInt() : 0;
  final start = t['start'], end = t['end'];
  return 'en=$en hour=${f('hour')} min=${f('min')} macro=${f('macro')} '
      'dow=${f('dow')} start=${sub(start, 'mon')}/${sub(start, 'day')} '
      'end=${sub(end, 'mon')}/${sub(end, 'day')}';
}

/// EXACT comparison of two compacted readbacks. Returns null when [actual] is
/// row-for-row identical to [expected] (same rows, same multiplicity, same
/// order); otherwise a human-readable description of every difference.
///
/// This replaces `timersInsLanded` for restore verification. That comparator
/// is a CONTAINMENT check ("every row I sent is present") with a special
/// "cleared schedule" branch for an empty send — right for "did my schedule
/// land", wrong for "is the table back to what it was": a survivor row passes
/// containment, and a solar-only capture takes the special branch.
String? timerTableDiff(
  List<Map<String, dynamic>> expected,
  List<Map<String, dynamic>> actual,
) {
  final e = expected.map(canonicalTimerRow).toList();
  final a = actual.map(canonicalTimerRow).toList();
  final missing = <String>[];
  final remaining = List<String>.of(a);
  for (final row in e) {
    if (!remaining.remove(row)) missing.add(row);
  }
  final extra = remaining; // whatever expected did not account for
  final parts = <String>[];
  if (missing.isNotEmpty) parts.add('MISSING ${missing.length}: $missing');
  if (extra.isNotEmpty) parts.add('EXTRA ${extra.length}: $extra');
  if (parts.isEmpty && e.length == a.length) {
    for (var i = 0; i < e.length; i++) {
      if (e[i] != a[i]) {
        parts.add('same rows, DIFFERENT ORDER (first at index $i)');
        break;
      }
    }
  }
  return parts.isEmpty ? null : parts.join('; ');
}

/// The `timers.ins` body that restores [captured].
///
/// Writes ALL [kWledGeneralTimerSlots] general indices: the captured general
/// rows re-packed from index 0, then [kEmptyTimerRow] for the rest. That is
/// the only shape that (a) clears every slot a run could have dirtied and
/// (b) re-asserts every captured row, whatever slot it originally lived in —
/// the compacted readback does not expose slot numbers, so re-posting only
/// the captured rows at their readback indices could duplicate a row that
/// really lived in slot 3.
///
/// Solar rows (hour 255) are deliberately NOT re-posted. The harness never
/// writes slots 8/9, and a lone re-posted 255 row always lands in slot 8
/// (sunrise) even if it came from slot 9 (sunset). [timerTableDiff] still
/// checks them afterwards, so a disturbed solar row is caught, not hidden.
///
/// Limitation, by design: general rows come back re-packed from slot 0. The
/// app rewrites all ten slots on every schedule sync, so slot numbers carry
/// no meaning it relies on; the readback (which is what everything reads) is
/// identical.
List<Map<String, dynamic>> buildTimerRestoreIns(
    List<Map<String, dynamic>> captured) {
  final general = captured.where((t) => !isSolarTimerRow(t)).toList();
  return [
    for (var i = 0; i < kWledGeneralTimerSlots; i++)
      i < general.length
          ? Map<String, dynamic>.from(general[i])
          : Map<String, dynamic>.from(kEmptyTimerRow),
  ];
}

/// `light.gc` from a raw cfg, or null when absent/unreadable.
Map<String, dynamic>? gammaFromCfg(Map<String, dynamic>? cfg) {
  final light = cfg?['light'];
  final gc = (light is Map) ? light['gc'] : null;
  return (gc is Map) ? gc.cast<String, dynamic>() : null;
}

/// Colour gamma is ON iff `gc.col > 1` (WLED's "exponent-or-1" flag). A cfg
/// POST without `light.gc` resets it to 1 — the wipe this harness used to
/// inflict on every restore.
bool gammaColIntact(Map<String, dynamic>? gc) {
  final col = gc?['col'];
  return col is num && col > 1.0;
}

/// Every `/json/cfg` body the harness sends goes through the app's own gamma
/// chokepoint, so a timers-only write can no longer wipe `light.gc.col`. A
/// body that already states `light.gc` passes through unchanged.
Map<String, dynamic> prepareCfgPayload(Map<String, dynamic> payload) =>
    normalizeWledCfgPayload(payload);

/// Rows the harness itself writes. Any of these on the controller at run start
/// is residue from a run that never restored. (fire-test's scratch has no fixed
/// signature — its minute is computed at run time — which is what the inflight
/// ledger is for.)
const List<Map<String, int>> kHarnessSignatureRows = [
  {'hour': 3, 'min': 33, 'macro': 1, 'dow': 2}, // cfg-truth scratch
  {'hour': 3, 'min': 15, 'macro': 1, 'dow': 17}, // sync-sim fixture ON
  {'hour': 4, 'min': 20, 'macro': 2, 'dow': 17}, // sync-sim fixture OFF
];

bool isHarnessSignatureRow(Map<String, dynamic> t) {
  int f(String k) => (t[k] is num) ? (t[k] as num).toInt() : -1;
  return kHarnessSignatureRows.any((sig) =>
      f('hour') == sig['hour'] &&
      f('min') == sig['min'] &&
      f('macro') == sig['macro'] &&
      f('dow') == sig['dow']);
}

/// PRE-FLIGHT: reasons the controller is NOT in a state a run may start from.
/// Empty = clean. Each reason is one line, written for a human reading the
/// refusal. A killed process skips every `finally`, so the NEXT run has to be
/// the thing that notices — this is that check.
List<String> detectDirtyState({
  required List<Map<String, dynamic>> timers,
  required Map<String, dynamic>? gc,
  required bool inflightLedgerPresent,
}) {
  final reasons = <String>[];
  if (inflightLedgerPresent) {
    reasons.add('an inflight run ledger exists — the previous mutating run '
        'did not reach a verified restore (killed, crashed, or restore FAILED)');
  }
  if (!gammaColIntact(gc)) {
    reasons.add('light.gc = $gc — colour gamma is WIPED (col must be > 1; '
        'the NGL standard is ${kNglLightGammaConfig['col']})');
  }
  final sigs = timers.where(isHarnessSignatureRow).map(canonicalTimerRow);
  for (final s in sigs) {
    reasons.add('harness scratch/fixture row still armed: $s');
  }
  return reasons;
}

/// The durable record of one mutating run. Written to bench/state/inflight.json
/// BEFORE the first write and removed only after a VERIFIED restore, so a run
/// that dies mid-way leaves exactly what the next run needs to (a) refuse to
/// start and (b) put the controller back (`bench recover`).
class RunLedger {
  final String runId;
  final String command;
  final String ip;
  final String startedAt;
  final List<Map<String, dynamic>> capturedTimers;
  final Map<String, dynamic>? capturedGamma;
  final bool? capturedOn;
  final Set<int> dirtiedSlots;
  String status; // inflight | restored | restore-failed

  RunLedger({
    required this.runId,
    required this.command,
    required this.ip,
    required this.startedAt,
    required this.capturedTimers,
    required this.capturedGamma,
    required this.capturedOn,
    Set<int>? dirtiedSlots,
    this.status = 'inflight',
  }) : dirtiedSlots = dirtiedSlots ?? <int>{};

  Map<String, dynamic> toJson() => {
        'runId': runId,
        'command': command,
        'ip': ip,
        'startedAt': startedAt,
        'status': status,
        'capturedTimers': capturedTimers,
        'capturedGamma': capturedGamma,
        'capturedOn': capturedOn,
        'dirtiedSlots': (dirtiedSlots.toList()..sort()),
      };

  static RunLedger? fromJson(Map<String, dynamic> j) {
    final timers = j['capturedTimers'];
    if (timers is! List) return null;
    final gc = j['capturedGamma'];
    return RunLedger(
      runId: '${j['runId'] ?? ''}',
      command: '${j['command'] ?? ''}',
      ip: '${j['ip'] ?? ''}',
      startedAt: '${j['startedAt'] ?? ''}',
      status: '${j['status'] ?? 'inflight'}',
      capturedTimers: timers
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(),
      capturedGamma: gc is Map ? gc.cast<String, dynamic>() : null,
      capturedOn: j['capturedOn'] is bool ? j['capturedOn'] as bool : null,
      dirtiedSlots: {
        for (final s in (j['dirtiedSlots'] is List ? j['dirtiedSlots'] : []))
          if (s is num) s.toInt(),
      },
    );
  }
}

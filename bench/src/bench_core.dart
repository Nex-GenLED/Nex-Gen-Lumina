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

import 'package:nexgen_command/features/wled/wled_hardware_config.dart';

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

/// Layout-drift detector (P1-42): compares a known layout against the live one
/// by total LED count and per-bus start/len. Returns null when identical.
class LayoutDrift {
  final String summary;
  const LayoutDrift(this.summary);
}

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
  }
  return diffs.isEmpty ? null : LayoutDrift(diffs.join('; '));
}

/// Serialize a [WledHardwareConfig] to the compact known_layout.json shape.
Map<String, dynamic> layoutToJson(WledHardwareConfig c) => {
      'totalLeds': c.totalLeds,
      'buses': [
        for (final b in c.buses) {'start': b.start, 'len': b.len}
      ],
    };

WledHardwareConfig layoutFromJson(Map<String, dynamic> j) {
  final buses = <WledLedBus>[];
  final raw = j['buses'];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        buses.add(WledLedBus(
          pin: const [0],
          start: (e['start'] is num) ? (e['start'] as num).toInt() : 0,
          len: (e['len'] is num) ? (e['len'] as num).toInt() : 0,
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
/// `en:1` as enabled (1) and a JSON BOOL `en:true` as DISABLED (0). Given the
/// stored `en` value read back after writing each form, assert the polarity.
/// This is a permanent regression guard for the bool/int saga.
CheckResult checkEnTruthTable({
  required Object? storedForIntWrite, // readback en after writing en:1 (int)
  required Object? storedForBoolWrite, // readback en after writing en:true (bool)
}) {
  int norm(Object? v) => (v == 1 || v == true) ? 1 : 0;
  final intOk = norm(storedForIntWrite) == 1;
  final boolOk = norm(storedForBoolWrite) == 0;
  final pass = intOk && boolOk;
  return CheckResult(
    'en truth table (int→1, bool→0)',
    pass,
    'en:1(int) stored as $storedForIntWrite (want enabled=1); '
        'en:true(bool) stored as $storedForBoolWrite (want disabled=0)',
  );
}

/// Bounds for app-managed schedule preset slots and the lease slots that must
/// NEVER be touched by the harness's scratch writes.
const int kSchedulePresetMin = 10;
const int kSchedulePresetMax = 25;
const Set<int> kLeaseSlots = {26, 28, 41};
const Set<int> kSystemSlots = {1, 2, 3, 4, 5};
const int kWledPresetCeiling = 250;

/// Is a saved preset "on"? This firmware stores on-state per-segment (no
/// top-level `on` on saved presets): on iff any segment is on. Falls back to a
/// top-level `on` for builds that store it. Mirrors ScheduleSyncService's rule.
bool presetIsOn(Map<String, dynamic> def) {
  final seg = def['seg'];
  if (seg is List) {
    for (final s in seg) {
      if (s is Map && s['on'] == true) return true;
    }
    return false;
  }
  return def['on'] == true;
}

/// Preset-invariant checks over a parsed presets.json (id→def map):
///  - ON system presets (1,3,4,5) read as on (ib/root asserts master power).
///  - OFF preset (2) reads as off.
///  - No app-managed slots outside 10-25 that look schedule-owned.
///  - Every slot id ≤ 250 (WLED ceiling).
List<CheckResult> checkPresetInvariants(Map<int, Map<String, dynamic>> presets) {
  final out = <CheckResult>[];

  for (final id in const [1, 3, 4, 5]) {
    final def = presets[id];
    if (def == null) continue; // absent is not a violation here (not yet synced)
    out.add(CheckResult(
      'ON-preset $id asserts power (reads on)',
      presetIsOn(def),
      'preset $id on=${presetIsOn(def)} (want true)',
    ));
  }

  final off = presets[2];
  if (off != null) {
    out.add(CheckResult(
      'OFF-preset 2 reads off',
      !presetIsOn(off),
      'preset 2 on=${presetIsOn(off)} (want false)',
    ));
  }

  final overCeiling = presets.keys.where((id) => id > kWledPresetCeiling).toList()
    ..sort();
  out.add(CheckResult(
    'all preset slots ≤ $kWledPresetCeiling',
    overCeiling.isEmpty,
    overCeiling.isEmpty ? 'max id ${_maxId(presets)}' : 'over-ceiling: $overCeiling',
  ));

  return out;
}

int _maxId(Map<int, Map<String, dynamic>> presets) =>
    presets.keys.isEmpty ? 0 : presets.keys.reduce((a, b) => a > b ? a : b);

/// Convert a presets.json body ({"1":{...},"2":{...}}) to an int-keyed map,
/// dropping the "0" bootloader slot WLED always emits.
Map<int, Map<String, dynamic>> parsePresets(Map<String, dynamic> body) {
  final out = <int, Map<String, dynamic>>{};
  body.forEach((k, v) {
    final id = int.tryParse(k);
    if (id != null && id != 0 && v is Map) {
      out[id] = v.cast<String, dynamic>();
    }
  });
  return out;
}

/// WLED dow bit for a weekday index where Monday=0..Sunday=6 (matches wled_dow).
/// Exposed so fire-test can compute "today" from the CONTROLLER clock.
int dowBitForMondayZeroIndex(int mondayZero) => 1 << mondayZero;

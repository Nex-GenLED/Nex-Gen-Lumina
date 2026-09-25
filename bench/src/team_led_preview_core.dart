// Pure logic for the team LED preview (bench/bin/team_led_preview.dart).
//
// No I/O here beyond parsing strings handed in, so every rule that keeps the
// preview safe is unit-tested (test/bench/team_led_preview_core_test.dart):
//   • the live home controller is refused by address, before and after connect;
//   • a payload can only ever be LIVE state — no preset, playlist, reboot or
//     config key survives [assertLiveStateOnly];
//   • the restore payload is the exact inverse of what a preview touches, and
//     [restoreDiff] proves it landed.

import 'dart:math' as math;

import 'package:nexgen_command/data/team_led_colors.dart';

/// Tyler's LIVE home controller. Never a preview target.
const String kLiveHomeControllerIp = '192.168.1.150';

/// The spare, unregistered bench controller.
const String kSpareControllerIp = '192.168.1.173';

/// Keys that would persist, load or reboot. A preview is live state only, so
/// none of these may appear anywhere in a payload. `ps`/`pl` only LOAD, but a
/// preview has no reason to touch presets at all.
const Set<String> kForbiddenAnywhere = {
  'psave', 'pdel', 'ps', 'pl', 'playlist', 'rb',
};

/// Top-level keys that only mean something alongside a preset save (`ib`,
/// `sb`, `n`, `ql`) or advance a playlist (`np`).
const Set<String> kForbiddenTopLevel = {'ib', 'sb', 'n', 'ql', 'np'};

/// The segment fields a preview writes — and therefore the only ones restore
/// puts back. Anything else on the segment is never touched.
const List<String> kTouchedSegFields = [
  'on', 'frz', 'bri', 'grp', 'spc', 'of', 'fx', 'sx', 'ix', 'pal', 'col',
];

/// Refuses the live home controller. [resolved] are the addresses [host]
/// resolved to (a hostname can point at it too).
String? refuseHost(String host, {List<String> resolved = const []}) {
  if (host.trim() == kLiveHomeControllerIp ||
      resolved.contains(kLiveHomeControllerIp)) {
    return 'REFUSED: $kLiveHomeControllerIp is the live home controller. '
        'The preview only ever targets the spare ($kSpareControllerIp).';
  }
  return null;
}

/// Refuses a controller whose own /json/info reports the live home address.
String? refuseInfo(Map<String, dynamic> info) {
  if (info['ip'] == kLiveHomeControllerIp) {
    return 'REFUSED: the controller reports ip $kLiveHomeControllerIp — that '
        'is the live home controller.';
  }
  return null;
}

/// Throws [StateError] if [payload] could persist, load, or reboot anything.
void assertLiveStateOnly(Map<String, dynamic> payload) {
  for (final k in payload.keys) {
    if (kForbiddenTopLevel.contains(k)) {
      throw StateError('refusing to send "$k" — live state only');
    }
  }
  void walk(Object? node) {
    if (node is Map) {
      for (final e in node.entries) {
        if (kForbiddenAnywhere.contains(e.key)) {
          throw StateError('refusing to send "${e.key}" — live state only');
        }
        walk(e.value);
      }
    } else if (node is List) {
      node.forEach(walk);
    }
  }

  walk(payload);
}

/// One kTeamColors entry, parsed from source (the bench runs under plain
/// `dart run`, which cannot load the Flutter-typed table itself).
class PreviewTeam {
  const PreviewTeam(this.slug, this.name, this.primary, this.secondary);

  final String slug;
  final String name;

  /// Brand colours, 0xRRGGBB.
  final int primary;
  final int secondary;

  String get league => slug.split('_').first;
}

final RegExp _teamEntry = RegExp(
  r"'([a-z0-9_]+)':\s*TeamColors\(\s*"
  r'primary:\s*Color\(0x[Ff]{2}([0-9A-Fa-f]{6})\),\s*'
  r'secondary:\s*Color\(0x[Ff]{2}([0-9A-Fa-f]{6})\),\s*'
  r'''teamName:\s*(?:'((?:[^'\\]|\\.)*)'|"([^"]*)")''',
);

/// Parse lib/features/sports_alerts/data/team_colors.dart. Source order, with
/// the Packers moved to the front — the owner's bug goes first.
List<PreviewTeam> parseTeams(String teamColorsSource) {
  final teams = <PreviewTeam>[
    for (final m in _teamEntry.allMatches(teamColorsSource))
      PreviewTeam(
        m.group(1)!,
        (m.group(4) ?? m.group(5)!).replaceAll(r"\'", "'"),
        int.parse(m.group(2)!, radix: 16),
        int.parse(m.group(3)!, radix: 16),
      ),
  ];
  final i = teams.indexWhere((t) => t.slug == 'nfl_packers');
  if (i > 0) teams.insert(0, teams.removeAt(i));
  return teams;
}

final RegExp _ledLine = RegExp(r'^\s*0x([0-9A-Fa-f]{6}): LedRgb\([^)]*\), // (.*?) ·');

/// Brand hex → problem class, from the trailing comments in
/// lib/data/team_led_colors.dart (display only; values come from the import).
Map<int, String> parseProblemClasses(String teamLedSource) => {
      for (final line in teamLedSource.split('\n'))
        if (_ledLine.firstMatch(line) case final m?)
          int.parse(m.group(1)!, radix: 16): m.group(2)!,
    };

/// Narrow [teams] to [leagues] (slug prefixes, e.g. `nfl`, `ncaa`) and start
/// at [startSlug]. Empty [leagues] keeps every league.
List<PreviewTeam> selectTeams(
  List<PreviewTeam> teams, {
  List<String> leagues = const [],
  String? startSlug,
}) {
  var out = leagues.isEmpty
      ? teams
      : teams.where((t) => leagues.contains(t.league)).toList();
  if (startSlug != null) {
    final i = out.indexWhere((t) => t.slug == startSlug);
    if (i < 0) throw ArgumentError.value(startSlug, 'start', 'not in the list');
    out = out.sublist(i);
  }
  return out;
}

/// What the strip shows.
enum PreviewView {
  /// Alternating primary/secondary bands — the two-colour Game Day look.
  blocks,
  primary,
  secondary,
}

/// `[r, g, b]` for one colour of [team], as the LED value (what ships) or the
/// brand hex (what shipped before — the A/B comparison).
List<int> previewRgb(int brand, {required bool led}) {
  if (led) return teamLedRgb(brand).toRgb();
  return [(brand >> 16) & 0xFF, (brand >> 8) & 0xFF, brand & 0xFF];
}

/// Apply WLED colour gamma 2.8 in software — for a controller whose own colour
/// gamma is OFF, so the preview still looks like the fleet.
List<int> emulateGamma(List<int> rgb) => [
      for (final v in rgb) (255 * math.pow(v / 255, 2.8)).round().clamp(0, 255),
    ];

/// The live-state preview payload for existing segments [segIds].
///
/// `tt: 0` is a one-shot instant transition (not persisted, nothing to
/// restore). grp/spc/of are pinned so a leftover spacing cannot fake a colour.
Map<String, dynamic> buildPreviewPayload({
  required List<int> segIds,
  required PreviewView view,
  required List<int> primaryRgb,
  required List<int> secondaryRgb,
  required int bri,
  required int blockSize,
}) {
  final p = [...primaryRgb, 0];
  final s = [...secondaryRgb, 0];
  const off = [0, 0, 0, 0];
  final (fx, col) = switch (view) {
    PreviewView.blocks => (83, [p, s, off]), // Solid Pattern: col0 / col1 bands
    PreviewView.primary => (0, [p, s, off]), // Solid: col0
    PreviewView.secondary => (0, [s, p, off]),
  };
  final band = (blockSize - 1).clamp(0, 255);
  final payload = <String, dynamic>{
    'on': true,
    'bri': bri.clamp(1, 255),
    'tt': 0,
    'seg': [
      for (final id in segIds)
        {
          'id': id,
          'on': true,
          'frz': false,
          'bri': 255,
          'grp': 1,
          'spc': 0,
          'of': 0,
          'fx': fx,
          'sx': band,
          'ix': band,
          'pal': 0,
          'col': col,
        },
    ],
  };
  assertLiveStateOnly(payload);
  return payload;
}

/// Segment ids present in a captured /json/state (`seg` may be a list or a
/// single map depending on firmware).
List<int> segIdsOf(Map<String, dynamic> state) {
  final seg = state['seg'];
  final list = seg is List ? seg : (seg is Map ? [seg] : const []);
  return [
    for (final s in list)
      if (s is Map && s['id'] is num) (s['id'] as num).toInt(),
  ];
}

List<Map<String, dynamic>> _segs(Map<String, dynamic> state) {
  final seg = state['seg'];
  final list = seg is List ? seg : (seg is Map ? [seg] : const []);
  return [for (final s in list) if (s is Map) s.cast<String, dynamic>()];
}

/// The exact inverse of every preview: master on/bri, and on each captured
/// segment only the [kTouchedSegFields].
Map<String, dynamic> buildRestorePayload(Map<String, dynamic> captured) {
  final payload = <String, dynamic>{
    if (captured.containsKey('on')) 'on': captured['on'],
    if (captured.containsKey('bri')) 'bri': captured['bri'],
    'tt': 0,
    'seg': [
      for (final s in _segs(captured))
        {
          'id': s['id'],
          for (final f in kTouchedSegFields)
            if (s.containsKey(f)) f: s[f],
        },
    ],
  };
  assertLiveStateOnly(payload);
  return payload;
}

/// Fields that differ between the capture and a post-restore readback. Empty
/// means the controller is back exactly as found (for everything the preview
/// can touch).
List<String> restoreDiff(
  Map<String, dynamic> captured,
  Map<String, dynamic> readback,
) {
  final out = <String>[];
  for (final k in const ['on', 'bri']) {
    if ('${captured[k]}' != '${readback[k]}') {
      out.add('$k: ${captured[k]} → ${readback[k]}');
    }
  }
  final after = {for (final s in _segs(readback)) s['id']: s};
  for (final s in _segs(captured)) {
    final r = after[s['id']];
    if (r == null) {
      out.add('seg ${s['id']}: missing after restore');
      continue;
    }
    for (final f in kTouchedSegFields) {
      if ('${s[f]}' != '${r[f]}') {
        out.add('seg ${s['id']}.$f: ${s[f]} → ${r[f]}');
      }
    }
  }
  return out;
}

String hex6(int rgb) =>
    '#${(rgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

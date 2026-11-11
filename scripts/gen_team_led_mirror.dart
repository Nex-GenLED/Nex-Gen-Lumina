// Regenerates the server mirror of the team LED table from the Dart source of
// truth. Never edit functions/src/teamLedColors.ts by hand.
//
//   dart run scripts/gen_team_led_mirror.dart          # rewrite the mirror
//   dart run scripts/gen_team_led_mirror.dart --check  # exit 1 if it drifted
//
// Only the map body between `>([` and `]);` is rewritten; the file's header,
// types and teamLedRgb() stay as they are. test/data/team_led_colors_test.dart
// ("server mirror") fails if the two files drift.
//
// The mirror is NOT imported by any deployed function in build 124. Wiring the
// planner to it (b9eac14 on fix/team-led-colors-2026-09-24) is a separate,
// gated functions deploy.
import 'dart:io';

import 'package:nexgen_command/data/team_led_colors.dart';

const _mirrorPath = 'functions/src/teamLedColors.ts';

String _hex6(int v) => v.toRadixString(16).toUpperCase().padLeft(6, '0');

void main(List<String> args) {
  final check = args.contains('--check');
  final file = File(_mirrorPath);
  if (!file.existsSync()) {
    stderr.writeln('$_mirrorPath not found — run from the repo root.');
    exit(2);
  }
  final src = file.readAsStringSync();
  const open = '>([\n';
  const close = '\n]);\n';
  final start = src.indexOf(open);
  final end = start < 0 ? -1 : src.indexOf(close, start);
  if (start < 0 || end < 0) {
    stderr.writeln('$_mirrorPath: map block (`>([` … `]);`) not found.');
    exit(2);
  }

  final keys = kTeamLedRgb.keys.toList()..sort();
  final body = [
    for (final k in keys)
      '  [0x${_hex6(k)}, [${kTeamLedRgb[k]!.r}, ${kTeamLedRgb[k]!.g}, '
          '${kTeamLedRgb[k]!.b}]],',
  ].join('\n');
  final out =
      src.substring(0, start + open.length) + body + src.substring(end);

  if (check) {
    if (out != src) {
      stderr.writeln('$_mirrorPath has drifted from lib/data/team_led_colors.dart '
          '— run: dart run scripts/gen_team_led_mirror.dart');
      exit(1);
    }
    stdout.writeln('$_mirrorPath matches (${keys.length} entries).');
    return;
  }
  file.writeAsStringSync(out);
  stdout.writeln('wrote $_mirrorPath (${keys.length} entries).');
}

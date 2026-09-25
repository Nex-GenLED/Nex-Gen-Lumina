// Team LED colour bench preview.
//
//   dart run bench/bin/team_led_preview.dart [--league nfl,nba] [--start nfl_bears]
//
// Pushes ONE team's colours at a time to the SPARE controller (192.168.1.173)
// as live /json/state, steps through the teams on a keypress, and records the
// owner's keep / adjust verdicts to bench/state/team_led_notes.jsonl. The LED
// values come from the real table (lib/data/team_led_colors.dart), so what is
// reviewed is exactly what ships.
//
// HARD RULES, enforced in code (bench/src/team_led_preview_core.dart):
//   • never 192.168.1.150 (the live home controller) — refused by address, by
//     resolved address, and by the controller's own reported ip;
//   • POST /json/state only; this client has no other write. Every payload is
//     checked for psave/pdel/ps/pl/playlist/rb/ib/sb/n/ql/np before it goes;
//   • the original state is captured before the first write (and saved to
//     bench/state/team_led_preview_capture.json) and restored on quit, on
//     Ctrl+C, and on any error; the restore is read back and diffed.
//
// Keys: n/Enter next · p prev · b both (bands) · 1 primary · 2 secondary
//       o original brand hex (A/B toggle) · k keep → next · a adjust (note)
//       s skip · q quit
//
// Other modes:
//   --list                   print the team order and exit (no network)
//   --smoke                  non-interactive self-check: capture → Packers LED
//                            → readback → restore → diff, then exit
//   --restore-from <file>    re-apply a saved capture (if a run was killed)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nexgen_command/data/team_led_colors.dart';

import '../src/team_led_preview_core.dart';

const _usage = '''
usage: dart run bench/bin/team_led_preview.dart [options]
  --host <ip>            target (default $kSpareControllerIp; $kLiveHomeControllerIp is refused)
  --league <a,b>         slug prefixes: nfl nba mlb nhl mls nwsl wnba ncaa ncaamb fifa cl
  --start <slug>         begin at this team (e.g. nfl_bears)
  --bri <1-255>          master brightness for the preview (default 128)
  --block <n>            band width in LEDs for the two-colour view (default 15)
  --notes <path>         verdict log (default bench/state/team_led_notes.jsonl)
  --emulate-gamma        apply colour gamma 2.8 in software (use only if the
                         controller's own colour gamma is OFF)
  --yes                  skip the "is this the right controller?" prompt
  --list | --smoke | --restore-from <file>
''';

Future<void> main(List<String> argv) async {
  final a = _Args(argv);
  if (a.flag('help') || a.flag('h')) {
    stdout.write(_usage);
    return;
  }

  final root = _repoRoot();
  final teams = parseTeams(File(
          '${root.path}/lib/features/sports_alerts/data/team_colors.dart')
      .readAsStringSync());
  final classes = parseProblemClasses(
      File('${root.path}/lib/data/team_led_colors.dart').readAsStringSync());
  final leagues = (a.opt('league') ?? '')
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();
  final selected = selectTeams(teams, leagues: leagues, startSlug: a.opt('start'));

  if (a.flag('list')) {
    for (final (i, t) in selected.indexed) {
      stdout.writeln('${(i + 1).toString().padLeft(4)}  ${t.slug.padRight(28)} '
          '${t.name}');
    }
    return;
  }

  final host = a.opt('host') ?? kSpareControllerIp;
  final resolved = <String>[];
  try {
    resolved.addAll(
        (await InternetAddress.lookup(host)).map((x) => x.address));
  } catch (_) {/* an IP literal needs no lookup */}
  final refused = refuseHost(host, resolved: resolved);
  if (refused != null) {
    stderr.writeln(refused);
    exitCode = 3;
    return;
  }

  final wled = _StateOnlyClient('http://$host');
  try {
    final info = await wled.get('/json/info');
    if (info == null) {
      stderr.writeln('No answer from $host/json/info.');
      exitCode = 1;
      return;
    }
    final refusedInfo = refuseInfo(info);
    if (refusedInfo != null) {
      stderr.writeln(refusedInfo);
      exitCode = 3;
      return;
    }
    final cfg = await wled.get('/json/cfg'); // READ only — never posted
    final gammaCol = ((cfg?['light'] as Map?)?['gc'] as Map?)?['col'];
    stdout.writeln('Controller: "${info['name']}"  WLED ${info['ver']}  '
        '${(info['leds'] as Map?)?['count']} LEDs  ip ${info['ip'] ?? host}');
    stdout.writeln('Colour gamma (light.gc.col): $gammaCol  '
        '(the table assumes the fleet standard 2.8)');
    final emulate = a.flag('emulate-gamma');
    if (gammaCol is num && (gammaCol - 2.8).abs() > 0.05 && !emulate) {
      stdout.writeln('  ! colour gamma is not 2.8 here, so this preview will not '
          'match customer controllers. Re-run with --emulate-gamma, or set it in '
          'WLED → LED Preferences yourself (this tool never writes config).');
    }

    if (a.opt('restore-from') case final path?) {
      final saved = jsonDecode(File(path).readAsStringSync()) as Map;
      final captured = (saved['state'] as Map).cast<String, dynamic>();
      exitCode = await _restore(wled, captured) ? 0 : 1;
      return;
    }

    final captured = await wled.get('/json/state');
    if (captured == null) {
      stderr.writeln('Could not read /json/state — nothing written.');
      exitCode = 1;
      return;
    }
    final segIds = segIdsOf(captured);
    if (segIds.isEmpty) {
      stderr.writeln('No segments in /json/state — nothing written.');
      exitCode = 1;
      return;
    }
    final backup = File('${root.path}/bench/state/team_led_preview_capture.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'captured_at': DateTime.now().toIso8601String(),
        'host': host,
        'state': captured,
      }));
    stdout.writeln('Captured original state → ${_rel(root, backup)}');

    final keys = _Keys();
    if (!a.flag('yes') && !a.flag('smoke')) {
      final answer =
          await keys.line('Preview on THIS controller? Type y to continue: ');
      if (answer.trim().toLowerCase() != 'y') {
        stdout.writeln('Nothing written.');
        await keys.close();
        return;
      }
    }

    bool? restored;
    Future<bool> restoreOnce() async =>
        restored ??= await _restore(wled, captured);

    final sigint = ProcessSignal.sigint.watch().listen((_) async {
      stdout.writeln('\nCtrl+C — restoring the controller…');
      await restoreOnce();
      await keys.close();
      exit(130);
    });

    try {
      final opts = _PreviewOptions(
        bri: int.tryParse(a.opt('bri') ?? '') ?? 128,
        block: int.tryParse(a.opt('block') ?? '') ?? 15,
        emulateGamma: emulate,
        segIds: segIds,
        gammaCol: gammaCol,
        host: host,
      );
      if (a.flag('smoke')) {
        if (!await _smoke(wled, opts)) exitCode = 1;
      } else {
        final notes = File(a.opt('notes') ??
            '${root.path}/bench/state/team_led_notes.jsonl')
          ..createSync(recursive: true);
        await _interactive(wled, keys, selected, classes, opts, notes, root);
      }
    } catch (e) {
      stderr.writeln('Error: $e');
      exitCode = 1;
    } finally {
      if (!await restoreOnce()) exitCode = 1;
      await sigint.cancel();
      await keys.close();
    }
  } finally {
    wled.close();
  }
}

class _PreviewOptions {
  _PreviewOptions({
    required this.bri,
    required this.block,
    required this.emulateGamma,
    required this.segIds,
    required this.gammaCol,
    required this.host,
  });
  final int bri;
  final int block;
  final bool emulateGamma;
  final List<int> segIds;
  final Object? gammaCol;
  final String host;
}

Map<String, dynamic> _payloadFor(
  PreviewTeam t,
  PreviewView view,
  bool led,
  _PreviewOptions o,
) {
  List<int> rgb(int brand) {
    final v = previewRgb(brand, led: led);
    return o.emulateGamma ? emulateGamma(v) : v;
  }

  return buildPreviewPayload(
    segIds: o.segIds,
    view: view,
    primaryRgb: rgb(t.primary),
    secondaryRgb: rgb(t.secondary),
    bri: o.bri,
    blockSize: o.block,
  );
}

Future<void> _interactive(
  _StateOnlyClient wled,
  _Keys keys,
  List<PreviewTeam> teams,
  Map<int, String> classes,
  _PreviewOptions o,
  File notes,
  Directory root,
) async {
  if (teams.isEmpty) {
    stdout.writeln('No teams match.');
    return;
  }
  stdout.writeln('\nKeys: n/Enter next · p prev · b both · 1 primary · '
      '2 secondary · o brand A/B · k keep · a adjust · s skip · q quit');
  stdout.writeln('Verdicts → ${_rel(root, notes)}\n');
  var i = 0;
  var view = PreviewView.blocks;
  var led = true;
  var lastShown = '';

  Future<void> show() async {
    final t = teams[i];
    final ok = await wled.postState(_payloadFor(t, view, led, o));
    final p = teamLedRgb(t.primary).toRgb();
    final s = teamLedRgb(t.secondary).toRgb();
    final header = '[${i + 1}/${teams.length}] ${t.name} (${t.slug})';
    if (header != lastShown) {
      stdout.writeln(header);
      stdout.writeln('   primary   ${hex6(t.primary)} → LED $p  '
          '${classes[t.primary] ?? '(not in table — brand sent)'}');
      stdout.writeln('   secondary ${hex6(t.secondary)} → LED $s  '
          '${classes[t.secondary] ?? '(not in table — brand sent)'}');
      lastShown = header;
    }
    stdout.writeln('   showing: ${led ? 'LED' : 'BRAND (old)'} · ${view.name}'
        '${ok ? '' : '  ! POST failed'}');
  }

  Future<void> record(String verdict, String note) async {
    final t = teams[i];
    notes.writeAsStringSync(
      '${jsonEncode({
        'ts': DateTime.now().toIso8601String(),
        'host': o.host,
        'slug': t.slug,
        'team': t.name,
        'verdict': verdict,
        'note': note,
        'view': view.name,
        'gamma_col': o.gammaCol,
        'emulated_gamma': o.emulateGamma,
        'brand': {'primary': hex6(t.primary), 'secondary': hex6(t.secondary)},
        'led': {
          'primary': teamLedRgb(t.primary).toRgb(),
          'secondary': teamLedRgb(t.secondary).toRgb(),
        },
        'class': {
          'primary': classes[t.primary],
          'secondary': classes[t.secondary],
        },
      })}\n',
      mode: FileMode.append,
    );
    stdout.writeln('   recorded: $verdict${note.isEmpty ? '' : ' — $note'}');
  }

  await show();
  while (true) {
    final k = (await keys.key()).toLowerCase();
    switch (k) {
      case 'q':
        return;
      case 'n' || '\r' || '\n' || ' ':
        if (i < teams.length - 1) {
          i++;
          led = true;
          view = PreviewView.blocks;
        } else {
          stdout.writeln('   (last team)');
        }
      case 'p':
        if (i > 0) {
          i--;
          led = true;
          view = PreviewView.blocks;
        }
      case 'b':
        view = PreviewView.blocks;
      case '1':
        view = PreviewView.primary;
      case '2':
        view = PreviewView.secondary;
      case 'o':
        led = !led;
      case 'k':
        await record('keep', '');
        if (i < teams.length - 1) {
          i++;
          led = true;
          view = PreviewView.blocks;
        }
      case 'a':
        final note = await keys.line(
            '   adjust note (e.g. "primary: less blue"): ');
        await record('adjust', note.trim());
        continue; // stay on this team
      case 's':
        if (i < teams.length - 1) i++;
      default:
        continue;
    }
    await show();
  }
}

/// Non-interactive self-check on the real controller: push the Packers LED
/// colours and read them back. The caller's `finally` restores and diffs.
Future<bool> _smoke(_StateOnlyClient wled, _PreviewOptions o) async {
  const packers = PreviewTeam('nfl_packers', 'Green Bay Packers', 0x203731, 0xFFB612);
  final payload = _payloadFor(packers, PreviewView.blocks, true, o);
  final posted = await wled.postState(payload);
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final after = await wled.get('/json/state');
  final seg0 = ((after?['seg'] as List?)?.first as Map?) ?? const {};
  final col = (seg0['col'] as List?)?.cast<List>() ?? const [];
  final landed = col.length >= 2 &&
      '${col[0].take(3).toList()}' == '${teamLedRgb(0x203731).toRgb()}' &&
      '${col[1].take(3).toList()}' == '${teamLedRgb(0xFFB612).toRgb()}' &&
      seg0['fx'] == 83;
  stdout.writeln('smoke: POST ${posted ? 'ok' : 'FAILED'} · readback '
      'fx ${seg0['fx']} col ${col.take(2).toList()} → '
      '${landed ? 'Packers LED landed' : 'MISMATCH'}');
  return posted && landed;
}

Future<bool> _restore(_StateOnlyClient wled, Map<String, dynamic> captured) async {
  final ok = await wled.postState(buildRestorePayload(captured));
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final readback = await wled.get('/json/state');
  if (!ok || readback == null) {
    stderr.writeln('RESTORE: POST ${ok ? 'ok' : 'FAILED'}, readback '
        '${readback == null ? 'FAILED' : 'ok'} — re-run with --restore-from '
        'bench/state/team_led_preview_capture.json');
    return false;
  }
  final diff = restoreDiff(captured, readback);
  if (diff.isEmpty) {
    stdout.writeln('RESTORE: controller back exactly as found '
        '(on, bri, and every segment field the preview touches).');
    return true;
  }
  stderr.writeln('RESTORE: differences remain:\n  ${diff.join('\n  ')}');
  return false;
}

/// GET anything; POST only /json/state, and only after [assertLiveStateOnly].
/// There is deliberately no cfg or preset write in this client.
class _StateOnlyClient {
  _StateOnlyClient(this.base) {
    _http.connectionTimeout = const Duration(seconds: 5);
  }

  final String base;
  final HttpClient _http = HttpClient();

  void close() => _http.close(force: true);

  Future<Map<String, dynamic>?> get(String path) async {
    try {
      final req = await _http.getUrl(Uri.parse('$base$path'));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200 || body.trim().isEmpty) return null;
      final d = jsonDecode(body);
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> postState(Map<String, dynamic> payload) async {
    assertLiveStateOnly(payload);
    try {
      final req = await _http.postUrl(Uri.parse('$base/json/state'));
      final bytes = utf8.encode(jsonEncode(payload));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.contentLength = bytes.length; // WLED rejects chunked encoding
      req.add(bytes);
      final res = await req.close().timeout(const Duration(seconds: 8));
      await res.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}

/// Single keypresses when the terminal allows raw mode (Windows console,
/// macOS/Linux terminals); otherwise type the key and press Enter.
class _Keys {
  _Keys() {
    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
      _raw = true;
    } catch (_) {
      _raw = false;
    }
    _sub = stdin.transform(utf8.decoder).listen((chunk) {
      for (final ch in chunk.split('')) {
        _queue.add(ch);
      }
      _wake?.complete();
      _wake = null;
    });
  }

  late final bool _raw;
  late final StreamSubscription<String> _sub;
  final List<String> _queue = [];
  Completer<void>? _wake;

  Future<String> _next() async {
    while (_queue.isEmpty) {
      _wake = Completer<void>();
      await _wake!.future;
    }
    return _queue.removeAt(0);
  }

  Future<String> key() async {
    if (_raw) {
      final ch = await _next();
      if (ch == '\x03') return 'q'; // Ctrl+C in raw mode
      return ch;
    }
    final l = await line('');
    return l.isEmpty ? '\n' : l.substring(0, 1);
  }

  Future<String> line(String prompt) async {
    stdout.write(prompt);
    final buf = StringBuffer();
    while (true) {
      final ch = await _next();
      if (ch == '\r' || ch == '\n') {
        if (_raw) stdout.writeln();
        if (!_raw && ch == '\r') continue;
        return buf.toString();
      }
      if (_raw && (ch == '\x7f' || ch == '\b')) {
        final s = buf.toString();
        if (s.isNotEmpty) {
          buf
            ..clear()
            ..write(s.substring(0, s.length - 1));
          stdout.write('\b \b');
        }
        continue;
      }
      buf.write(ch);
      if (_raw) stdout.write(ch);
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    if (_raw) {
      try {
        stdin.lineMode = true;
        stdin.echoMode = true;
      } catch (_) {}
    }
  }
}

class _Args {
  _Args(List<String> argv) {
    for (var i = 0; i < argv.length; i++) {
      final a = argv[i];
      if (!a.startsWith('--')) continue;
      final name = a.substring(2);
      final hasValue = i + 1 < argv.length && !argv[i + 1].startsWith('--');
      _m[name] = hasValue ? argv[++i] : 'true';
    }
  }

  final Map<String, String> _m = {};
  String? opt(String k) => _m[k] == 'true' ? null : _m[k];
  bool flag(String k) => _m.containsKey(k);
}

Directory _repoRoot() {
  var d = Directory.current;
  while (!File('${d.path}/pubspec.yaml').existsSync()) {
    final up = d.parent;
    if (up.path == d.path) {
      throw StateError('run from inside the repo');
    }
    d = up;
  }
  return d;
}

String _rel(Directory root, File f) =>
    f.path.replaceFirst('${root.path}${Platform.pathSeparator}', '')
        .replaceFirst('${root.path}/', '');

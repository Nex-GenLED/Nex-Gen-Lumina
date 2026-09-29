// Per-effect default SPEED bench preview (+110 E1, owner item D).
//
//   dart run bench/bin/effect_speed_preview.dart [--start 91] [--all]
//
// Runs ONE effect at a time on the SPARE controller (192.168.1.173) at the
// speed the app now starts it at (lib/features/wled/pattern_effect_speeds.dart
// — imported, so what is reviewed is what ships), lets the owner nudge it
// slower or faster and A/B it against WLED's desk default (128), and records
// keep / adjust verdicts to bench/state/effect_speed_notes.jsonl. The owner's
// nine "too fast" effects come first.
//
// HARD RULES, enforced in code (bench/src/effect_speed_preview_core.dart):
//   • never 192.168.1.150 (the live home controller) — refused by address, by
//     resolved address, and by the controller's own reported ip;
//   • POST /json/state only; this client has no other write. Every payload is
//     checked for psave/pdel/ps/pl/playlist/rb/ib/sb/n/ql/np before it goes;
//   • the original state is captured before the first write (and saved to
//     bench/state/effect_speed_preview_capture.json) and restored on quit, on
//     Ctrl+C, and on any error; the restore is read back and diffed;
//   • full-field strobes (Strobe, Strobe Rainbow, Strobe Mega) are left out
//     unless --include-flash, and even then never sent above ~3 Hz (speed
//     capped at 240; Strobe Mega at one flash per burst).
//
// Keys: n/Enter next · p prev · + faster · - slower (5 at a time; shift for
//       20: ] and [) · r back to the table value · w WLED's 128 (A/B) ·
//       k keep → next · a adjust (records the CURRENT speed + a note) ·
//       s skip · q quit
//
// Other modes:
//   --list                   print the effect order and table speeds, then exit
//   --smoke                  non-interactive self-check: capture → Juggle at its
//                            table speed → readback → restore → diff, then exit
//   --restore-from <file>    re-apply a saved capture (if a run was killed)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';

import '../src/effect_speed_preview_core.dart';

const _usage = '''
usage: dart run bench/bin/effect_speed_preview.dart [options]
  --host <ip>            target (default $kSpareControllerIp; $kLiveHomeControllerIp is refused)
  --start <fx>           begin at this effect id (e.g. 91)
  --all                  include 2D and audio effects (not offered on a 1D roofline)
  --include-flash        include Strobe / Strobe Rainbow / Strobe Mega (capped, see header)
  --bri <1-255>          master brightness for the preview (default 128)
  --notes <path>         verdict log (default bench/state/effect_speed_notes.jsonl)
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
  final notesById = parseTableNotes(
      File('${root.path}/lib/features/wled/pattern_effect_speeds.dart')
          .readAsStringSync());
  var effects = previewEffects(
    includeFlash: a.flag('include-flash'),
    includeAll: a.flag('all'),
    notes: notesById,
  );
  if (int.tryParse(a.opt('start') ?? '') case final start?) {
    final i = effects.indexWhere((e) => e.id == start);
    if (i < 0) {
      stderr.writeln('Effect $start is not in the list (see --list).');
      exitCode = 2;
      return;
    }
    effects = effects.sublist(i);
  }

  if (a.flag('list')) {
    for (final (i, e) in effects.indexed) {
      stdout.writeln('${(i + 1).toString().padLeft(4)}  fx ${e.id.toString().padLeft(3)}  '
          '${e.name.padRight(22)} '
          '${e.speedIsPace ? 'sx ${e.speed.toString().padLeft(3)}' : 'sx  — '}'
          '${e.intensity != null ? '  ix ${e.intensity}' : ''}'
          '${e.isFlash ? '  FLASH' : ''}  ${e.note}');
    }
    return;
  }

  final host = a.opt('host') ?? kSpareControllerIp;
  final resolved = <String>[];
  try {
    resolved.addAll((await InternetAddress.lookup(host)).map((x) => x.address));
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
    stdout.writeln('Controller: "${info['name']}"  WLED ${info['ver']}  '
        '${(info['leds'] as Map?)?['count']} LEDs  ip ${info['ip'] ?? host}');

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
    final backup =
        File('${root.path}/bench/state/effect_speed_preview_capture.json')
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
      final bri = int.tryParse(a.opt('bri') ?? '') ?? 128;
      if (a.flag('smoke')) {
        if (!await _smoke(wled, segIds, bri)) exitCode = 1;
      } else {
        final notes = File(a.opt('notes') ??
            '${root.path}/bench/state/effect_speed_notes.jsonl')
          ..createSync(recursive: true);
        await _interactive(wled, keys, effects, segIds, bri, host, notes, root);
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

Future<void> _interactive(
  _StateOnlyClient wled,
  _Keys keys,
  List<PreviewEffect> effects,
  List<int> segIds,
  int bri,
  String host,
  File notes,
  Directory root,
) async {
  if (effects.isEmpty) {
    stdout.writeln('No effects match.');
    return;
  }
  stdout.writeln('\nKeys: n/Enter next · p prev · + faster · - slower '
      '(] [ by 20) · r table value · w WLED 128 · k keep · a adjust · '
      's skip · q quit');
  stdout.writeln('Verdicts → ${_rel(root, notes)}\n');
  var i = 0;
  late int sx;
  late int ix;
  var lastHeader = '';

  void reset() {
    final e = effects[i];
    sx = e.speed ?? 128;
    ix = e.intensity ?? 128;
  }

  Future<void> show() async {
    final e = effects[i];
    final safe = clampFlashForPreview(e.id, sx, ix);
    sx = safe.sx;
    ix = safe.ix;
    final ok = await wled.postState(
        buildPreviewPayload(segIds: segIds, fx: e.id, sx: sx, ix: ix, bri: bri));
    final header = '[${i + 1}/${effects.length}] fx ${e.id} ${e.name}';
    if (header != lastHeader) {
      stdout.writeln(header);
      stdout.writeln('   table: ${e.speedIsPace ? 'sx ${e.speed}' : 'speed is not a pace here'}'
          '${e.intensity != null ? ' · ix ${e.intensity}' : ''} '
          '(slider ${e.sliderMin}–${e.sliderMax})  ${e.note}');
      if (e.isFlash) {
        stdout.writeln('   ! FLASH — photosensitivity risk. The preview is capped '
            'at sx $kFlashPreviewMaxSpeed'
            '${e.id == 25 ? ' and one flash per burst' : ''}.');
      }
      lastHeader = header;
    }
    stdout.writeln('   showing sx $sx ix $ix${safe.capped ? ' (capped for safety)' : ''}'
        '${ok ? '' : '  ! POST failed'}');
  }

  Future<void> record(String verdict, String note) async {
    final e = effects[i];
    notes.writeAsStringSync(
      '${jsonEncode({
        'ts': DateTime.now().toIso8601String(),
        'host': host,
        'fx': e.id,
        'effect': e.name,
        'verdict': verdict,
        'note': note,
        'table_sx': e.speed,
        'table_ix': e.intensity,
        'reviewed_sx': sx,
        'reviewed_ix': ix,
        'flash': e.isFlash,
      })}\n',
      mode: FileMode.append,
    );
    stdout.writeln('   recorded: $verdict at sx $sx${note.isEmpty ? '' : ' — $note'}');
  }

  reset();
  await show();
  while (true) {
    final k = await keys.key();
    switch (k) {
      case 'q' || 'Q':
        return;
      case 'n' || '\r' || '\n' || ' ':
        if (i < effects.length - 1) {
          i++;
          reset();
        } else {
          stdout.writeln('   (last effect)');
        }
      case 'p':
        if (i > 0) {
          i--;
          reset();
        }
      case '+' || '=':
        sx = (sx + 5).clamp(0, 255);
      case '-' || '_':
        sx = (sx - 5).clamp(0, 255);
      case ']':
        sx = (sx + 20).clamp(0, 255);
      case '[':
        sx = (sx - 20).clamp(0, 255);
      case 'r':
        reset();
      case 'w':
        sx = 128;
      case 'k':
        await record('keep', '');
        if (i < effects.length - 1) {
          i++;
          reset();
        }
      case 'a':
        final note = await keys.line('   adjust note (e.g. "still fast"): ');
        await record('adjust', note.trim());
        continue; // stay on this effect
      case 's':
        if (i < effects.length - 1) {
          i++;
          reset();
        }
      default:
        continue;
    }
    await show();
  }
}

/// Non-interactive self-check on the real controller: run Juggle at its table
/// speed and read it back. The caller's `finally` restores and diffs.
Future<bool> _smoke(_StateOnlyClient wled, List<int> segIds, int bri) async {
  const fx = 64; // Juggle — first of the owner's list
  final sx = effectDefaultSpeed(fx)!;
  final posted = await wled.postState(
      buildPreviewPayload(segIds: segIds, fx: fx, sx: sx, ix: 128, bri: bri));
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final after = await wled.get('/json/state');
  final seg0 = ((after?['seg'] as List?)?.first as Map?) ?? const {};
  final landed = seg0['fx'] == fx && seg0['sx'] == sx;
  stdout.writeln('smoke: POST ${posted ? 'ok' : 'FAILED'} · readback '
      'fx ${seg0['fx']} sx ${seg0['sx']} → '
      '${landed ? 'Juggle at sx $sx landed' : 'MISMATCH'}');
  return posted && landed;
}

Future<bool> _restore(_StateOnlyClient wled, Map<String, dynamic> captured) async {
  final ok = await wled.postState(buildRestorePayload(captured));
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final readback = await wled.get('/json/state');
  if (!ok || readback == null) {
    stderr.writeln('RESTORE: POST ${ok ? 'ok' : 'FAILED'}, readback '
        '${readback == null ? 'FAILED' : 'ok'} — re-run with --restore-from '
        'bench/state/effect_speed_preview_capture.json');
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

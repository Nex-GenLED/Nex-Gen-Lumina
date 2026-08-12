// bench — pure-Dart CLI harness for the Nex-Gen Lumina bench controller.
// Ledger M-21 ("the multiplier"): automates this week's proven verification
// loops, reusing the app's REAL builders (buildCfgPayload, timersInsLanded,
// buildChannelPowerPayload, deviceChannelsFromConfig — all extracted to
// Flutter-free files so this runs under `dart run` with no dart:ui).
//
// Usage:  dart run bench/bin/bench.dart <command> [--ip 192.168.1.150]
//   probe | snapshot | cfg-truth | sync-sim | preset-verify | fire-test |
//   channel-power | restore | all
//
// Exit 0 = all assertions passed, 1 = any failed (CI- / session-gateable).
//
// SAFETY: every mutating command captures state first and restores after.
// Scratch writes touch ONLY the last timer slots and preset ids 245-249; NEVER
// the lease slots (26/28/41), system presets (1-5), or live schedule slots
// (10-25) without a snapshot first.

import 'dart:convert';
import 'dart:io';

import 'package:nexgen_command/features/schedule/timer_landing.dart';
import 'package:nexgen_command/features/schedule/cfg_payload_builder.dart' as cfg;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/channel_power_payload.dart';

import '../src/bench_core.dart';
import '../src/fanout_verify.dart';
import '../src/wled_client.dart';

late WledClient client;
final List<CheckResult> _results = [];
final String _benchDir = _resolveBenchDir();

void _record(CheckResult r) {
  _results.add(r);
  stdout.writeln('  ${r.render()}');
}

void _log(String m) => stdout.writeln(m);

String _resolveBenchDir() {
  // Script lives at bench/bin/bench.dart; bench/ is its parent's parent.
  final script = File.fromUri(Platform.script).absolute.path;
  final binDir = File(script).parent.path;
  return Directory(binDir).parent.path;
}

Map<String, dynamic> _loadJsonFile(String path, Map<String, dynamic> fallback) {
  final f = File(path);
  if (!f.existsSync()) return fallback;
  try {
    final d = jsonDecode(f.readAsStringSync());
    return d is Map ? d.cast<String, dynamic>() : fallback;
  } catch (_) {
    return fallback;
  }
}

String _resolveIp(List<String> args) {
  final ipFlag = args.indexOf('--ip');
  if (ipFlag != -1 && ipFlag + 1 < args.length) return args[ipFlag + 1];
  final cfg = _loadJsonFile('$_benchDir/config.json', const {});
  final ip = cfg['controllerIp'];
  return (ip is String && ip.isNotEmpty) ? ip : '192.168.1.150';
}

// ─────────────────────────────────────────────────────────────────────────
// Commands
// ─────────────────────────────────────────────────────────────────────────

Future<void> cmdProbe({bool update = false}) async {
  _log('▶ probe');
  final info = await client.getInfo();
  final cfg = await client.getCfg();
  if (info == null || cfg == null) {
    _record(const CheckResult('probe reachable', false, 'no /json/info or /json/cfg'));
    return;
  }
  final ver = info['ver'];
  final vid = info['vid'];
  final uptime = info['uptime'];
  final live = parseHwLedFromCfg(cfg);
  _log('  ver=$ver vid=$vid uptime=${uptime}s '
      'layout=${live.totalLeds} LEDs, ${live.buses.length} buses '
      '${live.buses.map((b) => '[${b.start},${b.len}]').join(' ')}');

  final known = layoutFromJson(_loadJsonFile('$_benchDir/known_layout.json', const {}));
  final drift = detectLayoutDrift(known, live);
  if (drift == null) {
    _record(CheckResult('layout matches known_layout.json', true,
        '${live.totalLeds} LEDs, ${live.buses.length} buses'));
  } else if (update) {
    final out = layoutToJson(live);
    out['_comment'] =
        'Last-confirmed hw.led layout for P1-42 drift detection (updated by probe --update).';
    out['confirmedAt'] = DateTime.now().toIso8601String().split('T').first;
    File('$_benchDir/known_layout.json')
        .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
    _record(CheckResult('layout drift → known_layout.json UPDATED', true, drift.summary));
  } else {
    _record(CheckResult('layout drift (P1-42)', false,
        '${drift.summary} — run `probe --update` to confirm'));
  }
}

Future<String?> cmdSnapshot() async {
  _log('▶ snapshot');
  final state = await client.getState();
  final cfg = await client.getCfg();
  final presets = await client.getPresets();
  if (state == null || cfg == null) {
    _record(const CheckResult('snapshot captured', false, 'state/cfg unreadable'));
    return null;
  }
  final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final dir = Directory('$_benchDir/snapshots')..createSync(recursive: true);
  final path = '${dir.path}/snap-$ts.json';
  final snap = {
    'capturedAt': DateTime.now().toIso8601String(),
    'ip': client.base,
    'state': state,
    'timers': timerInsFrom(cfg),
    'presets': presets ?? {},
  };
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(snap));
  _record(CheckResult('snapshot captured', true,
      '${timerInsFrom(cfg).length} timers, ${(presets ?? {}).length} presets → ${path.split('/').last}'));
  return path;
}

/// Read the current timer ins (for capture/restore brackets).
Future<List<Map<String, dynamic>>> _captureTimers() async {
  final cfg = await client.getCfg();
  return cfg == null ? const [] : timerInsFrom(cfg);
}

Future<void> _restoreTimers(List<Map<String, dynamic>> ins, {String label = 'restore timers'}) async {
  final ok = await client.postCfg({'timers': {'ins': ins}});
  final v = await client.patientVerify(
    confirm: () async {
      final cfg = await client.getCfg();
      return cfg != null && timersInsLanded(ins, timerInsFrom(cfg));
    },
    onPoll: (s) => _log('    …restoring, controller recovering (${s}s)'),
  );
  _record(CheckResult(label, v.confirmed, 'post=$ok, verified=${v.confirmed} (${v.stallSeconds}s)'));
}

Future<void> cmdCfgTruth() async {
  _log('▶ cfg-truth (en int/bool polarity — permanent regression guard)');
  final captured = await _captureTimers();
  try {
    // Scratch timer occupies the LAST general slot (index 7); a real dow, a
    // benign macro. We write en as INT then as BOOL and read back the stored en.
    // Post a CLEAN single-scratch ins (NOT captured+scratch): the live readback
    // carries solar sentinels (hour:255) that, re-posted into general slots,
    // make WLED drop the scratch — the inaugural run's cfg-truth failure. A lone
    // scratch timer stores cleanly; captured is restored in the finally.
    Map<String, dynamic> scratch(Object en) =>
        {'en': en, 'hour': 3, 'min': 33, 'macro': 1, 'dow': 2};

    // Returns the stored `en` for the scratch, or null when the controller
    // dropped it from the readback (WLED compacts DISABLED timers out — the
    // expected outcome when a bool `en:true` is stored as disabled/0).
    Future<Object?> writeAndReadEn(Object en) async {
      // Reset to a known-DISABLED baseline first so each polarity test is
      // isolated — otherwise a bool write following an int:1 write reads the
      // stale en:1 (WLED keeps the prior value when it can't apply the bool).
      await client.postCfg({
        'timers': {
          'ins': [
            {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0}
          ]
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await client.postCfg({'timers': {'ins': [scratch(en)]}});
      Object? stored;
      // Short settle-poll (0.15.1 commits fast; no minutes-long stall). The int
      // scratch should appear; a dropped (disabled) scratch stays absent → null.
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final cfg = await client.getCfg();
        if (cfg == null) continue; // mid-commit empty body — keep polling
        final match = timerInsFrom(cfg).where((t) =>
            (t['hour'] as num?)?.toInt() == 3 &&
            (t['min'] as num?)?.toInt() == 33 &&
            (t['macro'] as num?)?.toInt() == 1);
        if (match.isNotEmpty) {
          stored = match.first['en'];
          break;
        }
        // Responsive controller + scratch absent ⇒ stored disabled/compacted.
        if (i >= 2) break;
      }
      return stored;
    }

    final storedInt = await writeAndReadEn(1); // int
    final storedBool = await writeAndReadEn(true); // bool
    // AUDIT FIX: `intWriteLanded` is now a required precondition. Previously a
    // null (never-landed) BOOL readback normalized to 0 and PASSED the bool
    // half — so a dead controller, a dropped POST or a network error all
    // reported "correctly disabled". The int write is the control that proves
    // the write path works at all; without it the result is inconclusive.
    _record(checkEnTruthTable(
      intWriteLanded: storedInt != null,
      storedForIntWrite: storedInt,
      storedForBoolWrite: storedBool,
    ));
  } finally {
    await _restoreTimers(captured, label: 'cfg-truth restore');
  }
}

Future<void> cmdSyncSim() async {
  _log('▶ sync-sim (REAL buildCfgPayload → post → patient verify → timersInsLanded)');
  final captured = await _captureTimers();
  var postCount = 0;
  try {
    // Fixture schedule: ON 3:15am / OFF 4:20am, Mon+Fri. Uses the app's REAL
    // builder — this is the whole point (drift catches a builder change).
    final fixture = [
      ScheduleItem(
        id: 'bench-sim',
        actionLabel: 'Turn On',
        timeLabel: '3:15 AM',
        offTimeLabel: '4:20 AM',
        repeatDays: const ['Mon', 'Fri'],
        enabled: true,
      ),
    ];
    final payload = cfg.buildCfgPayload(fixture);
    final sentIns = timerInsFrom(payload);
    _log('  built ${sentIns.length} real timers via buildCfgPayload: '
        '${sentIns.map((t) => '${t['hour']}:${t['min']}/m${t['macro']}/d${t['dow']}').join(', ')}');

    final ok = await client.postCfg(payload);
    postCount++;
    final v = await client.patientVerify(
      confirm: () async {
        final cfgBack = await client.getCfg();
        return cfgBack != null && timersInsLanded(sentIns, timerInsFrom(cfgBack));
      },
      onPoll: (s) => _log('    …verifying through stall (${s}s)'),
    );
    _record(CheckResult('sync-sim landed (timersInsLanded)', v.confirmed,
        'post2xx=$ok, landed=${v.confirmed}, stall=${v.stallSeconds}s, posts=$postCount'));
  } finally {
    await _restoreTimers(captured, label: 'sync-sim restore');
  }
}

Future<void> cmdPresetVerify({bool functional = true}) async {
  _log('▶ preset-verify (on-device invariants)');
  final body = await client.getPresets();
  if (body == null) {
    _record(const CheckResult('presets readable', false, '/presets.json unreadable'));
    return;
  }
  final presets = parsePresets(body);
  for (final r in checkPresetInvariants(presets)) {
    _record(r);
  }
  // AUDIT FIX: was a HARDCODED `true` — a check that could never fail. Now
  // compares lease slots against a re-read after the static checks, so any
  // mutation during this run is caught. (The harness never writes them; this
  // asserts that rather than asserting it in a comment.)
  final after = parsePresets(await client.getPresets() ?? const {});
  _record(checkLeaseSlotsIntact(before: presets, after: after));

  final scheduleSlots = presets.keys
      .where((id) => id >= kSchedulePresetMin && id <= kSchedulePresetMax)
      .toList()
    ..sort();
  _log('  app-managed schedule slots present (10-25): $scheduleSlots');

  if (functional) await _functionalPresetGuard(presets);
}

/// FUNCTIONAL master-power guard (VERIFICATION_REPORT.md §5 Guard 2).
///
/// Static key inspection still encodes an assumption about what WLED does with
/// `ib`. This asserts the only property that actually matters, end to end:
///
///     master OFF → load preset N → state.on MUST be true
///
/// It cannot be faked by a firmware change in mechanism, and it is the exact
/// manual test that exposed the defect the static check had been passing on.
/// MUTATING: toggles master power, so it captures and restores.
Future<void> _functionalPresetGuard(Map<int, Map<String, dynamic>> presets) async {
  final onPresets = [1, 3, 4, 5].where(presets.containsKey).toList();
  if (onPresets.isEmpty) {
    _record(const CheckResult('functional preset guard', true,
        'no ON presets on device — nothing to exercise'));
    return;
  }
  _log('  functional guard: master-off → load preset → assert lights on');
  final pre = await client.getState();
  final preOn = pre?['on'] == true;
  final prePs = pre?['ps'];
  try {
    for (final id in onPresets) {
      await client.postState({'on': false});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final dark = await client.getState();
      if (dark?['on'] == true) {
        _record(CheckResult('functional: preset $id lights a dark strip', false,
            'precondition failed — could not force master off'));
        continue;
      }
      await client.postState({'ps': id});
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final after = await client.getState();
      final poweredOn = after?['on'] == true;
      _record(CheckResult(
        'functional: preset $id lights a dark strip',
        poweredOn,
        'master off → ps:$id → state.on=${after?['on']} ps=${after?['ps']} '
            '(want on=true)'
            '${poweredOn ? '' : ' — preset $id does NOT assert master power; a '
                'timer firing macro:$id fires DARK'}',
      ));
    }
  } finally {
    await client.postState({'on': preOn});
    if (prePs is num && prePs.toInt() > 0) {
      await client.postState({'ps': prePs.toInt()});
    }
    _log('  functional guard restored master on=$preOn ps=$prePs');
  }
}

Future<void> cmdFireTest() async {
  _log('▶ fire-test (scratch timer ~2 min ahead, master off, await power-on)');
  final captured = await _captureTimers();
  try {
    // Compute "today" dow per the CONTROLLER clock where possible; WLED 0.15.1
    // does not expose wall time over JSON, so we use local time and the app's
    // Mon=bit0 convention. Target 2 minutes ahead (rounded to the minute).
    // AUDIT FIX: the old code used the HOST clock with a comment claiming
    // "WLED 0.15.1 does not expose wall time over JSON". It DOES — /json →
    // info.time. Host/controller clock or timezone skew silently armed the
    // timer for the wrong minute, failing the test for a reason unrelated to
    // the app. Prefer controller time; fall back to host with a loud warning.
    final info = await client.getInfo();
    final ctrlNow = parseControllerTime(info?['time']);
    final hostNow = DateTime.now();
    if (ctrlNow == null) {
      _log('    ⚠ controller time unavailable (info.time=${info?['time']}) — '
          'falling back to HOST clock; a clock skew will flake this test');
    } else {
      final skew = ctrlNow.difference(hostNow).inSeconds.abs();
      _log('    controller time=$ctrlNow host=$hostNow skew=${skew}s');
      if (skew > 60) {
        _record(CheckResult('fire-test precondition: clock skew < 60s', false,
            'controller/host skew ${skew}s — arming would target the wrong '
            'minute. Fix NTP before trusting a fire result.'));
      }
    }
    final now = ctrlNow ?? hostNow;
    // 3-min lead (not 2): the arm+verify eats into the margin; a short lead
    // flakes if the target minute passes during arming.
    final target = now.add(const Duration(minutes: 3));
    final dowBit = dowBitForMondayZeroIndex(now.weekday - 1); // Mon=1→bit0
    // CLEAN single-scratch array (NOT captured+scratch): re-posting the live
    // solar sentinels (hour:255) into general slots makes WLED drop the scratch,
    // so it never fires. macro:1 = system ON preset (no scratch preset written).
    final scratch = {
      'en': 1,
      'hour': target.hour,
      'min': target.minute,
      'macro': 1,
      'dow': dowBit
    };

    await client.postState({'on': false}); // start dark
    await client.postCfg({'timers': {'ins': [scratch]}});
    final armed = await client.patientVerify(confirm: () async {
      final cfgBack = await client.getCfg();
      return cfgBack != null && timersInsLanded([scratch], timerInsFrom(cfgBack));
    }, onPoll: (s) => _log('    …arming scratch timer (${s}s)'));
    _record(CheckResult('fire-test: scratch timer armed', armed.confirmed,
        armed.confirmed
            ? 'scratch landed on /json/cfg readback (${armed.stallSeconds}s)'
            : 'scratch did not land on /json/cfg readback'));
    if (!armed.confirmed) {
      // AUDIT FIX: the old code recorded the failure and then CONTINUED —
      // waiting 90s to emit a "strip powered on" check that was meaningless
      // because nothing was ever armed. Bail instead of manufacturing a
      // second, uninterpretable failure.
      _log('  arming failed — skipping the fire window (nothing to wait for)');
      return;
    }
    // Park `ps` on a DIFFERENT preset before arming so the discriminator is
    // non-degenerate. Bench-observed on this firmware: a plain /json/state
    // write does NOT clear `ps`, so without this the value left behind by the
    // functional preset guard (ps=1) collides with the scratch macro (also 1)
    // and "ps changed to 1" cannot distinguish a fire from a leftover.
    // Preset 2 is the OFF preset, so loading it also enforces the required
    // start-dark precondition.
    final parked = await client.postState({'ps': kNglOffPresetIdForBench});
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Capture ps BEFORE the fire window: it is the discriminator between
    // "never fired" and "fired but dark" (VERIFICATION_REPORT.md §6).
    // NOTE: nothing may write /json/state during the window — see above.
    final psBefore = (await client.getState())?['ps'];
    if (!parked || psBefore == 1) {
      _log('    ⚠ could not park ps away from the scratch macro '
          '(ps=$psBefore) — fire-test A will report INCONCLUSIVE');
    }
    _log('  scratch timer armed for ${target.hour}:${target.minute.toString().padLeft(2, '0')} '
        '(dow bit $dowBit); master off; ps=$psBefore; waiting for fire…');

    // Wait until ~65s past the target minute.
    final fireDeadline = DateTime(target.year, target.month, target.day, target.hour, target.minute)
        .add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(fireDeadline)) {
      await Future<void>.delayed(const Duration(seconds: 10));
      _log('    …waiting (${DateTime.now().difference(now).inSeconds}s elapsed)');
    }
    // AUDIT FIX — the single conflated assertion is split in two. The old check
    // (`state.on == true`) failed IDENTICALLY when the timer never fired
    // (firmware) and when it fired into a preset that does not assert master
    // power (app). Both were true on the bench rig at once, which is why the
    // failure stayed ambiguous for weeks.
    final state = await client.getState();
    for (final r in checkFireTestSplit(
      expectedMacro: 1,
      psBefore: psBefore,
      psAfter: state?['ps'],
      onAfter: state?['on'],
    )) {
      _record(r);
    }
  } finally {
    await client.postState({'on': false});
    await _restoreTimers(captured, label: 'fire-test restore');
  }
}

Future<void> cmdChannelPower() async {
  _log('▶ channel-power (P1-43 four shapes via buildChannelPowerPayload)');
  final cfgBody = await client.getCfg();
  if (cfgBody == null) {
    _record(const CheckResult('channel-power precondition', false, 'cfg unreadable'));
    return;
  }
  final channels = deviceChannelsFromConfig(parseHwLedFromCfg(cfgBody));
  if (channels.length < 2) {
    _record(CheckResult('channel-power needs ≥2 channels', false,
        'only ${channels.length} channel(s) on device'));
    return;
  }
  final a = channels[0].id, b = channels[1].id;

  // Capture live master + seg on-states for restore.
  final pre = await client.getState();
  final preOn = pre?['on'] == true;

  Set<int> litFromState(Map<String, dynamic>? s) {
    final out = <int>{};
    final seg = s?['seg'];
    if (seg is List) {
      for (final e in seg) {
        if (e is Map && e['on'] == true && e['id'] is int) out.add(e['id'] as int);
      }
    }
    return out;
  }

  Future<Map<String, dynamic>?> applyAndRead(Map<String, dynamic> payload) async {
    await client.postState(payload);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return client.getState();
  }

  try {
    // CASE 3 (critical): from master-off, channel A on → ONE post, master on +
    // A on / B off. Assert emitted shape AND resulting state.
    await client.postState({'on': false});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final p3 = buildChannelPowerPayload(
        channelId: a, on: true, masterOn: false, litChannelIds: {}, channels: channels);
    final emitted3ok = p3['on'] == true &&
        (p3['seg'] as List).length == channels.length &&
        (p3['seg'] as List).any((s) => s['id'] == a && s['on'] == true) &&
        (p3['seg'] as List).any((s) => s['id'] == b && s['on'] == false);
    final s3 = await applyAndRead(p3);
    final lit3 = litFromState(s3);
    _record(CheckResult('P1-43 case 3: master-off → chan $a on = ONE post, only $a lit',
        emitted3ok && s3?['on'] == true && lit3.contains(a) && !lit3.contains(b),
        'emitted={on:${p3['on']},segs:${(p3['seg'] as List).length}}; state on=${s3?['on']} lit=$lit3'));

    // CASE 4: channel B on while master already on → seg-only (no top-level on).
    final p4 = buildChannelPowerPayload(
        channelId: b, on: true, masterOn: true, litChannelIds: {a}, channels: channels);
    final emitted4ok = !p4.containsKey('on') &&
        (p4['seg'] as List).single['id'] == b &&
        (p4['seg'] as List).single['on'] == true;
    final s4 = await applyAndRead(p4);
    final lit4 = litFromState(s4);
    // AUDIT FIX: `lit` means "segment flagged on", NOT "physically lit". Without
    // asserting master power too, this passed when the master was off and both
    // segments merely carried on:true — i.e. a dark strip reported as correct.
    _record(CheckResult('P1-43 case 4: chan $b on while master on = seg-only, $a undisturbed',
        emitted4ok && s4?['on'] == true && lit4.contains(a) && lit4.contains(b),
        'emitted noMasterKey=${!p4.containsKey('on')}; master on=${s4?['on']} (want true); state lit=$lit4'));

    // CASE 1: channel A off while B still lit → seg off, NO master key.
    final p1 = buildChannelPowerPayload(
        channelId: a, on: false, masterOn: true, litChannelIds: {a, b}, channels: channels);
    final emitted1ok = !p1.containsKey('on') &&
        (p1['seg'] as List).single['id'] == a &&
        (p1['seg'] as List).single['on'] == false;
    final s1 = await applyAndRead(p1);
    final lit1 = litFromState(s1);
    // Same audit fix as case 4 — master must remain ON for "only $a dies" to
    // mean anything physically.
    _record(CheckResult('P1-43 case 1: chan $a off (others lit) = seg-off no master, only $a dies',
        emitted1ok && s1?['on'] == true && !lit1.contains(a) && lit1.contains(b),
        'emitted noMasterKey=${!p1.containsKey('on')}; master on=${s1?['on']} (want true); state lit=$lit1'));

    // CASE 2: channel B off (last lit) → master follows off.
    final p2 = buildChannelPowerPayload(
        channelId: b, on: false, masterOn: true, litChannelIds: {b}, channels: channels);
    final emitted2ok = p2['on'] == false && !p2.containsKey('seg');
    final s2 = await applyAndRead(p2);
    _record(CheckResult('P1-43 case 2: chan $b off (last lit) = master off',
        emitted2ok && s2?['on'] == false,
        'emitted={on:${p2['on']}}; state on=${s2?['on']} (want false)'));
  } finally {
    // Restore master to its pre-test power.
    await client.postState({'on': preOn});
    _log('  restored master on=$preOn');
  }
}

Future<void> cmdRestore() async {
  _log('▶ restore (re-assert from newest snapshot)');
  final dir = Directory('$_benchDir/snapshots');
  if (!dir.existsSync()) {
    _record(const CheckResult('restore', false, 'no snapshots/ dir'));
    return;
  }
  final snaps = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (snaps.isEmpty) {
    _record(const CheckResult('restore', false, 'no snapshot files'));
    return;
  }
  final snap = jsonDecode(snaps.last.readAsStringSync()) as Map<String, dynamic>;
  final ins = (snap['timers'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
  await _restoreTimers(ins, label: 'restore timers from ${snaps.last.path.split('/').last}');
  final state = snap['state'];
  if (state is Map && state['on'] is bool) {
    // AUDIT FIX: was a HARDCODED `true` — it posted and asserted nothing, so a
    // failed restore reported green. Now reads back and compares.
    final want = state['on'] as bool;
    await client.postState({'on': want});
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final got = (await client.getState())?['on'];
    _record(CheckResult('restore master power', got == want,
        'wanted on=$want, readback on=$got'));
  }
}

Future<void> cmdAll() async {
  _log('══ bench all — inaugural run ${DateTime.now().toIso8601String()} ══');
  await cmdProbe();
  await cmdSnapshot();
  await cmdCfgTruth();
  await cmdPresetVerify();
  await cmdSyncSim();
  await cmdFireTest();
  await cmdChannelPower();
  await cmdRestore();
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run bench/bin/bench.dart <command> [--ip IP]');
    stderr.writeln('  probe|snapshot|cfg-truth|sync-sim|preset-verify|'
        'fire-test|channel-power|restore|all');
    exit(2);
  }
  final ip = _resolveIp(args);
  client = WledClient('http://$ip');
  _log('bench → $ip');

  final cmd = args.first;
  try {
    switch (cmd) {
      case 'probe':
        await cmdProbe(update: args.contains('--update'));
        break;
      case 'snapshot':
        await cmdSnapshot();
        break;
      case 'cfg-truth':
        await cmdCfgTruth();
        break;
      case 'sync-sim':
        await cmdSyncSim();
        break;
      case 'preset-verify':
        await cmdPresetVerify();
        break;
      case 'fire-test':
        await cmdFireTest();
        break;
      case 'channel-power':
        await cmdChannelPower();
        break;
      case 'restore':
        await cmdRestore();
        break;
      case 'fanout-verify':
        await cmdFanoutVerify(args);
        break;
      case 'all':
        await cmdAll();
        break;
      default:
        stderr.writeln('unknown command: $cmd');
        client.close();
        exit(2);
    }
  } finally {
    client.close();
  }

  final failed = _results.where((r) => !r.pass).toList();
  _log('');
  _log('══ ${_results.length - failed.length}/${_results.length} checks passed ══');
  if (failed.isNotEmpty) {
    _log('FAILURES:');
    for (final f in failed) {
      _log('  ✗ ${f.name}: ${f.evidence}');
    }
  }
  exit(failed.isEmpty ? 0 : 1);
}

// ───────────────────────────────────────────────────────────────────────────
// fanout-verify — two-node crew fanout (runbook step 4)
// ───────────────────────────────────────────────────────────────────────────
//
// Proves a sync initiated by A lands on B's controller while B never runs the
// app. Node A is this bench controller; Node B is a stub WLED endpoint served
// in-process, fed by a bridge simulator that drains B's Firestore command queue
// exactly as the ESP32 does. No second house, no second phone.
//
// NOT RUNNABLE YET: needs the F-3 rules deploy AND config/sync_fanout enabled
// for the test context. Both are Tyler's gates; this exits 2 naming what is
// missing rather than producing a meaningless result.
//
//   dart run bench/bin/bench.dart fanout-verify \
//     --group <groupId> --a-token <A idToken> \
//     --b-uid <B uid> --b-token <B idToken> [--b-port 8099]
//
// TWO tokens, deliberately: A initiates (its token authorizes applySyncPattern)
// and B's own token is what the bridge-sim drains B's queue with. A cannot read
// B's commands — that separation is what makes a pass mean "fanout", rather
// than "A wrote to itself".

const String _fnBase =
    'https://us-central1-icrt6menwsv2d8all8oijs021b06s5.cloudfunctions.net';
const String _fsBase = 'https://firestore.googleapis.com/v1/projects/'
    'icrt6menwsv2d8all8oijs021b06s5/databases/(default)/documents';

String? _flag(List<String> args, String name) {
  final i = args.indexOf('--$name');
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

/// Decodes a Firestore REST typed value into plain Dart.
Object? _fsValue(Map<String, dynamic> v) {
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('integerValue')) return int.tryParse('${v['integerValue']}');
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('arrayValue')) {
    final vals = (v['arrayValue']['values'] as List?) ?? const [];
    return vals.map((e) => _fsValue(Map<String, dynamic>.from(e))).toList();
  }
  if (v.containsKey('mapValue')) {
    final f = (v['mapValue']['fields'] as Map?) ?? const {};
    return f.map((k, e) =>
        MapEntry(k as String, _fsValue(Map<String, dynamic>.from(e))));
  }
  return null;
}

/// [CommandQueue] over the Firestore REST API using B's OWN id token — the
/// same authority the real bridge has, so rules apply exactly as in production.
class _RestCommandQueue implements CommandQueue {
  _RestCommandQueue(this.idToken);
  final String idToken;
  final HttpClient _http = HttpClient();

  @override
  Future<List<QueuedCommand>> pending(String uid) async {
    final req = await _http.getUrl(Uri.parse('$_fsBase/users/$uid/commands'));
    req.headers.set('Authorization', 'Bearer $idToken');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      _log('  queue read failed ${res.statusCode}: $body');
      return const [];
    }
    final docs = (jsonDecode(body)['documents'] as List?) ?? const [];
    final out = <QueuedCommand>[];
    for (final d in docs) {
      final m = Map<String, dynamic>.from(d);
      final fields = Map<String, dynamic>.from(m['fields'] ?? {});
      final decoded = fields
          .map((k, v) => MapEntry(k, _fsValue(Map<String, dynamic>.from(v))));
      final name = (m['name'] as String? ?? '').split('/').last;
      // fanoutToCrew writes the WLED body as a JSON STRING; decode it back.
      Map<String, dynamic> payload = {};
      final raw = decoded['payload'];
      if (raw is String && raw.isNotEmpty) {
        try {
          payload = Map<String, dynamic>.from(jsonDecode(raw));
        } catch (_) {}
      } else if (raw is Map) {
        payload = Map<String, dynamic>.from(raw);
      }
      out.add(QueuedCommand(
        id: name,
        type: decoded['type'] as String? ?? 'applyJson',
        status: decoded['status'] as String? ?? 'pending',
        payload: payload,
      ));
    }
    return out;
  }

  @override
  Future<void> markComplete(String uid, String commandId) async {
    final uri = Uri.parse(
        '$_fsBase/users/$uid/commands/$commandId?updateMask.fieldPaths=status');
    final req = await _http.patchUrl(uri);
    req.headers.set('Authorization', 'Bearer $idToken');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'fields': {
        'status': {'stringValue': 'completed'}
      }
    }));
    await (await req.close()).drain<void>();
  }

  void close() => _http.close(force: true);
}

/// Node B: a stub WLED endpoint. GET /json/state reports, POST applies.
class _StubController {
  ControllerSnapshot state = const ControllerSnapshot(
    on: true,
    effectId: 0,
    paletteId: 0,
    colors: [
      [0, 0, 0]
    ],
  );
  HttpServer? _server;

  Future<int> start(int port) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((req) async {
      if (req.method == 'POST') {
        // HttpRequest is Stream<Uint8List>, so bind the decoder rather than
        // transform() (which wants a StreamTransformer<Uint8List, _>).
        final body = await utf8.decoder.bind(req).join();
        try {
          state =
              applyPayload(state, Map<String, dynamic>.from(jsonDecode(body)));
        } catch (_) {}
        req.response.statusCode = 200;
        await req.response.close();
        return;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'on': state.on,
        'seg': [
          {'fx': state.effectId, 'pal': state.paletteId, 'col': state.colors}
        ],
      }));
      await req.response.close();
    });
    return _server!.port;
  }

  Future<void> stop() async => _server?.close(force: true);
}

Future<FanoutResponse> _postFanout(
  String token,
  String groupId,
  Map<String, dynamic> payload,
) async {
  final http = HttpClient();
  try {
    final req = await http.postUrl(Uri.parse('$_fnBase/applySyncPattern'));
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'data': {
        'groupId': groupId,
        'sessionId': '',
        'payload': payload,
        'fanout': true,
        'source': 'bench_fanout_verify',
      }
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    Map<String, dynamic> parsed = {};
    try {
      parsed = Map<String, dynamic>.from(jsonDecode(body));
    } catch (_) {}
    return FanoutResponse.fromBody(res.statusCode, parsed);
  } finally {
    http.close(force: true);
  }
}

Future<void> cmdFanoutVerify(List<String> args) async {
  _log('> fanout-verify (A=bench controller, B=stub + bridge-sim)');

  final group = _flag(args, 'group');
  final aToken = _flag(args, 'a-token');
  final bUid = _flag(args, 'b-uid');
  final bToken = _flag(args, 'b-token');
  final bPort = int.tryParse(_flag(args, 'b-port') ?? '') ?? 8099;

  final missing = <String>[
    if (group == null) '--group',
    if (aToken == null) '--a-token',
    if (bUid == null) '--b-uid',
    if (bToken == null) '--b-token',
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('fanout-verify needs: ${missing.join(", ")}');
    stderr.writeln('Prerequisites (both gated by Tyler):');
    stderr.writeln('  1. F-3 rules deployed');
    stderr.writeln('  2. config/sync_fanout.enabled = true for the test context');
    client.close();
    exit(2);
  }

  // Fireworks in two contrasting colors: visually obvious and far from any
  // resting state, so "converged" cannot be a coincidence.
  const pattern = PatternSpec(
    effectId: 88,
    paletteId: 5,
    colors: [
      [255, 0, 0],
      [0, 0, 255]
    ],
  );

  final stub = _StubController();
  final queue = _RestCommandQueue(bToken!);
  try {
    final port = await stub.start(bPort);
    _log('  Node B stub on 127.0.0.1:$port');

    final first = await _postFanout(aToken!, group!, pattern.toSegPayload());
    _log('  fanout#1 -> status=${first.statusCode} ok=${first.ok} '
        'reason=${first.reason}');

    // Bridge-sim: poll, because the CF write and the queue read are not
    // synchronous — and the real bridge polls too.
    var drained = <QueuedCommand>[];
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      drained = executableCommands(await queue.pending(bUid!));
      if (drained.isNotEmpty) break;
    }
    for (final c in drained) {
      stub.state = applyPayload(stub.state, c.payload);
      await queue.markComplete(bUid!, c.id);
    }
    _log('  bridge-sim drained ${drained.length} command(s)');

    // Second fanout INSIDE the 18s cooldown — must be refused.
    final second = await _postFanout(aToken, group, pattern.toSegPayload());
    _log('  fanout#2 -> status=${second.statusCode} ok=${second.ok} '
        'reason=${second.reason}');

    final aState = await client.getState();
    final aSnap = aState == null
        ? const ControllerSnapshot(on: false)
        : ControllerSnapshot.fromState(aState);

    final checks = evaluateFanoutRun(FanoutRunObservation(
      bQueueAfterFanout: drained,
      initiatorUid: 'A',
      nodeBUid: bUid!,
      nodeAAfter: aSnap,
      nodeBAfter: stub.state,
      broadcast: pattern,
      secondFanout: second,
    ));
    for (final c in checks) {
      _record(CheckResult(c.name, c.pass, c.evidence));
    }
  } finally {
    queue.close();
    await stub.stop();
  }
}

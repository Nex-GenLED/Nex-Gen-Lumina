// evidence/gameday-team-priority-2026-09-22/gd_priority_bench_test.dart
//
// HARDWARE bench for the Game Day team-priority hierarchy.
//
// Lives under evidence/, NOT test/, deliberately: it writes to the real bench
// controller, and the repo's suite-count invariant (3357/34/0) must stay
// comparable run to run. Prior Game Day bench probes used the same location.
//
// Run explicitly, from the worktree root:
//   flutter test evidence/gameday-team-priority-2026-09-22/gd_priority_bench_test.dart
//
// ⚠️ WRITES TO REAL HARDWARE at 192.168.1.150. It applies Game Day designs and
// restores the captured state at the end. It performs NO psave, NO pdel and NO
// /json/cfg POST — the bench controller's presets.json carries known flash
// corruption and a cfg POST omitting `light.gc` wipes gamma, so both are
// avoided entirely and verified unchanged by hash at the end.
//
// WHAT IS REAL AND WHAT IS SIMULATED
//   REAL: GameDayAutopilotService (the shipping class, unmodified for this
//         run), its arbitration, its design selection, its payload builder,
//         and the HTTP write + readback against the controller.
//   SIMULATED: the two ESPN readers. A real Royals-and-Chiefs overlap cannot
//         be waited for, so game times and final-whistles are injected. The
//         30-minute post-game countdown is fast-forwarded through the
//         service's own test seam.

// This IS a test — it just lives outside test/ so the suite-count invariant
// stays comparable (see the header). The analyzer scopes @visibleForTesting to
// test/, so using the service's countdown seam from here needs the exemption.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/game_state.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/foreground_celebration_providers.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';

const kIp = '192.168.1.150';
const kBase = 'http://$kIp';

// ── Fakes: ONLY the two ESPN readers ──────────────────────────────────────

class _FakeSchedule extends GameScheduleService {
  final Map<String, DateTime> nextGame = {};
  final Set<String> soon = {};

  @override
  Future<DateTime?> fetchNextGameDate(String id, SportType s) async =>
      nextGame[id];

  @override
  Future<bool> hasGameSoon(String id, SportType s, {int minutes = 30}) async =>
      soon.contains(id);
}

class _FakeEspn extends EspnApiService {
  final Map<String, GameState> games = {};

  @override
  Future<GameState?> fetchTeamGame(SportType s, String id) async => games[id];
}

GameState _g(String gid, String teamId, GameStatus st) => GameState(
      gameId: gid,
      homeTeam: 'Home',
      awayTeam: 'Away',
      homeTeamId: teamId,
      awayTeamId: 'opp',
      status: st,
      lastUpdated: DateTime.now(),
    );

GameDayAutopilotConfig _cfg(String slug) {
  final t = kTeamColors[slug]!;
  return GameDayAutopilotConfig(
    teamSlug: slug,
    teamName: t.teamName,
    espnTeamId: t.espnTeamId,
    sport: t.sport,
    primaryColorValue: t.primary.toARGB32(),
    secondaryColorValue: t.secondary.toARGB32(),
    enabled: true,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );
}

List<int> _rgbOf(String slug) {
  final c = kTeamColors[slug]!.primary;
  return [
    (c.r * 255).round(),
    (c.g * 255).round(),
    (c.b * 255).round(),
  ];
}

// ── Controller I/O ────────────────────────────────────────────────────────

final _client = http.Client();

Future<Map<String, dynamic>> _getJson(String path) async {
  final r = await _client
      .get(Uri.parse('$kBase$path'))
      .timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) {
    throw StateError('GET $path → HTTP ${r.statusCode}');
  }
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<String> _sha(String path) async {
  final r = await _client
      .get(Uri.parse('$kBase$path'))
      .timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw StateError('GET $path → ${r.statusCode}');
  return sha256.convert(r.bodyBytes).toString();
}

Future<bool> _post(Map<String, dynamic> payload) async {
  final r = await _client
      .post(Uri.parse('$kBase/json/state'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload))
      .timeout(const Duration(seconds: 15));
  return r.statusCode == 200;
}

/// seg 0's primary colour as [r,g,b], from a live state read.
Future<List<int>> _wireColor() async {
  final st = await _getJson('/json/state');
  final segs = (st['seg'] as List).cast<Map<String, dynamic>>();
  final col = (segs.first['col'] as List).first as List;
  return [
    (col[0] as num).toInt(),
    (col[1] as num).toInt(),
    (col[2] as num).toInt(),
  ];
}

Future<bool> _isOn() async => (await _getJson('/json/state'))['on'] == true;

void _log(String s) => stdout.writeln('  [bench] $s');

// ── Harness ───────────────────────────────────────────────────────────────

class _Rig {
  late final _FakeSchedule sched;
  late final _FakeEspn espn;
  late final GameDayAutopilotService svc;
  int resumeCalls = 0;
  List<String> priority;

  _Rig(this.priority) {
    sched = _FakeSchedule();
    espn = _FakeEspn();
    svc = GameDayAutopilotService(espnApi: espn, scheduleService: sched);
    svc.onGetTeamPriority = () => priority;
    // The REAL write. No participation filter: this run is about which team's
    // design reaches the controller, and channel fan-out is untouched by this
    // change. Payload lands on seg 0, which is what _wireColor reads.
    svc.onApplyPayload = (payload) async {
      final ok = await _post(payload);
      if (!ok) throw StateError('controller rejected the apply');
    };
    svc.onResumeNormalSchedule = () {
      resumeCalls++;
      _log('!! onResumeNormalSchedule fired (would power the house off)');
    };
  }

  String? get owner => svc.activeSessions.values
      .where((s) => s.ownsLights)
      .map((s) => s.teamSlug)
      .firstOrNull;

  Set<String> get deferred => svc.activeSessions.values
      .where((s) => s.deferred)
      .map((s) => s.teamSlug)
      .toSet();

  /// Which teams would have score celebrations armed right now, through the
  /// REAL derivation the app uses.
  Set<String> celebratingTeams(List<GameDayAutopilotConfig> configs) =>
      computeLiveCelebrationTeams(
        sessions: svc.activeSessions,
        ephemeralSessions: const [],
        configs: configs,
      ).map((t) => t.teamSlug).toSet();
}

void main() {
  const chiefs = 'nfl_chiefs';
  const royals = 'mlb_royals';
  final chiefsCfg = _cfg(chiefs);
  final royalsCfg = _cfg(royals);
  final chiefsId = chiefsCfg.espnTeamId;
  final royalsId = royalsCfg.espnTeamId;
  // Firestore document-id order — mlb_royals sorts BEFORE nfl_chiefs. This is
  // the order that used to decide the winner, so every case feeds it.
  final docOrder = [royalsCfg, chiefsCfg];

  late Map<String, dynamic> snapshot;
  late String presetsSha;
  late String cfgSha;
  late int uptimeAtStart;

  setUpAll(() async {
    _log('=== T0 SNAPSHOT ===');
    final info = await _getJson('/json/info');
    uptimeAtStart = (info['uptime'] as num).toInt();
    snapshot = await _getJson('/json/state');
    presetsSha = await _sha('/presets.json');
    cfgSha = await _sha('/json/cfg');
    _log('ver=${info['ver']} uptime=${uptimeAtStart}s '
        'ws=${info['ws']} live=${info['live']}');
    _log('presets.json sha256=${presetsSha.substring(0, 16)}…');
    _log('cfg.json    sha256=${cfgSha.substring(0, 16)}…');
    _log('state.on=${snapshot['on']} bri=${snapshot['bri']}');
    expect(info['ws'], 0,
        reason: 'another client is connected — is a second bench session or '
            'the app driving this controller?');
  });

  tearDownAll(() async {
    _log('=== RESTORE ===');
    await _post(snapshot);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final after = await _getJson('/json/state');
    final diffs = <String>[];
    for (final k in ['on', 'bri', 'transition', 'ps', 'mainseg']) {
      if (jsonEncode(snapshot[k]) != jsonEncode(after[k])) {
        diffs.add('$k: ${snapshot[k]} → ${after[k]}');
      }
    }
    final segBefore = (snapshot['seg'] as List).cast<Map<String, dynamic>>();
    final segAfter = (after['seg'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < segBefore.length && i < segAfter.length; i++) {
      for (final k in ['fx', 'sx', 'ix', 'pal', 'col', 'on', 'bri', 'start', 'stop']) {
        if (jsonEncode(segBefore[i][k]) != jsonEncode(segAfter[i][k])) {
          diffs.add('seg$i.$k: ${jsonEncode(segBefore[i][k])} → '
              '${jsonEncode(segAfter[i][k])}');
        }
      }
    }

    final presetsAfter = await _sha('/presets.json');
    final cfgAfter = await _sha('/json/cfg');
    final info = await _getJson('/json/info');
    final uptimeEnd = (info['uptime'] as num).toInt();

    _log('state diffs: ${diffs.isEmpty ? "NONE" : diffs.join("; ")}');
    _log('presets.json unchanged: ${presetsAfter == presetsSha}');
    _log('cfg.json     unchanged: ${cfgAfter == cfgSha}');
    _log('uptime ${uptimeAtStart}s → ${uptimeEnd}s '
        '(no reboot: ${uptimeEnd > uptimeAtStart})');

    expect(diffs, isEmpty, reason: 'restore left the controller changed');
    expect(presetsAfter, presetsSha, reason: 'presets.json changed');
    expect(cfgAfter, cfgSha, reason: 'cfg.json changed');
    expect(uptimeEnd, greaterThan(uptimeAtStart), reason: 'controller rebooted');
    _client.close();
  });

  test('B1 — two teams overlapping: the #1 team is what reaches the wire, '
      'and it stays there', () async {
    _log('=== B1: priority [chiefs, royals], both windows open ===');
    final rig = _Rig([chiefs, royals]);
    rig.sched.soon.addAll([chiefsId, royalsId]);

    await rig.svc.evaluateConfigs(docOrder);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final wire = await _wireColor();
    _log('owner=${rig.owner} deferred=${rig.deferred} wire=$wire '
        'expected=${_rgbOf(chiefs)}');
    expect(rig.owner, chiefs);
    expect(rig.deferred, {royals});
    expect(wire, _rgbOf(chiefs),
        reason: 'the lower-priority team sorts FIRST by document id; before '
            'the hierarchy it was the one on the wire');
    expect(rig.celebratingTeams(docOrder), isEmpty,
        reason: 'pre-game, nobody is live yet');

    // Stays there across further ticks.
    await rig.svc.evaluateConfigs(docOrder);
    await rig.svc.evaluateConfigs(docOrder);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final wire2 = await _wireColor();
    _log('after 2 more ticks wire=$wire2');
    expect(wire2, _rgbOf(chiefs));
    expect(rig.resumeCalls, 0);
  });

  test('B2 — REVERSE the hierarchy, identical game times: the other team '
      'wins (priority is doing the work, not slug order)', () async {
    _log('=== B2: priority [royals, chiefs], same windows ===');
    final rig = _Rig([royals, chiefs]);
    rig.sched.soon.addAll([chiefsId, royalsId]);

    await rig.svc.evaluateConfigs(docOrder);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final wire = await _wireColor();
    _log('owner=${rig.owner} deferred=${rig.deferred} wire=$wire '
        'expected=${_rgbOf(royals)}');
    expect(rig.owner, royals);
    expect(rig.deferred, {chiefs});
    expect(wire, _rgbOf(royals));
  });

  test('B3 — the LOWER-priority game ends first: the house does NOT go dark '
      'and the winner keeps the wire', () async {
    _log('=== B3: chiefs #1, royals finishes first ===');
    final rig = _Rig([chiefs, royals]);
    rig.sched.soon.addAll([chiefsId, royalsId]);
    await rig.svc.evaluateConfigs(docOrder);
    expect(rig.owner, chiefs);

    // Both live.
    rig.espn.games[chiefsId] = _g('gc', chiefsId, GameStatus.inProgress);
    rig.espn.games[royalsId] = _g('gr', royalsId, GameStatus.inProgress);
    await rig.svc.evaluateConfigs(docOrder);
    _log('both live → celebrating=${rig.celebratingTeams(docOrder)}');
    expect(rig.celebratingTeams(docOrder), {chiefs},
        reason: 'ONLY the current team alerts; the deferred team is silent');

    // Royals final + countdown elapsed.
    rig.espn.games[royalsId] = _g('gr', royalsId, GameStatus.final_);
    await rig.svc.evaluateConfigs(docOrder);
    rig.svc.debugSetCountdownEnd(royals, DateTime(2020));
    await rig.svc.evaluateConfigs(docOrder);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final on = await _isOn();
    final wire = await _wireColor();
    _log('resumeCalls=${rig.resumeCalls} on=$on wire=$wire '
        'owner=${rig.owner}');
    expect(rig.resumeCalls, 0,
        reason: 'THE BUG: the first game to end used to power the house off');
    expect(on, isTrue, reason: 'house went dark mid-game');
    expect(wire, _rgbOf(chiefs));
    expect(rig.celebratingTeams(docOrder), {chiefs});
  });

  test('B4 — the WINNER ends while the other is still live: hand-off, the '
      "survivor's design is applied and its alerts start", () async {
    _log('=== B4: chiefs #1 finishes, royals still live ===');
    final rig = _Rig([chiefs, royals]);
    rig.sched.soon.addAll([chiefsId, royalsId]);
    await rig.svc.evaluateConfigs(docOrder);
    expect(rig.owner, chiefs);

    rig.espn.games[chiefsId] = _g('gc', chiefsId, GameStatus.inProgress);
    rig.espn.games[royalsId] = _g('gr', royalsId, GameStatus.inProgress);
    await rig.svc.evaluateConfigs(docOrder);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await _wireColor(), _rgbOf(chiefs));
    expect(rig.celebratingTeams(docOrder), {chiefs});

    // Chiefs final, countdown elapses. Royals still playing.
    rig.espn.games[chiefsId] = _g('gc', chiefsId, GameStatus.final_);
    await rig.svc.evaluateConfigs(docOrder);
    rig.svc.debugSetCountdownEnd(chiefs, DateTime(2020));
    await rig.svc.evaluateConfigs(docOrder);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final on = await _isOn();
    final wire = await _wireColor();
    final celebrating = rig.celebratingTeams(docOrder);
    _log('resumeCalls=${rig.resumeCalls} on=$on wire=$wire '
        'owner=${rig.owner} celebrating=$celebrating');
    expect(rig.resumeCalls, 0, reason: 'hand off, do not go dark');
    expect(on, isTrue);
    expect(rig.owner, royals);
    expect(wire, _rgbOf(royals),
        reason: "the survivor's design must reach the controller");
    expect(celebrating, {royals},
        reason: 'the team taking over becomes current and ITS alerts fire');
    expect(rig.deferred, isEmpty);
  });

  test('B5 — the last game ending DOES resume the normal schedule', () async {
    _log('=== B5: single team, game ends ===');
    final rig = _Rig([chiefs]);
    rig.sched.soon.add(chiefsId);
    await rig.svc.evaluateConfigs([chiefsCfg]);
    rig.espn.games[chiefsId] = _g('gc', chiefsId, GameStatus.inProgress);
    await rig.svc.evaluateConfigs([chiefsCfg]);
    rig.espn.games[chiefsId] = _g('gc', chiefsId, GameStatus.final_);
    await rig.svc.evaluateConfigs([chiefsCfg]);
    rig.svc.debugSetCountdownEnd(chiefs, DateTime(2020));
    await rig.svc.evaluateConfigs([chiefsCfg]);

    _log('resumeCalls=${rig.resumeCalls} (expected 1)');
    expect(rig.resumeCalls, 1,
        reason: 'with nothing left to hand off to, resuming is correct');
  });
}

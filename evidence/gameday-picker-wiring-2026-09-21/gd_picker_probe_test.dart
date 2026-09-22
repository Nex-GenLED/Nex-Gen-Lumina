// BENCH PROBE — NOT PART OF THE SUITE. Copied into test/ for one run, then
// deleted; preserved under evidence/ for the record.
//
// Drives the REAL foreground celebration path (coordinator → resolveCelebration
// → buildAnimationSteps) with a synthetic Chiefs touchdown for every entry in
// the celebration picker's list, plus "no pick", and writes the exact wire
// payloads to JSON for the bench script. Also prints the contrast-fallback
// matrix against Game Day's own base designs. No network, no device, no
// Firestore.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/team_design_catalog.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/foreground_celebration_coordinator.dart';
import 'package:nexgen_command/features/sports_alerts/services/score_monitor_service.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

class _Monitor implements ScoreMonitor {
  final _c = StreamController<ScoreAlertEvent>.broadcast();
  @override
  Stream<ScoreAlertEvent> get alertStream => _c.stream;
  @override
  Future<void> checkScores(List<ScoreAlertConfig> c) async {}
  @override
  void reset() {}
}

class _Recorder implements CelebrationDelivery {
  _Recorder(this.baseFx);
  final int baseFx;
  List<AlertAnimationStep> played = const [];
  @override
  Future<Map<String, dynamic>?> capture() async => {
        'on': true,
        'bri': 128,
        'seg': [
          {'id': 0, 'on': true, 'fx': baseFx, 'pal': 0},
        ],
      };
  @override
  Future<void> play(List<AlertAnimationStep> steps) async => played = steps;
  @override
  Future<void> revert(Map<String, dynamic> captured) async {}
}

// Bench .150 topology: two buses, 0-128 and 128-290.
const _bench = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];

Future<List<AlertAnimationStep>> _fire({required int? pick, required int baseFx}) async {
  final rec = _Recorder(baseFx);
  final coord = ForegroundCelebrationCoordinator(
    monitor: _Monitor(),
    delivery: rec,
    minGap: Duration.zero,
  );
  coord.syncLiveTeams([
    CelebrationTeam(
      teamSlug: 'nfl_chiefs',
      sport: SportType.nfl,
      celebrationEffectId: pick,
      // What a user who only taps an effect ends up saving: the picker seeds
      // speed from the effect's speed profile and intensity at 128
      // (colorway_effect_selector.dart, celebration mode).
      celebrationSpeed: pick == null ? 240 : getSpeedProfile(pick).rawDefault,
      celebrationIntensity: pick == null ? 240 : 128,
    ),
  ]);
  // ignore: invalid_use_of_visible_for_testing_member
  coord.handleAlert(ScoreAlertEvent(
    teamSlug: 'nfl_chiefs',
    sport: SportType.nfl,
    eventType: AlertEventType.touchdown,
    pointsScored: 7,
    gameId: 'synthetic-picker-verify',
    timestamp: DateTime.utc(2026, 9, 21),
  ));
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  coord.dispose();
  return rec.played;
}

void main() {
  test('PROBE: real coordinator, every picker entry, synthetic touchdown',
      () async {
    final out = <Map<String, dynamic>>[];

    for (final pick in <int?>[null, ...WledEffectsCatalog.celebrationPickIds]) {
      final steps = await _fire(pick: pick, baseFx: 0); // over Solid: no clash
      expect(steps.length, 3);
      final e = pick == null ? null : WledEffectsCatalog.getById(pick);
      for (var i = 0; i < steps.length; i++) {
        final wire = applyChannelFilter(steps[i].payload, const [0, 1], _bench);
        final seg = (wire['seg'] as List).first as Map;
        out.add({
          'pick': pick,
          'pickName': e?.name ?? '(no pick — legacy)',
          'colorBehavior': e?.colorBehavior.name,
          'stage': i + 1,
          'holdSeconds': steps[i].hold.inSeconds,
          'fx': seg['fx'],
          'fxName': WledEffectsCatalog.getById(seg['fx'] as int)?.name,
          'wire': wire,
        });
      }
      final s1 = (steps.first.payload['seg'] as List).first as Map;
      // ignore: avoid_print
      print('PROBE pick=${pick ?? '-'} (${e?.name ?? 'legacy'}, '
          '${e?.colorBehavior.name ?? '-'}): stage fx = '
          '${steps.map((s) => ((s.payload['seg'] as List).first as Map)['fx']).toList()} '
          'sx=${s1['sx']} ix=${s1['ix']} pal=${s1.containsKey('pal') ? s1['pal'] : '(absent)'}');
    }

    // Contrast matrix: which picks fall back to the white strobe over each of
    // Game Day's OWN base designs (the look most likely to be under a score).
    final chiefs = kTeamColors['nfl_chiefs']!;
    final baseFx = <int>{
      for (final d in TeamDesignCatalog.build(
        teamName: chiefs.teamName,
        primary: chiefs.primary,
        secondary: chiefs.secondary,
      ))
        d.effectId,
    }.toList()
      ..sort();
    final matrix = <Map<String, dynamic>>[];
    for (final pick in WledEffectsCatalog.celebrationPickIds) {
      final row = <String, dynamic>{
        'pick': pick,
        'name': WledEffectsCatalog.getById(pick)?.name,
      };
      for (final b in baseFx) {
        final steps = await _fire(pick: pick, baseFx: b);
        final fx = ((steps.first.payload['seg'] as List).first as Map)['fx'];
        row['base$b'] = fx == pick ? 'as-picked' : 'FALLBACK(fx $fx)';
      }
      matrix.add(row);
      // ignore: avoid_print
      print('MATRIX ${jsonEncode(row)}');
    }

    final path = Platform.environment['GD_PROBE_OUT']!;
    File(path).writeAsStringSync(const JsonEncoder.withIndent(' ')
        .convert({'payloads': out, 'baseFx': baseFx, 'matrix': matrix}));
  });
}

// BENCH PROBE — NOT PART OF THE SUITE. Deleted after the verification run.
//
// Drives the REAL foreground celebration path on the FIXED code with a
// synthetic Chiefs touchdown and writes the exact wire payloads to a JSON file
// for the bench script. No network, no device, no Firestore.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/foreground_celebration_coordinator.dart';
import 'package:nexgen_command/features/sports_alerts/services/score_monitor_service.dart';
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
  List<AlertAnimationStep> played = const [];
  @override
  Future<Map<String, dynamic>?> capture() async => {'on': false, 'seg': []};
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

Map<String, dynamic> _row(String label, AlertAnimationStep s) {
  final wire = applyChannelFilter(s.payload, const [0, 1], _bench);
  final fx = ((wire['seg'] as List).first as Map)['fx'] as int;
  return {
    'label': label,
    'fx': fx,
    'name': WledEffectsCatalog.getById(fx)?.name,
    'holdSeconds': s.hold.inSeconds,
    'wire': wire,
  };
}

void main() {
  test('PROBE: fixed code, real coordinator, synthetic scores', () async {
    final out = <Map<String, dynamic>>[];

    // 1. The LIVE path, end to end: coordinator -> builder, Chiefs touchdown.
    final rec = _Recorder();
    final coord = ForegroundCelebrationCoordinator(
      monitor: _Monitor(),
      delivery: rec,
      minGap: Duration.zero,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    coord.handleAlert(ScoreAlertEvent(
      teamSlug: 'nfl_chiefs',
      sport: SportType.nfl,
      eventType: AlertEventType.touchdown,
      pointsScored: 7,
      gameId: 'synthetic-fix-verify',
      timestamp: DateTime.utc(2026, 9, 21),
    ));
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(rec.played.length, 3);
    for (var i = 0; i < rec.played.length; i++) {
      out.add(_row('chiefs touchdown stage ${i + 1} [coordinator]', rec.played[i]));
    }
    coord.dispose();

    // 2. The other corrected stages, straight from the builder.
    final chiefs = kTeamColors['nfl_chiefs']!;
    final royals = kTeamColors['mlb_royals']!;
    final skc = kTeamColors['mls_sporting_kc']!;
    out.add(_row('royals run (was fx 5)',
        AlertTriggerService.buildAnimationSteps(AlertEventType.run, royals).single));
    out.add(_row('sporting kc soccerGoal stage 3 (was fx 63)',
        AlertTriggerService.buildAnimationSteps(AlertEventType.soccerGoal, skc)[2]));
    final win = AlertTriggerService.buildAnimationSteps(AlertEventType.win, chiefs);
    out.add(_row('chiefs win stage 2 (was fx 9)', win[1]));
    out.add(_row('chiefs win stage 3 (was fx 63)', win[2]));

    final path = Platform.environment['GD_PROBE_OUT']!;
    File(path).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    for (final r in out) {
      // ignore: avoid_print
      print('PROBE ${r['label']}: fx ${r['fx']} = ${r['name']} '
          '${jsonEncode(((r['wire'] as Map)['seg'] as List).first)}');
    }
  });
}

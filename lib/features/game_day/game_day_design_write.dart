// lib/features/game_day/game_day_design_write.dart
//
// The Game Day plan's design write, as a pure function of its inputs so it
// can be tested against a fake Firestore without the autopilot notifier
// (whose build() starts three timers). GameDayAutopilotNotifier.saveDesign
// delegates here.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/services/user_service.dart';

import '../autopilot/game_day_autopilot_config.dart';

/// The fields a design save updates on `users/{uid}/game_day_autopilot/{team}`.
///
/// [wledPayload] is the ONE representation: `effect_id` / `speed` /
/// `intensity` / `brightness` are read from its first segment (the optional
/// overrides only apply when the payload lacks the field), so the plan's
/// summary fields can never disagree with what it fires, and
/// [GameDayAutopilotConfig.designLabel] derives the card's text from it.
/// [designName] is the palette's name; the effect suffix is NOT stored.
Map<String, dynamic> gameDayDesignUpdate({
  required String designName,
  required Map<String, dynamic> wledPayload,
  int? effectId,
  int? speed,
  int? intensity,
  int? brightness,
  DateTime? now,
}) {
  final seg = wledPayload['seg'];
  final first = seg is List ? (seg.isEmpty ? null : seg.first) : seg;
  final segMap = first is Map ? first : const <String, dynamic>{};
  int fromSeg(String key, int? override, int fallback) =>
      (segMap[key] as num?)?.toInt() ?? override ?? fallback;
  return {
    'design_mode': AutopilotDesignMode.saved.name,
    'saved_design_name': designName,
    // JSON-STRING ENCODED: the payload carries seg[].col = [[r,g,b,w],…],
    // directly-nested arrays Firestore's native codecs reject (#84 class).
    'saved_design_payload': jsonEncode(wledPayload),
    'effect_id': fromSeg('fx', effectId, 0),
    'speed': fromSeg('sx', speed, 128),
    'intensity': fromSeg('ix', intensity, 128),
    'brightness': (wledPayload['bri'] as num?)?.toInt() ?? brightness ?? 200,
    'updated_at': Timestamp.fromDate(now ?? DateTime.now()),
  };
}

/// Persist a design for [teamSlug]. Throws when the plan document does not
/// exist, so a caller can report a save that did not happen.
Future<void> writeGameDayDesign(
  FirebaseFirestore db, {
  required String uid,
  required String teamSlug,
  required String designName,
  required Map<String, dynamic> wledPayload,
  int? effectId,
  int? speed,
  int? intensity,
  int? brightness,
}) {
  return db
      .collection('users')
      .doc(uid)
      .collection('game_day_autopilot')
      .doc(teamSlug)
      .update(UserService.sanitizeForFirestore(gameDayDesignUpdate(
        designName: designName,
        wledPayload: wledPayload,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
        brightness: brightness,
      )));
}

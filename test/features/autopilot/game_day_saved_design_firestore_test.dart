// BUG-GD-PICKER-1 — #84 sibling in the Game Day design picker.
//
// GameDayAutopilotNotifier.saveDesign persisted `saved_design_payload` as a
// RAW Map whose seg[].col is List<List<int>> (arrays-of-arrays). Firestore's
// native iOS codec aborts on directly-nested arrays (SIGABRT, #84); Android
// rejects them with a catchable error the picker's try/catch swallowed. Either
// way the write NEVER landed a doc, so saved Game Day designs were
// dead-on-arrival: the card kept showing "<Team> Running" and the apply path
// always fell back to the auto-built team-color payload.
//
// The fix mirrors favorites/scenes/schedules/remote_command: jsonEncode the
// payload to an opaque String on write (routed through
// UserService.sanitizeForFirestore as a guard), jsonDecode on read, tolerating
// any legacy raw-Map doc.
//
// These tests prove:
//   1. The saveDesign write map — with the payload jsonEncoded — passes
//      UserService.sanitizeForFirestore WITHOUT throwing (the exact guard that
//      made the raw write fail).
//   2. The RAW (unencoded) write map throws FirestoreSerializationError at the
//      col path — this is the clean exception the picker's catch now surfaces
//      as a SnackBar (item 4), and the reason the raw write was dead-on-arrival.
//   3. Round-trips through a real-backend-faithful FakeFirebaseFirestore:
//      write → read → GameDayAutopilotConfig.savedDesignPayload is byte-for-byte
//      the original, nested `col` included.
//   4. The RAW payload is rejected by the fake backend on write (proving the
//      pre-fix write could never persist).
//   5. Tolerant read: jsonEncoded String, legacy raw Map, null, and malformed
//      all decode sensibly.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/services/user_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A representative picker payload: multi-seg, each seg carrying a nested
  // `col` color matrix — the exact shape colorway_effect_selector builds and
  // hands to saveDesign (post applyChannelFilter).
  Map<String, dynamic> buildPickerPayload() => {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'fx': 17, // Twinkle
            'sx': 160,
            'ix': 128,
            'pal': 5,
            'grp': 1,
            'spc': 0,
            'col': [
              [0, 70, 173, 0], // Royals blue
              [255, 255, 255, 0],
            ],
          },
          {
            'id': 1,
            'fx': 17,
            'sx': 160,
            'ix': 128,
            'pal': 5,
            'col': [
              [193, 155, 91, 0], // Royals gold
            ],
          },
        ],
      };

  // Mirror EXACTLY what saveDesign writes: jsonEncode the payload, then route
  // the whole update map through the sanitize guard.
  Map<String, dynamic> buildSaveDesignWrite(Map<String, dynamic> payload) =>
      UserService.sanitizeForFirestore({
        'design_mode': AutopilotDesignMode.saved.name,
        'saved_design_name': 'Royals Twinkle - Twinkle',
        'saved_design_payload': jsonEncode(payload),
        'effect_id': 17,
        'speed': 160,
        'intensity': 128,
        'brightness': 255,
        'updated_at': Timestamp.fromDate(DateTime(2026, 7, 8)),
      });

  group('BUG-GD-PICKER-1 — sanitizer behavior at the write boundary', () {
    test('jsonEncoded saveDesign write passes sanitizeForFirestore', () {
      // The guard used to THROW on the raw nested col; the encoded form is an
      // opaque String, so it sanitizes cleanly.
      expect(() => buildSaveDesignWrite(buildPickerPayload()), returnsNormally);

      final write = buildSaveDesignWrite(buildPickerPayload());
      expect(write['saved_design_payload'], isA<String>());
      // The String decodes back to the original payload, nested col intact.
      expect(
        jsonDecode(write['saved_design_payload'] as String),
        equals(buildPickerPayload()),
      );
    });

    test(
        'RAW (unencoded) write throws FirestoreSerializationError at the col '
        'path — the clean exception the picker catch now surfaces', () {
      // This is what saveDesign did BEFORE the fix. On iOS the raw map crashed
      // natively; the sanitizer turns it into a catchable Dart error instead.
      expect(
        () => UserService.sanitizeForFirestore({
          'saved_design_name': 'Royals Twinkle - Twinkle',
          'saved_design_payload': buildPickerPayload(), // RAW map, nested col
        }),
        throwsA(isA<FirestoreSerializationError>().having(
          (e) => e.path,
          'path',
          'saved_design_payload.seg[0].col[0]',
        )),
      );
    });
  });

  group('BUG-GD-PICKER-1 — Firestore round-trip (fake backend)', () {
    late FakeFirebaseFirestore firestore;

    setUp(() => firestore = FakeFirebaseFirestore());

    test('saved payload round-trips byte-for-byte, nested col preserved',
        () async {
      final ref = firestore
          .collection('users')
          .doc('u1')
          .collection('game_day_autopilot')
          .doc('mlb_royals');

      // Seed a base doc, then apply the design write (matches saveDesign's
      // .update() on an existing team doc).
      await ref.set({
        'team_slug': 'mlb_royals',
        'team_name': 'Kansas City Royals',
        'espn_team_id': '7',
        'sport': 'mlb',
        'primary_color': 0xFF004687,
        'secondary_color': 0xFFBD9B5B,
        'created_at': Timestamp.fromDate(DateTime(2026, 7, 1)),
        'updated_at': Timestamp.fromDate(DateTime(2026, 7, 1)),
      });
      await ref.update(buildSaveDesignWrite(buildPickerPayload()));

      final doc = await ref.get();
      final config = GameDayAutopilotConfig.fromFirestore(doc.data()!);

      // Persist bug gone: the label now reflects the saved design name.
      expect(config.savedDesignName, 'Royals Twinkle - Twinkle');
      expect(config.designMode, AutopilotDesignMode.saved);
      expect(config.designLabel, 'Royals Twinkle - Twinkle');
      expect(config.effectId, 17);

      // The payload the apply path (applyGameDayConfigToDevice) will now use
      // for the FIRST time instead of filteredBase — nested col intact.
      expect(config.savedDesignPayload, isNotNull);
      expect(config.savedDesignPayload, equals(buildPickerPayload()));
      final seg0 = (config.savedDesignPayload!['seg'] as List).first as Map;
      expect(seg0['col'], [
        [0, 70, 173, 0],
        [255, 255, 255, 0],
      ]);
    });

    test('RAW nested payload is REJECTED by the fake backend on write '
        '(proves the pre-fix write was dead-on-arrival)', () async {
      final ref = firestore
          .collection('users')
          .doc('u1')
          .collection('game_day_autopilot')
          .doc('mlb_royals');

      // FakeFirebaseFirestore validates + rejects nested arrays exactly like
      // the real backend — the direct analogue of the iOS SIGABRT.
      expect(
        () => ref.set({
          'saved_design_payload': buildPickerPayload(), // RAW nested col
        }),
        throwsA(anything),
      );
    });
  });

  group('BUG-GD-PICKER-1 — tolerant read of saved_design_payload', () {
    GameDayAutopilotConfig readWith(dynamic rawPayload) =>
        GameDayAutopilotConfig.fromFirestore({
          'team_slug': 'mlb_royals',
          'team_name': 'Kansas City Royals',
          'sport': 'mlb',
          'saved_design_payload': rawPayload,
        });

    test('current shape: jsonEncoded String decodes to the Map', () {
      final config = readWith(jsonEncode(buildPickerPayload()));
      expect(config.savedDesignPayload, equals(buildPickerPayload()));
    });

    test('legacy shape: a raw Map is read verbatim (backward compatible)', () {
      // No such doc should exist (the raw write always failed), but tolerate.
      final legacy = {
        'on': true,
        'seg': [
          {
            'fx': 0,
            'col': [
              [1, 2, 3, 0],
            ],
          },
        ],
      };
      final config = readWith(legacy);
      expect(config.savedDesignPayload, equals(legacy));
    });

    test('null / empty / malformed → null (apply path falls back)', () {
      expect(readWith(null).savedDesignPayload, isNull);
      expect(readWith('').savedDesignPayload, isNull);
      expect(readWith('{not valid json').savedDesignPayload, isNull);
      // A non-Map JSON value (e.g. a bare array) is not a payload → null.
      expect(readWith('[1,2,3]').savedDesignPayload, isNull);
    });
  });
}

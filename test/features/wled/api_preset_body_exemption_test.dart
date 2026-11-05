// Roofline slice 2 — an API-command preset body (`o:true`) crosses the wire
// EXACTLY as built, and the relay refuses to carry one.
//
// FAIL-BEFORE (defect-style). On the unchanged code:
//   • normalizeWledPayload rewrites the body's segments: it pads `col` to three
//     slots, injects grp/spc, and re-validates every `i` colour (an RGB triple
//     becomes RGBW). The design preset's hash is computed over the body the
//     builder emits; a save that rewrote it on the way out would never match
//     the controller's stored copy, so every sync would re-save (flash wear)
//     and the read-back would report a mismatch. The owner's rule: the
//     normaliser never touches `o` or `i`.
//   • CloudRelayRepository.savePreset forwards the body to the bridge like any
//     other psave. The relay has no cfg door (no bus facts), no firmware read
//     and no read-back, so none of the slice's gates can run there; the owner
//     allowed refusing. On the unchanged code the relay queues a command
//     document for it.
//
// The non-API cases pin today's behaviour so the exemption is exactly as
// narrow as the `o` key.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A design preset body as the builder emits it, with the two things the
/// normaliser would otherwise rewrite: an RGB-only paint colour and a
/// one-slot `col`, and no grp/spc.
Map<String, dynamic> apiBody() => {
      'o': true,
      'on': true,
      'bri': 200,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': 100,
          'on': true,
          'fx': 0,
          'col': [
            [0, 0, 0]
          ],
          'i': [
            0,
            50,
            [255, 0, 0],
            50,
            100,
            [0, 0, 255, 0],
          ],
        },
        {'id': 1, 'start': 100, 'stop': 200, 'on': false},
      ],
    };

/// The same picture WITHOUT `o`: a live per-pixel apply, which today's
/// canonicalisation must keep handling.
Map<String, dynamic> livePerPixel() => apiBody()..remove('o');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('normalizeWledPayload never touches o or i on an API body', () {
    test('the body comes back with o:true and byte-identical segments', () {
      final input = apiBody();
      final out = normalizeWledPayload(input);
      expect(out['o'], isTrue);
      expect(out['on'], isTrue);
      expect(out['bri'], 200);
      expect(out['seg'], input['seg'],
          reason: 'no col padding, no grp/spc, no i re-validation, no frz');
      expect((out['seg'] as List)[0].containsKey('frz'), isFalse);
      expect((out['seg'] as List)[0].containsKey('grp'), isFalse);
    });

    test('the returned body is a copy — mutating it leaves the input alone',
        () {
      final input = apiBody();
      final out = normalizeWledPayload(input);
      (out['seg'] as List).clear();
      expect((input['seg'] as List).length, 2);
    });

    test('a live per-pixel apply (no o) is canonicalised exactly as before',
        () {
      final out = normalizeWledPayload(livePerPixel());
      final seg0 = (out['seg'] as List)[0] as Map;
      expect(seg0['i'][2], [255, 0, 0, 0], reason: 'RGB → RGBW');
      expect((seg0['col'] as List).length, 3, reason: 'padded');
      expect(seg0['grp'], 1);
      expect(seg0.containsKey('frz'), isFalse,
          reason: 'a per-pixel segment keeps its own freeze');
      final seg1 = (out['seg'] as List)[1] as Map;
      expect(seg1['frz'], isFalse, reason: 'a non-i segment is unfrozen');
    });

    test('o:false is not an API body — normalised like any other payload', () {
      final out = normalizeWledPayload(apiBody()..['o'] = false);
      final seg0 = (out['seg'] as List)[0] as Map;
      expect(seg0['i'][2], [255, 0, 0, 0]);
    });
  });

  group('the relay refuses an API-command preset body', () {
    CloudRelayRepository bridge(FakeFirebaseFirestore fs) => CloudRelayRepository(
          userId: 'u1',
          controllerId: 'c1',
          controllerIp: '10.0.0.32',
          webhookUrl: '',
          firestore: fs,
          commandTimeout: const Duration(milliseconds: 200),
        );

    Future<int> queued(FakeFirebaseFirestore fs) async =>
        (await fs.collection('users').doc('u1').collection('commands').get())
            .docs
            .length;

    test('savePreset with o:true returns false and queues NO command', () async {
      final fs = FakeFirebaseFirestore();
      final ok = await bridge(fs)
          .savePreset(presetId: 10, state: apiBody(), presetName: 'Porch');
      expect(ok, isFalse);
      expect(await queued(fs), 0,
          reason: 'refused before the write: nothing for the bridge to carry');
    });

    test('an ordinary psave body still goes to the bridge (a command is queued)',
        () async {
      final fs = FakeFirebaseFirestore();
      await bridge(fs).savePreset(
          presetId: 10,
          state: const {'on': true, 'bri': 200, 'ib': true},
          presetName: 'NGL On');
      expect(await queued(fs), 1);
    });
  });
}

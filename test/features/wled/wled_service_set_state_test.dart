// Audit 2026-05-29 — coverage for WledService.setState's redirect through
// applyJson + normalizeWledPayload. Without the redirect, setState left
// the device's col[1]/col[2] holding the prior pattern's values; the next
// poll returned all three and the dashboard rendered a "blend" with a
// fingerprint that no longer matched the persisted Now Playing label.
//
// These tests assert the POST-normalize wire payload via the
// `lastSimulatedSetStatePayload` capture hook — the same shape applyJson
// would send to the controller on the live HTTP path. The capture runs
// AFTER normalizeWledPayload so a 1-slot col is observable as the
// 3-slot padded result that the device actually receives.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

void main() {
  group('WledService.setState wire payload (simulation capture)', () {
    late WledService service;

    setUp(() {
      service = WledService('http://mock');
    });

    test('color-only setState → wire seg has col padded to 3 slots', () async {
      final ok = await service.setState(color: const Color(0xFF0000FF));

      expect(ok, isTrue);
      final captured = service.lastSimulatedSetStatePayload;
      expect(captured, isNotNull);
      final seg = (captured!['seg'] as List).first as Map;
      expect(seg['id'], 0,
          reason: 'targeted single-seg shape — triggers Rule 5 pass-through');
      expect(seg['col'], equals([
        [0, 0, 255, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
    });

    test('color + brightness + speed → all fields land, col padded', () async {
      final ok = await service.setState(
        on: true,
        brightness: 200,
        speed: 180,
        color: const Color(0xFFFF0000),
      );

      expect(ok, isTrue);
      final captured = service.lastSimulatedSetStatePayload!;
      expect(captured['on'], isTrue);
      expect(captured['bri'], 200);
      final seg = (captured['seg'] as List).first as Map;
      expect(seg['sx'], 180);
      expect(seg['col'], equals([
        [255, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
    });

    test('forceRgbwZeroWhite: pure RGB color preserved, slots 1+2 cleared',
        () async {
      // The post-Bug B path is what the dashboard color picker hits when
      // the strip is RGBW (Tyler's hardware default). Pure RGB with W=0
      // is what setColor sets when forceRgbwZeroWhite=true.
      await service.setState(
        color: const Color(0xFF00FF00),
        forceRgbwZeroWhite: true,
      );

      final seg = (service.lastSimulatedSetStatePayload!['seg'] as List).first
          as Map;
      expect(seg['col'], equals([
        [0, 255, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
    });

    test('power-off only (no color) → no seg, no col in payload', () async {
      // Top-level-only payload like {'on': false}. normalizeWledPayload
      // pass-through (no seg → nothing to pad).
      await service.setState(on: false);

      final captured = service.lastSimulatedSetStatePayload!;
      expect(captured['on'], isFalse);
      expect(captured.containsKey('seg'), isFalse,
          reason: 'no seg-level fields touched → no seg emitted');
    });

    test('brightness-only slider drag → seg-less payload, no col padding',
        () async {
      // Pure brightness slider — the most frequent setState shape during
      // a user drag. Should not synthesize a col array (would blank the
      // lights).
      await service.setState(brightness: 100);

      final captured = service.lastSimulatedSetStatePayload!;
      expect(captured['bri'], 100);
      expect(captured.containsKey('seg'), isFalse);
    });

    test('speed-only → seg with sx, no col entry (so no padding triggered)',
        () async {
      // sx-only seg has no col key — normalizeWledPayload's col-pad block
      // is gated on `col is List && col.isNotEmpty`, so a col-less seg
      // passes through unchanged.
      await service.setState(speed: 90);

      final seg =
          (service.lastSimulatedSetStatePayload!['seg'] as List).first as Map;
      expect(seg['sx'], 90);
      expect(seg.containsKey('col'), isFalse);
    });

    test('sim-mode state updates remain intact alongside capture', () async {
      // Regression guard for the payload-build-moved-to-top refactor: the
      // sim-state updates that pre-existed must still fire so consumers
      // reading _simOn/_simBri/_simSpeed/_simColor (other tests, simulator
      // surfaces) keep working.
      await service.setState(
        on: true,
        brightness: 150,
        speed: 200,
        color: const Color(0xFFFFAA00),
      );

      // The sim-state updates aren't directly readable from outside the
      // class, but the second setState call should observe them: re-calling
      // with only `on:false` should leave the captured payload's brightness
      // and seg state untouched in the new call's payload (since they were
      // not supplied).
      service.lastSimulatedSetStatePayload = null;
      await service.setState(on: false);
      expect(service.lastSimulatedSetStatePayload!['on'], isFalse);
      expect(
        service.lastSimulatedSetStatePayload!.containsKey('bri'),
        isFalse,
        reason: 'only the fields the second call passed in should land',
      );
    });
  });
}

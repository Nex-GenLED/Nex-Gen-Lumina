// Roofline slice 3 — the AI (claudeProxy) context: the roofline block now
// carries the hardware channels' LED counts, and a "Variations of …" session
// adds a SAVED DESIGN block with the stamped bus lengths and a colour
// summary — and NOTHING that identifies the customer, the design or the
// controller (owner decision 2: AI requests are disclosed as shared with
// Anthropic). The smart system prompt tells the model what to do with the
// block and never to emit per-pixel `i` arrays.
//
// A snapshot of the parts this slice owns (the saved-design block in full,
// the roofline block's header and segment lines), plus the identifier
// assertions. Pure: the builders are static, no Firebase.
//
// Fixture: three buses of 162 / 128 / 100 with a peak at the end of bus 3,
// on controller record ctl-a; a saved design "Porch stripes" owned by
// customer-uid, stamped for three buses of 100 on ctl-a.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/lumina_ai/lumina_ai_service.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

final _now = DateTime(2026, 11, 5);

RooflineConfiguration _threeBuses() => RooflineConfiguration(
      id: 'ctl-a',
      name: 'Roof',
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: 3,
      controllerId: 'ctl-a',
      segments: const [
        RooflineSegment(id: 'a', name: 'Front run', pixelCount: 162, channelIndex: 0),
        RooflineSegment(id: 'b', name: 'Side run', pixelCount: 128, channelIndex: 1),
        RooflineSegment(id: 'c', name: 'Garage run', pixelCount: 90, channelIndex: 2),
        RooflineSegment(id: 'p', name: 'Garage peak', pixelCount: 10, startPixel: 90,
            channelIndex: 2, type: SegmentType.peak),
      ],
    ).withChannelPixelCounts(const {0: 162, 1: 128, 2: 100});

const kStamp = DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);

CustomDesign _saved() => CustomDesign(
      id: 'design-7f3a',
      name: 'Porch stripes',
      ownerId: 'customer-uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      layoutStamp: kStamp,
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(channelId: id, channelName: 'Channel ${id + 1}', ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 50, endLed: 89, color: [0, 0, 255, 0]),
                LedColorGroup(startLed: 90, endLed: 99, color: [10, 10, 12, 0]),
              ]),
      ],
    );

/// Everything about the fixture that must never reach the model.
const kIdentifiers = [
  'Porch stripes',
  'design-7f3a',
  'ctl-a',
  'customer-uid',
  'controller_id',
  'owner_id',
];

final _ipv4 = RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b');
final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');

void main() {
  group('the roofline block', () {
    final text = LuminaBrain.buildRooflineContext(_threeBuses());

    test('names the hardware channels and their LED counts', () {
      expect(
          text,
          startsWith('ROOFLINE INSTALLATION:\n'
              '- Total LED Count: 390\n'
              '- Number of Segments: 4\n'
              '- Hardware channels: 3 (162, 128, 100 LEDs)\n'
              '- Segment Types: 3 horizontal runs, 1 peak\n'));
    });

    test('lists every segment at its whole-controller LEDs, as before', () {
      expect(
          text,
          contains('Segments (in order from LED #0):\n'
              '  Front run (horizontal run): LEDs 0-161 (162 pixels)\n'
              '  Side run (horizontal run): LEDs 162-289 (128 pixels)\n'
              '  Garage run (horizontal run): LEDs 290-379 (90 pixels)\n'
              '  Garage peak (peak): LEDs 380-389 (10 pixels)\n'));
      expect(text, contains('ROOFLINE-AWARE PATTERN GUIDANCE:'));
    });

    test('a map with no bus lengths has no hardware line (unchanged)', () {
      final bare = _threeBuses().copyWith(channelPixelCounts: const {});
      expect(LuminaBrain.buildRooflineContext(bare), isNot(contains('Hardware channels')));
    });

    test('carries no controller id', () {
      expect(text, isNot(contains('ctl-a')));
      expect(text, isNot(matches(_ipv4)));
    });
  });

  group('the saved-design block', () {
    final base = variationBaseFor(_saved())!;
    final text = LuminaBrain.buildSavedDesignContext(base);

    test('is exactly the bus lengths, the colour summary and the rule', () {
      expect(
          text,
          'SAVED DESIGN (the look to make variations of):\n'
          '- Hardware channels: 3 (100, 100, 100 LEDs)\n'
          '- Colours by share of lights: [255,0,0,0] 50%, [0,0,255,0] 40%\n'
          '- Unlit: 10%\n'
          '\n'
          'VARIATION GUIDANCE:\n'
          '- Propose variations of this look: keep its palette as the '
          'starting point and change one colour or the arrangement\n'
          '- Describe the look with colours and an effect only; never '
          'list individual LEDs or per-pixel `i` arrays\n');
    });

    test('carries no identifier and no name', () {
      for (final id in kIdentifiers) {
        expect(text, isNot(contains(id)), reason: id);
      }
      expect(text, isNot(matches(_ipv4)));
      expect(text, isNot(matches(_email)));
    });

    test('never asks for per-pixel data', () {
      expect(text, contains('never list individual LEDs or per-pixel `i` arrays'));
      // No LED index is listed: the only numbers are counts and percentages.
      expect(text, isNot(contains('LEDs 0-')));
      expect(text, isNot(contains('"i"')));
    });
  });

  group('the smart system prompt', () {
    final smart = LuminaAI.debugSmartSystemPrompt;

    test('tells the model what a SAVED DESIGN block is and what to do with it', () {
      expect(smart, contains('when a SAVED DESIGN block is in the context'));
      expect(smart, contains('keep its palette as the starting point'));
    });

    test('forbids per-pixel output for any request', () {
      expect(smart, contains('NEVER output per-pixel `i` arrays or per-LED lists, for any request'));
    });
  });
}

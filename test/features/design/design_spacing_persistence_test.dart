// M8 (followup N3b) — a design can carry its spacing.
//
// `ChannelDesign` had no grp/spc field: a saved "1 On 4 Off" re-applied from My
// Designs with every LED lit, and the tuner opened every design at grp 1/spc 0.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

final _now = DateTime(2026, 9, 19);

CustomDesign _oneOnFourOff() => CustomDesign(
      id: 'd', name: '1 On 4 Off', ownerId: 'u', createdAt: _now, updatedAt: _now,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Ch1', grouping: 1, spacing: 4,
            colorGroups: [LedColorGroup(startLed: 0, endLed: 0, color: [255, 177, 110, 0])]),
        ChannelDesign(channelId: 1, channelName: 'Ch2', grouping: 1, spacing: 4,
            colorGroups: [LedColorGroup(startLed: 0, endLed: 0, color: [255, 177, 110, 0])]),
      ],
    );

void main() {
  test('spacing survives Firestore and copyWith', () {
    final back = CustomDesign.fromFirestoreData('d', _oneOnFourOff().toFirestore());
    expect(back.channels.map((c) => [c.grouping, c.spacing]), [[1, 4], [1, 4]]);
    final edited = back.channels.first.copyWith(spacing: 6);
    expect([edited.grouping, edited.spacing], [1, 6]);
    expect(back.channels.first.copyWith(speed: 9).spacing, 4);
  });

  test('a design saved BEFORE the fields existed reads as the #88 defaults', () {
    final legacy = ChannelDesign.fromJson(const {
      'channel_id': 0, 'channel_name': 'Ch1', 'included': true,
      'color_groups': <dynamic>[], 'effect_id': 0, 'speed': 128, 'intensity': 128,
      'reverse': false, 'led_count': 0,
    });
    expect([legacy.grouping, legacy.spacing], [1, 0]);
  });

  test('out-of-range stored values are clamped to what WLED accepts', () {
    final c = ChannelDesign.fromJson(const {'channel_id': 0, 'grouping': 0, 'spacing': -3});
    expect([c.grouping, c.spacing], [1, 0]);
  });

  test('toWledPayload sends the design\'s own spacing on every channel', () {
    final payload = normalizeWledPayload(_oneOnFourOff().toWledPayload());
    for (final s in (payload['seg'] as List).cast<Map>()) {
      expect(s['grp'], 1);
      expect(s['spc'], 4, reason: 'was pinned to 0 → all LEDs lit');
    }
  });

  test('…and still ASSERTS the defaults for a design with no opinion (#88)', () {
    final plain = CustomDesign(
      id: 'p', name: 'Plain', ownerId: 'u', createdAt: _now, updatedAt: _now,
      channels: const [ChannelDesign(channelId: 0, channelName: 'Ch1', colorGroups: [
        LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0])])],
    );
    final seg = (plain.toWledPayload()['seg'] as List).single as Map;
    expect(seg['grp'], 1);
    expect(seg['spc'], 0);
  });

  test('tuner round trip: payload → SelectorState → payload keeps the spacing', () {
    final state = selectorStateFromPayload(_oneOnFourOff().toWledPayload());
    expect([state.grouping, state.spacing], [1, 4]);
    final seg = (buildSelectorPayload(state.copyWith(spacing: 6))['seg'] as List).single as Map;
    expect(seg['spc'], 6);
    expect(seg['grp'], 1);
  });
}

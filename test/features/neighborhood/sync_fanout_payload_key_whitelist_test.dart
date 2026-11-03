// +122 ADD A (owner, 2026-11-03): the fan-out payload may carry ONLY the keys
// the server function applySyncPattern keeps. The function drops every other
// key silently, so a builder that starts stating a new field would ship an app
// whose closed-app members never receive it, with no error anywhere. This
// test fails first.
//
// The whitelist is the server's, copied here verbatim. If this test fails
// because the app now adds a key: UPDATE AND DEPLOY THE SERVER FUNCTION
// (applySyncPattern's whitelist) BEFORE shipping a build that adds that key,
// then extend the lists below.
//
// Fixtures: the SyncCommand shape of sync_fanout_payload_normalized_test.dart
// (synthetic ids only), over five catalog looks including one Strobe and one
// Lightning — the two the normalizer rewrites — and one palette-driven effect
// (the pal rewrite). The one-segment fixture is what the app sends today
// (one id-less segment; the function partitions on that shape). The
// four-channel fixture is that payload expanded over four channel ids with
// the app's own expander — the shape a four-bus member's engine applies and
// the shape a per-channel fan-out would send — so `id` and `on` are proven
// to be the only keys the expansion adds. Test only; the builder is unchanged.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/sync_fanout_feature_flag.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

/// Top-level keys applySyncPattern keeps.
const Set<String> kServerTopLevelWhitelist = {'on', 'bri', 'seg'};

/// Per-seg-entry keys applySyncPattern keeps.
const Set<String> kServerSegWhitelist = {
  'fx', 'sx', 'ix', 'pal', 'grp', 'spc', 'col', 'bri',
  'c1', 'c2', 'c3', 'o1', 'o2', 'o3', 'frz', 'id', 'on',
};

const String kWhitelistBreachReason =
    'The fan-out payload carries a key applySyncPattern drops. Update and '
    'deploy the server function (applySyncPattern\'s key whitelist) BEFORE '
    'shipping a build that adds a key, then extend the whitelist in this test.';

/// Five catalog looks: Strobe and Lightning (the normalizer rewrites their
/// speed/intensity), Solid, Rainbow (palette-driven: the pal:5 → pal:4
/// rewrite) and Chase.
const List<({String name, int fx, int sx, int ix})> kLooks = [
  (name: 'Strobe', fx: 23, sx: 255, ix: 128),
  (name: 'Lightning', fx: 57, sx: 200, ix: 220),
  (name: 'Solid', fx: 0, sx: 128, ix: 128),
  (name: 'Rainbow', fx: 9, sx: 128, ix: 128),
  (name: 'Chase', fx: 28, sx: 255, ix: 255),
];

void main() {
  final now = DateTime.utc(2026, 11, 3, 20, 0);

  SyncCommand command(({String name, int fx, int sx, int ix}) look) =>
      SyncCommand(
        id: 'c-${look.fx}',
        groupId: 'g',
        effectId: look.fx,
        colors: const [0xFF0000, 0x00FF00],
        speed: look.sx,
        intensity: look.ix,
        brightness: 200,
        startTimestamp: now,
        memberDelays: const {'u1': 0, 'u2': 250},
        timingConfig: const SyncTimingConfig(),
        patternName: look.name,
      );

  ProviderContainer containerWith(_CapturingService service) {
    final c = ProviderContainer(overrides: [
      neighborhoodServiceProvider.overrideWithValue(service),
      syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Every key of [payload] outside the server's whitelist, as
  /// `top:key` / `seg[i]:key`, so the failure names the offender.
  List<String> breaches(Map<String, dynamic> payload) {
    final out = <String>[];
    for (final k in payload.keys) {
      if (!kServerTopLevelWhitelist.contains(k)) out.add('top:$k');
    }
    final seg = payload['seg'];
    if (seg is List) {
      for (var i = 0; i < seg.length; i++) {
        final s = seg[i];
        if (s is! Map) {
          out.add('seg[$i]:not-a-map');
          continue;
        }
        for (final k in s.keys) {
          if (!kServerSegWhitelist.contains(k)) out.add('seg[$i]:$k');
        }
      }
    }
    return out;
  }

  /// The payload broadcastSync hands the fan-out service for [look].
  Future<Map<String, dynamic>> fanoutPayloadFor(
      ({String name, int fx, int sx, int ix}) look) async {
    final svc = _CapturingService();
    final c = containerWith(svc);
    await c
        .read(neighborhoodNotifierProvider.notifier)
        .broadcastSync(command(look));
    expect(svc.fanoutPayloads, hasLength(1),
        reason: 'flag on → exactly one fan-out call for ${look.name}');
    return svc.fanoutPayloads.single;
  }

  test('the five looks are catalog effects (fixture sanity)', () {
    for (final look in kLooks) {
      expect(WledEffectsCatalog.getById(look.fx), isNotNull,
          reason: '${look.name} (fx ${look.fx}) must be a catalog effect');
    }
  });

  group('one-segment fixture: what the app sends applySyncPattern today', () {
    for (final look in kLooks) {
      test('${look.name} (fx ${look.fx}): every key is on the whitelist',
          () async {
        final p = await fanoutPayloadFor(look);
        expect((p['seg'] as List), hasLength(1),
            reason: 'the function partitions on one id-less segment');
        expect(((p['seg'] as List).single as Map).containsKey('id'), isFalse);
        expect(breaches(p), isEmpty, reason: kWhitelistBreachReason);
      });
    }

    test('the normalizer\'s own additions are all on the whitelist '
        '(grp, spc, frz, bri, the options the effect reads, sx/ix/pal)',
        () async {
      // Lightning reads options; Strobe's cap and Rainbow's pal rewrite are
      // exercised above. This pins that the normalizer added SOMETHING — so
      // a future change that made it add a non-whitelisted key is caught by
      // the loop above, not hidden by an empty payload.
      final p = await fanoutPayloadFor(kLooks[1]);
      final s = (p['seg'] as List).single as Map;
      expect(s['frz'], isFalse);
      expect(s.containsKey('grp'), isTrue);
      expect(s.containsKey('spc'), isTrue);
      expect(s.containsKey('bri'), isTrue);
    });
  });

  group('four-channel fixture: the payload expanded over four channel ids', () {
    const fourChannels = [0, 1, 2, 3];

    for (final look in kLooks) {
      test('${look.name} (fx ${look.fx}): four entries, only id and on added',
          () async {
        final p = await fanoutPayloadFor(look);
        final expanded = expandForParticipation(p, fourChannels);
        final seg = expanded['seg'] as List;
        expect(seg, hasLength(4), reason: 'one entry per channel');
        final template = Map<String, dynamic>.from(
            (p['seg'] as List).single as Map);
        for (var i = 0; i < 4; i++) {
          final s = Map<String, dynamic>.from(seg[i] as Map);
          expect(s['id'], fourChannels[i]);
          expect(s['on'], isTrue);
          expect(
              s.keys.toSet().difference(template.keys.toSet()),
              {'id', 'on'},
              reason: 'the expander adds only id and on');
        }
        expect(breaches(expanded), isEmpty, reason: kWhitelistBreachReason);
      });
    }
  });
}

/// `implements` on purpose: the real service's constructor wants a live
/// Firebase app. Only the two calls broadcastSync makes are answered.
class _CapturingService implements NeighborhoodService {
  final List<Map<String, dynamic>> fanoutPayloads = [];
  final List<SyncCommand> broadcasts = [];

  @override
  Future<FanoutResult> fanoutAdHocSync({
    required String groupId,
    required Map<String, dynamic> payload,
  }) async {
    fanoutPayloads.add(payload);
    return const FanoutResult(ok: true);
  }

  @override
  Future<void> broadcastSyncCommand(
    SyncCommand command, {
    Duration writeTimeout = kSyncCommandWriteTimeout,
  }) async {
    broadcasts.add(command);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

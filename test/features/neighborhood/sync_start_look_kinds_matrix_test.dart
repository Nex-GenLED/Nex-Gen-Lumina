// SYNC START WINDOW (2026-11-02, read-only investigation, scratch worktree at
// tag build-121). Question 2 of the brief: for every kind of look the app can
// select as the sync pattern, does the client Start path run to completion up
// to the first network / Firestore call, or does it throw / return nothing?
//
// The path under test is the REAL code, with fakes only at the two
// boundaries the brief names:
//
//   panel _startSync  → engine.createSyncCommand / createComplementCommand
//                     → notifier.broadcastSync
//                         → ref.read(syncFanoutEnabledSyncProvider)   [flag ON here]
//                         → normalizeWledPayload(_buildFanoutPayload(command))
//                         → service.fanoutAdHocSync   → http.post  [MockClient]
//                         → service.broadcastSyncCommand → Firestore [FakeFirebaseFirestore]
//
// The panel itself (_SyncControlPanelState) is not pumped: its build reads
// FirebaseAuth.instance (sync_control_panel.dart:1182), which needs a Firebase
// app. Everything the panel does between the tap and the notifier call is
// data construction, reproduced here with the panel's own argument list
// (sync_control_panel.dart:1265-1305) and the panel's own guard
// (isWellFormedSyncAssignment, sync_control_panel.dart:79).
//
// Fixture: one group, two members, each with ONE denormalised controller id,
// whose controller docs carry participating_channels of 4 and 3 channels.
// Synthetic ids only; 192.0.2.x addresses (TEST-NET-1).

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';
import 'package:nexgen_command/features/design/per_pixel_payload_guard.dart'
    show kPerPixelSyncRefusedMessage;
import 'package:nexgen_command/features/neighborhood/sync_fanout_feature_flag.dart';
import 'package:nexgen_command/features/neighborhood/sync_per_pixel_guard.dart'
    show syncAssignmentCarriesPerPixel;
import 'package:nexgen_command/features/neighborhood/widgets/sync_control_panel.dart'
    show isWellFormedSyncAssignment, syncAssignmentRefusalMessage;
import 'package:nexgen_command/features/wled/pattern_flash_safety.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fixture: the two-member group
// ─────────────────────────────────────────────────────────────────────────────

const kGroupId = 'g-sync-window';
const kHostUid = 'u-host';
const kGuestUid = 'u-guest';
const kHostCtrl = 'ctrl-host';
const kGuestCtrl = 'ctrl-guest';

final kMembers = <NeighborhoodMember>[
  NeighborhoodMember(
    oderId: kHostUid,
    displayName: 'Host',
    positionIndex: 0,
    ledCount: 490,
    controllerIp: '192.0.2.10',
    controllerId: const [kHostCtrl],
    isOnline: true,
    lastSeen: DateTime.utc(2026, 11, 2, 22, 35),
  ),
  NeighborhoodMember(
    oderId: kGuestUid,
    displayName: 'Guest',
    positionIndex: 1,
    ledCount: 286,
    controllerIp: '192.0.2.11',
    controllerId: const [kGuestCtrl],
    isOnline: true,
    lastSeen: DateTime.utc(2026, 11, 2, 22, 35),
  ),
];

/// Seeds the group, both member docs, and both controller docs (4 and 3
/// participating channels). Nothing on the CLIENT Start path reads the
/// controller docs — the server partition does — but the brief asks for the
/// fixture, and the real broadcastSyncCommand is run against this store.
Future<FakeFirebaseFirestore> seedFirestore() async {
  final db = FakeFirebaseFirestore();
  await db.collection('neighborhoods').doc(kGroupId).set({
    'name': 'window',
    'inviteCode': 'ABC123',
    'creatorUid': kHostUid,
    'createdAt': DateTime.utc(2026, 10, 31, 23, 47),
    'memberUids': [kHostUid, kGuestUid],
    'isActive': false,
    'activePatternId': null,
    'activePatternName': null,
  });
  for (final m in kMembers) {
    await db
        .collection('neighborhoods')
        .doc(kGroupId)
        .collection('members')
        .doc(m.oderId)
        .set(m.toFirestore());
  }
  await db.collection('users').doc(kHostUid).collection('controllers').doc(kHostCtrl).set({
    'ip': '192.0.2.10',
    'name': 'Host controller',
    'participating_channels': [0, 1, 2, 3],
  });
  await db.collection('users').doc(kGuestUid).collection('controllers').doc(kGuestCtrl).set({
    'ip': '192.0.2.11',
    'name': 'Guest controller',
    'participating_channels': [0, 1, 2],
  });
  return db;
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixture: every look kind, built with the app's OWN factories
// ─────────────────────────────────────────────────────────────────────────────

class LookKind {
  final String label;
  final SyncPatternAssignment assignment;
  const LookKind(this.label, this.assignment);
}

List<Color> _colors(List<int> rgb) => rgb.map((c) => Color(c | 0xFF000000)).toList();

/// What the Sync Control Center can actually put in _globalPattern at
/// build-121 (sync_control_panel.dart:486-529, 2060-2067): catalog palette +
/// effect via fromLibraryNode, or the const Solid White default. The other
/// kinds (favourite, saved design, two-channel, zone/segment, per-pixel) are
/// built through SyncPatternAssignment.fromWledPayload — the model's own
/// factory, which has NO caller in lib/ at build-121 — so that the builder
/// and normalizer are exercised on those shapes too.
final List<LookKind> kLookKinds = [
  // 1. Built-in effect — Popular strip entry (kFeaturedSyncRefs 'xmas_classic', fx 28)
  LookKind(
    'built-in effect via fromLibraryNode (Popular strip, fx 28)',
    SyncPatternAssignment.fromLibraryNode(
      name: 'Classic Christmas',
      themeColors: _colors([0xFF0000, 0x00FF00]),
      effectId: 28,
      speed: 128,
    ),
  ),
  // 2. Browse-All pick: palette + chosen effect, palette default speed/intensity
  LookKind(
    'built-in effect via Browse-All (fx 77 meteor, palette defaults)',
    SyncPatternAssignment.fromLibraryNode(
      name: 'Classic Halloween - Meteor',
      themeColors: _colors([0xFF6A00, 0x8A2BE2, 0x00FF00]),
      effectId: 77,
      speed: 150,
      intensity: 128,
    ),
  ),
  // 3. No selection: the panel's const default
  const LookKind(
    'default Solid White (no selection)',
    SyncPatternAssignment(name: 'Solid White', effectId: 0, colors: [0xFFFFFF]),
  ),
  // 4. Favourite-shaped payload (single seg, 4-channel colours, pal 5)
  LookKind(
    'favourite (fromWledPayload, single seg)',
    SyncPatternAssignment.fromWledPayload(
      name: 'Fav: Candy Cane',
      payload: {
        'on': true,
        'bri': 180,
        'seg': [
          {'fx': 3, 'sx': 120, 'ix': 200, 'pal': 5, 'col': [[255, 0, 0, 0], [255, 255, 255, 0], [0, 0, 0, 0]]},
        ],
      },
    ),
  ),
  // 5. Saved design with grouping/spacing and installation geometry keys
  LookKind(
    'saved design (grp/spc + geometry keys of/rev)',
    SyncPatternAssignment.fromWledPayload(
      name: 'My Design: Blocks',
      payload: {
        'on': true,
        'bri': 255,
        'seg': [
          {'id': 0, 'fx': 0, 'sx': 128, 'ix': 128, 'pal': 5, 'grp': 7, 'spc': 7, 'of': 3, 'rev': false, 'col': [[255, 0, 0], [0, 0, 255]]},
        ],
      },
    ),
  ),
  // 6. Two-channel design: channel 1 excluded with the {id, on:false} marker (#89)
  LookKind(
    'two-channel design (channel 1 exclusion marker)',
    SyncPatternAssignment.fromWledPayload(
      name: 'Two-channel',
      payload: {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'fx': 15, 'sx': 110, 'ix': 128, 'pal': 5, 'col': [[0, 128, 0, 0], [255, 255, 255, 0]]},
          {'id': 1, 'on': false},
        ],
      },
    ),
  ),
  // 7. Zone / segment look: two bounded segments
  LookKind(
    'zone/segment look (two bounded segs)',
    SyncPatternAssignment.fromWledPayload(
      name: 'Roofline zones',
      payload: {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'start': 0, 'stop': 200, 'fx': 10, 'sx': 140, 'ix': 128, 'pal': 5, 'col': [[255, 120, 0, 0]]},
          {'id': 1, 'start': 200, 'stop': 490, 'fx': 10, 'sx': 140, 'ix': 128, 'pal': 5, 'col': [[120, 0, 255, 0]]},
        ],
      },
    ),
  ),
  // 8. Per-pixel look (Design Studio `i` array) — fromWledPayload reads fx 0
  LookKind(
    'per-pixel look (i array)',
    SyncPatternAssignment.fromWledPayload(
      name: 'Pixel paint',
      payload: {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'i': [0, [255, 0, 0, 0], 1, [0, 255, 0, 0], 2, 10, [0, 0, 255, 0]]},
        ],
      },
    ),
  ),
  // 9. Lightning at the picker maximum
  LookKind(
    'Lightning (57) at sx 200 / ix 220',
    SyncPatternAssignment.fromLibraryNode(
      name: 'Haunted House - Lightning',
      themeColors: _colors([0xFFFFFF, 0x4040FF]),
      effectId: kLightningEffectId,
      speed: 200,
      intensity: 220,
    ),
  ),
  // 10. Strobe family at the slider maximum
  LookKind(
    'Strobe (23) at sx 255',
    SyncPatternAssignment.fromLibraryNode(
      name: 'Frankenstein - Strobe',
      themeColors: _colors([0x00FF00, 0x8A2BE2]),
      effectId: 23,
      speed: 255,
      intensity: 128,
    ),
  ),
  LookKind(
    'Strobe Rainbow (24) at sx 255',
    SyncPatternAssignment.fromLibraryNode(
      name: 'Strobe Rainbow',
      themeColors: _colors([0xFF0000, 0x00FF00, 0x0000FF]),
      effectId: 24,
      speed: 255,
    ),
  ),
  LookKind(
    'retired Strobe Mega (25) from a stored reference',
    SyncPatternAssignment.fromLibraryNode(
      name: 'Old Strobe Mega',
      themeColors: _colors([0xFFFFFF]),
      effectId: 25,
      speed: 255,
    ),
  ),
  // 11. A palette-sweep effect carrying pal 5 (normalizer rewrites to 4)
  LookKind(
    'Rainbow (9) with pal 5 (palette guard path)',
    SyncPatternAssignment.fromLibraryNode(
      name: 'Rainbow',
      themeColors: _colors([0xFF0000, 0x0000FF]),
      effectId: 9,
      pal: 5,
    ),
  ),
  // 12. A colours-only verified particle effect (guard exemption path)
  LookKind(
    'Juggle (64) with pal 5 (exempt from palette guard)',
    SyncPatternAssignment.fromLibraryNode(
      name: 'Juggle',
      themeColors: _colors([0xFF0000, 0xFFFF00]),
      effectId: 64,
      pal: 5,
    ),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Fakes at the two boundaries
// ─────────────────────────────────────────────────────────────────────────────

/// Captures what broadcastSync hands the service, without a network or a
/// store — same shape as sync_fanout_payload_normalized_test.dart.
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// FirebaseAuth / User are sealed; subclassing for a scoped test fake is
// intentional (same pattern as fanout_trigger_flag_gate_test.dart).
// ignore: subtype_of_sealed_class
class _StubAuth implements FirebaseAuth {
  _StubAuth(this._user);
  final User? _user;
  @override
  User? get currentUser => _user;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

// ignore: subtype_of_sealed_class
class _StubUser implements User {
  _StubUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'test-id-token';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

/// Exactly what _startSync builds for the unified path
/// (sync_control_panel.dart:1265-1305), for [global] and optional per-house
/// overrides.
SyncCommand buildAsPanelDoes(
  NeighborhoodSyncEngine engine,
  SyncPatternAssignment global, {
  Map<String, SyncPatternAssignment> perHouse = const {},
  SyncType syncType = SyncType.sequentialFlow,
}) {
  var command = engine.createSyncCommand(
    groupId: kGroupId,
    members: kMembers,
    effectId: global.effectId,
    colors: global.colors,
    speed: global.speed,
    intensity: global.intensity,
    brightness: global.brightness,
    timingConfig: const SyncTimingConfig(pixelsPerSecond: 50.0, gapDelayMs: 0, reverseDirection: false),
    syncType: syncType,
    patternName: global.name,
    pal: global.pal,
    grp: global.grp,
    spc: global.spc,
  );
  if (perHouse.isNotEmpty) {
    command = SyncCommand(
      id: command.id,
      groupId: command.groupId,
      effectId: command.effectId,
      colors: command.colors,
      speed: command.speed,
      intensity: command.intensity,
      brightness: command.brightness,
      startTimestamp: command.startTimestamp,
      memberDelays: command.memberDelays,
      timingConfig: command.timingConfig,
      syncType: command.syncType,
      patternName: command.patternName,
      scheduleId: command.scheduleId,
      pal: command.pal,
      grp: command.grp,
      spc: command.spc,
      memberColorOverrides: command.memberColorOverrides,
      complementTheme: command.complementTheme,
      memberPatternOverrides: Map<String, SyncPatternAssignment>.from(perHouse),
    );
  }
  return command;
}

Map<String, dynamic> seg0(Map<String, dynamic> p) =>
    Map<String, dynamic>.from((p['seg'] as List).first as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────────────────────────────────────────────────────────
  // A. Panel guard + engine builder + notifier builder/normalizer, flag ON
  // ───────────────────────────────────────────────────────────────────────────
  group('Start path to the fan-out boundary (flag ON) — every look kind', () {
    for (final kind in kLookKinds) {
      test(kind.label, () async {
        // 1. The panel's refuse-before-write guard (sync_control_panel.dart:1253)
        //    must PASS for this kind, or Start ends with the red snackbar.
        //    Roofline slice 1, item 4 (owner decision D5): the PER-PIXEL kind
        //    is now the one look the panel refuses, with its own sentence —
        //    the server whitelist drops `i`, so a closed-app neighbour would
        //    show the black base under the design's name. Nothing starts.
        if (syncAssignmentCarriesPerPixel(kind.assignment)) {
          expect(isWellFormedSyncAssignment(kind.assignment), isFalse,
              reason: 'a painted picture cannot be fanned out');
          expect(syncAssignmentRefusalMessage(kind.assignment),
              kPerPixelSyncRefusedMessage);
          return;
        }
        expect(isWellFormedSyncAssignment(kind.assignment), isTrue,
            reason: 'the panel would refuse this look with the red snackbar');

        final svc = _CapturingService();
        final c = ProviderContainer(overrides: [
          neighborhoodServiceProvider.overrideWithValue(svc),
          syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
        ]);
        addTearDown(c.dispose);

        // 2. engine.createSyncCommand with the panel's argument list.
        final engine = c.read(neighborhoodSyncEngineProvider);
        final command = buildAsPanelDoes(engine, kind.assignment);
        expect(command.memberDelays.keys, containsAll([kHostUid, kGuestUid]),
            reason: 'both online members get a delay slot');

        // 3. notifier.broadcastSync: flag read → _buildFanoutPayload →
        //    normalizeWledPayload → fanoutAdHocSync → broadcastSyncCommand.
        final result = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(command);

        expect(result.failure, isNull, reason: 'a failure means the try block threw');
        expect(result.fanout?.ok, isTrue);
        expect(result.commandWritten, isTrue);
        expect(c.read(neighborhoodNotifierProvider).hasError, isFalse);
        expect(svc.fanoutPayloads, hasLength(1), reason: 'the payload reached the POST boundary');
        expect(svc.broadcasts, hasLength(1), reason: 'the group-command write was reached');

        // 4. The normalized payload has the shape the server partitions on.
        final p = svc.fanoutPayloads.single;
        expect(p['on'], isTrue);
        expect(p['bri'], kind.assignment.brightness);
        expect(p['seg'], hasLength(1), reason: 'Slice 1 sends ONE id-less seg');
        final s = seg0(p);
        expect(s.containsKey('id'), isFalse);
        expect(s['fx'], isA<int>());
        expect((s['col'] as List), hasLength(3));
        expect(s['frz'], isFalse);
        expect(s.containsKey('grp'), isTrue);
        expect(s.containsKey('spc'), isTrue);

        // 5. Flash-safety at the chokepoint (build 120, c1fe727).
        final fx = s['fx'] as int;
        if (fx == kLightningEffectId) {
          expect(s['sx'], lessThanOrEqualTo(kLightningSpeedCap));
          expect(s['ix'], lessThanOrEqualTo(kLightningIntensityCap));
        }
        if (kSpeedCappedFlashEffectIds.contains(fx)) {
          expect(s['sx'], lessThanOrEqualTo(kStrobeSpeedCap));
        }
        if (kind.assignment.effectId == 25) {
          expect(fx, kRetiredEffectFallback, reason: 'retired Strobe Mega plays as Strobe');
        }
      });
    }

    test('complement mode (July 4th theme) via createComplementCommand', () async {
      final svc = _CapturingService();
      final c = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(svc),
        syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
      ]);
      addTearDown(c.dispose);
      final engine = c.read(neighborhoodSyncEngineProvider);
      final command = engine.createComplementCommand(
        groupId: kGroupId,
        members: kMembers,
        theme: ComplementThemes.july4th,
        effectIdOverride: 0,
        speed: 128,
        intensity: 128,
        brightness: 200,
      );
      final result = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(command);
      expect(result.fanout?.ok, isTrue);
      expect(svc.fanoutPayloads, hasLength(1));
      expect(svc.broadcasts, hasLength(1));
      // The fan-out carries the GLOBAL (theme fallback) colours; per-member
      // complement colours are app-open-only (Slice 1 dead schema).
      expect((seg0(svc.fanoutPayloads.single)['col'] as List), hasLength(3));
    });

    test('per-house overrides attached (the panel copy at :1284-1305)', () async {
      final svc = _CapturingService();
      final c = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(svc),
        syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
      ]);
      addTearDown(c.dispose);
      final engine = c.read(neighborhoodSyncEngineProvider);
      final command = buildAsPanelDoes(
        engine,
        kLookKinds.first.assignment,
        perHouse: {kGuestUid: kLookKinds[9].assignment}, // guest gets the Strobe
      );
      final result = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(command);
      expect(result.fanout?.ok, isTrue);
      expect(svc.fanoutPayloads, hasLength(1));
      // getPatternForMember('') is the GLOBAL look; the guest override does not
      // reach the fan-out (Slice 1 sends the full payload to everyone).
      expect(seg0(svc.fanoutPayloads.single)['fx'], 28);
      expect(svc.broadcasts.single.memberPatternOverrides, hasLength(1));
    });

    test('simultaneous and patternMatch sync types also complete', () async {
      for (final t in [SyncType.simultaneous, SyncType.patternMatch]) {
        final svc = _CapturingService();
        final c = ProviderContainer(overrides: [
          neighborhoodServiceProvider.overrideWithValue(svc),
          syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
        ]);
        final engine = c.read(neighborhoodSyncEngineProvider);
        final command = buildAsPanelDoes(engine, kLookKinds[1].assignment, syncType: t);
        final result = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(command);
        expect(result.fanout?.ok, isTrue, reason: '$t');
        expect(svc.fanoutPayloads, hasLength(1), reason: '$t');
        c.dispose();
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // B. The REAL service: the HTTP POST and the Firestore writes, every kind
  // ───────────────────────────────────────────────────────────────────────────
  group('Real NeighborhoodService — first network and Firestore calls', () {
    for (final kind in kLookKinds) {
      test('${kind.label}: POST leaves, group command doc is written', () async {
        final db = await seedFirestore();
        final service = NeighborhoodService(firestore: db, auth: _StubAuth(_StubUser(kHostUid)));
        final c = ProviderContainer(overrides: [
          neighborhoodServiceProvider.overrideWithValue(service),
          syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
        ]);
        addTearDown(c.dispose);
        final engine = c.read(neighborhoodSyncEngineProvider);
        final command = buildAsPanelDoes(engine, kind.assignment);

        final posts = <http.Request>[];
        final result = await http.runWithClient(
          () => c.read(neighborhoodNotifierProvider.notifier).broadcastSync(command),
          () => MockClient((req) async {
            posts.add(req);
            return http.Response('{"ok":true}', 200);
          }),
        );

        // The POST (service :535-554) left the device with the fan-out shape.
        expect(posts, hasLength(1), reason: 'exactly one applySyncPattern POST');
        final req = posts.single;
        expect(req.url.path, endsWith('/applySyncPattern'));
        expect(req.headers['Authorization'], 'Bearer test-id-token');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        expect(data['groupId'], kGroupId);
        expect(data['initiatorUid'], kHostUid);
        expect(data['source'], 'sync_fanout');
        expect(data['fanout'], isTrue);
        expect((data['payload'] as Map)['seg'], hasLength(1));
        expect(result.fanout?.ok, isTrue);

        // The group command doc (service :650) and the group flip (:656).
        final cmds = await db.collection('neighborhoods').doc(kGroupId).collection('commands').get();
        expect(cmds.docs, hasLength(1), reason: 'broadcastSyncCommand wrote the command');
        final parsed = SyncCommand.fromFirestore(cmds.docs.single);
        expect(parsed.groupId, kGroupId);
        expect(parsed.patternName, kind.assignment.name);
        final group = await db.collection('neighborhoods').doc(kGroupId).get();
        expect(group.data()!['isActive'], isTrue, reason: 'only this write flips the panel label');
        expect(group.data()!['activePatternName'], kind.assignment.name);
      });
    }

    test('flag OFF: no POST at all, the command doc is still written', () async {
      final db = await seedFirestore();
      final service = NeighborhoodService(firestore: db, auth: _StubAuth(_StubUser(kHostUid)));
      final c = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(service),
        syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(false)),
      ]);
      addTearDown(c.dispose);
      final engine = c.read(neighborhoodSyncEngineProvider);
      final command = buildAsPanelDoes(engine, kLookKinds.first.assignment);
      final posts = <http.Request>[];
      final result = await http.runWithClient(
        () => c.read(neighborhoodNotifierProvider.notifier).broadcastSync(command),
        () => MockClient((req) async {
          posts.add(req);
          return http.Response('{"ok":true}', 200);
        }),
      );
      expect(result.fanout, isNull);
      expect(result.commandWritten, isTrue);
      expect(posts, isEmpty);
      final cmds = await db.collection('neighborhoods').doc(kGroupId).collection('commands').get();
      expect(cmds.docs, hasLength(1));
    });

    test('both members OFFLINE in the roster: command still built and written, '
        'but with an EMPTY delay map (the initiator\'s own engine will not apply it)', () async {
      final db = await seedFirestore();
      final service = NeighborhoodService(firestore: db, auth: _StubAuth(_StubUser(kHostUid)));
      final c = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(service),
        syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
      ]);
      addTearDown(c.dispose);
      final engine = c.read(neighborhoodSyncEngineProvider);
      final offline = kMembers.map((m) => m.copyWith(isOnline: false)).toList();
      final command = engine.createSyncCommand(
        groupId: kGroupId,
        members: offline,
        effectId: 28,
        colors: const [0xFF0000, 0x00FF00],
        speed: 128,
        intensity: 128,
        brightness: 200,
        timingConfig: const SyncTimingConfig(),
        patternName: 'Classic Christmas',
      );
      expect(command.memberDelays, isEmpty, reason: 'engine :164-192 drops offline members');
      final posts = <http.Request>[];
      final result = await http.runWithClient(
        () => c.read(neighborhoodNotifierProvider.notifier).broadcastSync(command),
        () => MockClient((req) async {
          posts.add(req);
          return http.Response('{"ok":true}', 200);
        }),
      );
      expect(result.fanout?.ok, isTrue);
      expect(posts, hasLength(1));
      final cmds = await db.collection('neighborhoods').doc(kGroupId).collection('commands').get();
      expect(cmds.docs, hasLength(1));
      // getDelayForMember → -1 for everyone → engine :608-613 returns before apply.
      expect(SyncCommand.fromFirestore(cmds.docs.single).getDelayForMember(kHostUid), -1);
    });
  });
}

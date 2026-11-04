// SYNC START WINDOW (2026-11-02), item 6: the initiator is never dropped from
// their own Start by a stale presence flag.
//
// Confirmed from code (build-121):
//   * sender — createSyncCommand → _filterActiveMembers dropped every member
//     with isOnline:false, the initiator included, so the delay map had no
//     slot for them;
//   * receiver — the initiator's own engine then returned at
//     "No delay found for current user" (and, even with a slot, the own-apply
//     gate `_shouldParticipateInSync` refused an offline member).
//   Net effect: the initiator's own lights never joined the sync they started,
//   with nothing shown. Paused / opted-out remain explicit choices and still
//   exclude.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';

NeighborhoodMember _member(
  String uid,
  int position, {
  bool online = true,
  MemberParticipationStatus status = MemberParticipationStatus.active,
}) =>
    NeighborhoodMember(
      oderId: uid,
      displayName: uid,
      positionIndex: position,
      ledCount: 300,
      isOnline: online,
      participationStatus: status,
      lastSeen: DateTime.utc(2026, 11, 2),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late NeighborhoodSyncEngine engine;

  setUp(() {
    container = ProviderContainer();
    engine = container.read(neighborhoodSyncEngineProvider);
  });
  tearDown(() => container.dispose());

  SyncCommand build(List<NeighborhoodMember> members, {String? initiatorUid}) =>
      engine.createSyncCommand(
        groupId: 'g',
        members: members,
        effectId: 28,
        colors: const [0xFF0000],
        speed: 128,
        intensity: 128,
        brightness: 200,
        timingConfig: const SyncTimingConfig(),
        patternName: 'x',
        initiatorUid: initiatorUid,
      );

  group('sender — createSyncCommand', () {
    test('initiator flagged offline is KEPT in the delay map when named', () {
      final members = [_member('u-host', 0, online: false), _member('u-guest', 1)];
      final cmd = build(members, initiatorUid: 'u-host');
      expect(cmd.memberDelays.keys, containsAll(['u-host', 'u-guest']));
      expect(cmd.getDelayForMember('u-host'), 0, reason: 'first in position order');
      expect(cmd.getDelayForMember('u-guest'), greaterThan(0));
    });

    test('legacy call without initiatorUid keeps the old behaviour (offline dropped)', () {
      final members = [_member('u-host', 0, online: false), _member('u-guest', 1)];
      final cmd = build(members);
      expect(cmd.memberDelays.keys, ['u-guest']);
      expect(cmd.getDelayForMember('u-host'), -1);
    });

    test('an OTHER offline member is still dropped when the initiator is named', () {
      final members = [_member('u-host', 0), _member('u-guest', 1, online: false)];
      final cmd = build(members, initiatorUid: 'u-host');
      expect(cmd.memberDelays.keys, ['u-host']);
    });

    test('a paused initiator is still excluded (explicit choice, not presence)', () {
      final members = [
        _member('u-host', 0, online: false, status: MemberParticipationStatus.paused),
        _member('u-guest', 1),
      ];
      final cmd = build(members, initiatorUid: 'u-host');
      expect(cmd.memberDelays.keys, ['u-guest']);
    });

    test('complement command forwards the initiator', () {
      final members = [_member('u-host', 0, online: false), _member('u-guest', 1)];
      final cmd = engine.createComplementCommand(
        groupId: 'g',
        members: members,
        theme: ComplementThemes.july4th,
        initiatorUid: 'u-host',
      );
      expect(cmd.memberDelays.keys, containsAll(['u-host', 'u-guest']));
    });
  });

  group('receiver — the own-apply gate', () {
    SyncCommand withSlots(Map<String, int> delays) => SyncCommand(
          id: 'c',
          groupId: 'g',
          effectId: 28,
          colors: const [0xFF0000],
          speed: 128,
          intensity: 128,
          brightness: 200,
          startTimestamp: DateTime.utc(2026, 11, 2),
          memberDelays: delays,
          timingConfig: const SyncTimingConfig(),
        );

    test('offline member WITH a slot (the initiator) participates', () {
      expect(
        engine.shouldParticipateInSync(
          _member('u-host', 0, online: false),
          withSlots(const {'u-host': 0, 'u-guest': 100}),
        ),
        isTrue,
      );
    });

    test('offline member WITHOUT a slot does not', () {
      expect(
        engine.shouldParticipateInSync(
          _member('u-other', 2, online: false),
          withSlots(const {'u-host': 0, 'u-guest': 100}),
        ),
        isFalse,
      );
    });

    test('paused member with a slot still does not (explicit choice)', () {
      expect(
        engine.shouldParticipateInSync(
          _member('u-host', 0, status: MemberParticipationStatus.paused),
          withSlots(const {'u-host': 0}),
        ),
        isFalse,
      );
    });

    test('online member with a slot participates (unchanged)', () {
      expect(
        engine.shouldParticipateInSync(_member('u-guest', 1), withSlots(const {'u-guest': 100})),
        isTrue,
      );
    });
  });
}

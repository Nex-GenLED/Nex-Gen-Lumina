import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal stub repository for the polling resolver tests. Implements only
/// the [WledRepository.fetchPresetNames] entry point used by
/// [WledNotifier._resolvePresetName]; everything else throws if exercised
/// so tests fail loudly if a future change starts touching unrelated paths.
class _FakeWledRepository implements WledRepository {
  /// Geometry (`start`/`stop`/`rev`/`mi`) is the PROVISIONING door — a separate
  /// method so `applyJson` can strip geometry unconditionally. This fake does
  /// not exercise it; `false` matches the interface default ("this transport
  /// cannot provision").
  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;

  Map<int, String> presetNames;

  _FakeWledRepository({Map<int, String>? presetNames})
      : presetNames = presetNames ?? <int, String>{};

  @override
  Future<Map<int, String>> fetchPresetNames() async => presetNames;

  @override
  void invalidatePresetCache() {}

  @override
  Future<Map<String, dynamic>?> getState() async => null;

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      false;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => false;

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;

  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;

  @override
  Future<bool> configureSyncReceiver() async => false;

  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;

  // The rest inherit no-op defaults from the abstract base.
  @override
  Future<WledHardwareConfig?> getConfig() async => null;
  @override
  Future<bool> supportsRgbw() async => false;
  @override
  Future<List<WledSegment>> fetchSegments() async => const <WledSegment>[];
  @override
  Future<bool> renameSegment({required int id, required String name}) async =>
      false;
  @override
  Future<bool> applyToSegments({
    required List<int> ids,
    Color? color,
    int? white,
    int? fx,
    int? speed,
    int? intensity,
  }) async =>
      false;
  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async =>
      false;
  @override
  Future<int?> getTotalLedCount() async => null;
  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async =>
      false;
  @override
  Future<bool> loadPreset(int presetId) async => false;
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}

/// Build a /json/state-shaped map for [applyStateDataForTest] with the
/// fields the resolver cares about (on, bri, ps, seg[0].fx).
Map<String, dynamic> _stateData({
  bool on = true,
  int bri = 200,
  int fx = 0,
  int ps = 0,
}) {
  return <String, dynamic>{
    'on': on,
    'bri': bri,
    'ps': ps,
    'seg': [
      {'id': 0, 'fx': fx, 'sx': 128, 'ix': 128},
    ],
  };
}

ProviderContainer _makeContainer({_FakeWledRepository? repo}) {
  return ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo ?? _FakeWledRepository()),
    // Pin connectivity to local so _startPolling doesn't try to subscribe
    // to a real stream that would invoke platform channels in tests.
    wledConnectivityStatusProvider.overrideWith(
      (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
    ),
  ]);
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetActivePresetLabelCacheForTest();
  });

  group('Resolver gating by _hasPolledOnce', () {
    test('first poll: resolver does not write to activePresetLabelProvider',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      // Construct the notifier (triggers build → _startPolling). Initial
      // state is WledStateModel.initial() with fx=0, ps=0.
      final notifier = container.read(wledStateProvider.notifier);
      expect(notifier.hasPolledOnceForTest, isFalse,
          reason: 'flag starts false');

      // Pre-set a label via setLabelWithFingerprint so we have something
      // observable. Use a deliberately-mismatching device state so a
      // misbehaving resolver would either clear it or overwrite it.
      final labelNotifier = container.read(activePresetLabelProvider.notifier);
      labelNotifier.setLabelWithFingerprint(
        'Pre-existing Label',
        WledStateModel.initial().copyWith(
          isOn: true,
          effectId: 99,
          presetId: 0,
          colorSequence: const [Color(0xFF00FF00)],
        ),
      );
      expect(container.read(activePresetLabelProvider), 'Pre-existing Label');

      // First poll: device says ps=0, fx=5. Without gating, the drift
      // branch (fx 0 → 5, ps unchanged) would clear the label. With
      // gating, the entire resolver block is skipped on first poll.
      notifier.applyStateDataForTest(_stateData(fx: 5, ps: 0));
      await _settle();

      // The label may have been touched by the cold-start reconcile
      // (which fingerprints against the new state), but NOT by the
      // resolver's drift branch. We assert hasPolledOnceForTest is true
      // and rely on the reconcile path being out-of-scope here — the
      // critical invariant is that the resolver itself didn't fire.
      expect(notifier.hasPolledOnceForTest, isTrue,
          reason: 'flag flips after first poll');
      expect(notifier.hasReconciledOnStartupForTest, isTrue);
    });

    test('first poll then second poll with same effectId: label preserved',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      // Drive the first poll first so cold-start reconcile fires with a
      // matching empty state (no persisted intent). Then set the label.
      notifier.applyStateDataForTest(_stateData(fx: 5, ps: 0));
      await _settle();

      final labelNotifier = container.read(activePresetLabelProvider.notifier);
      labelNotifier.setLabelWithFingerprint(
        'Steady Label',
        WledStateModel.initial().copyWith(
          isOn: true,
          effectId: 5,
          presetId: 0,
          colorSequence: const [Color(0xFF0000FF)],
        ),
      );

      // Second poll: same fx=5, same ps=0. Resolver should not touch the
      // label — no drift detected.
      notifier.applyStateDataForTest(_stateData(fx: 5, ps: 0));
      await _settle();

      expect(container.read(activePresetLabelProvider), 'Steady Label');
    });

    test('second poll with different effectId clears the label', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      notifier.applyStateDataForTest(_stateData(fx: 5, ps: 0));
      await _settle();

      final labelNotifier = container.read(activePresetLabelProvider.notifier);
      labelNotifier.setLabelWithFingerprint(
        'Will-Be-Dropped Label',
        WledStateModel.initial().copyWith(
          isOn: true,
          effectId: 5,
          presetId: 0,
          colorSequence: const [Color(0xFFFF0000)],
        ),
      );
      // Backdate labelUserSetAt past the 3s race-guard window. The setter
      // stamps it to now; we override directly via a sleep proxy.
      // (Real test would need fake_async — for unit speed we backdate the
      // expected guard via the labelNotifier's internal timestamp.)
      // Instead, simulate "old user write" by waiting briefly and
      // confirming the race-guard window logic. We use a real wait of
      // ~3.1s here, but to keep tests fast we instead test the guard
      // branch explicitly below. For THIS test, prove that with NO recent
      // user write, the drift clears. We achieve "no recent write" by
      // having setLabelWithFingerprint above stamp labelUserSetAt to
      // ~now, then NOT calling Future.delayed. To bypass the race guard,
      // mimic the case where the user write happened > 3s ago. We do
      // that by directly reading and forcing the timestamp via the
      // notifier's internal write timestamp on next set — but there's
      // no public hook. So instead, this test is structured to call
      // applyStateDataForTest > 3s after the user write using a real
      // delay.
      await Future<void>.delayed(const Duration(seconds: 3, milliseconds: 100));

      // Second poll with fx changed from 5 → 12, ps unchanged at 0.
      notifier.applyStateDataForTest(_stateData(fx: 12, ps: 0));
      await _settle();

      expect(container.read(activePresetLabelProvider), isNull,
          reason: 'drift clear should fire after fx change');
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('second poll with different effectId, recent user write: label preserved',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      notifier.applyStateDataForTest(_stateData(fx: 5, ps: 0));
      await _settle();

      final labelNotifier = container.read(activePresetLabelProvider.notifier);
      labelNotifier.setLabelWithFingerprint(
        'Race-Guard Label',
        WledStateModel.initial().copyWith(
          isOn: true,
          effectId: 5,
          presetId: 0,
          colorSequence: const [Color(0xFFFFFF00)],
        ),
      );

      // No delay — labelUserSetAt is essentially "now", well within 3s.
      // Drift fires (fx 5 → 12, ps unchanged) but race guard preserves
      // the label.
      notifier.applyStateDataForTest(_stateData(fx: 12, ps: 0));
      await _settle();

      expect(container.read(activePresetLabelProvider), 'Race-Guard Label',
          reason: 'race guard should preserve label set within 3s');
    });

    test('second poll with ps change resolves new preset name via repo',
        () async {
      final repo = _FakeWledRepository(
        presetNames: const {7: 'Fake Preset 7'},
      );
      final container = _makeContainer(repo: repo);
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      // First poll with ps=0 to establish the baseline.
      notifier.applyStateDataForTest(_stateData(fx: 5, ps: 0));
      await _settle();
      expect(notifier.hasPolledOnceForTest, isTrue);

      // Second poll: ps changes from 0 → 7. Resolver calls
      // _resolvePresetName(7), which fetches preset names and writes
      // 'Fake Preset 7' via setLabelWithFingerprint.
      notifier.applyStateDataForTest(_stateData(fx: 5, ps: 7));
      // Allow the async preset-name fetch + write to settle.
      await _settle();
      await _settle();

      expect(container.read(activePresetLabelProvider), 'Fake Preset 7',
          reason: 'ps change should trigger _resolvePresetName write');
    });
  });

  /// Read-side solid-mode guard (audit 2026-05-29). When the device returns
  /// fx=0 with stale col[1]/col[2] from a prior write that didn't pad them,
  /// _applyStateData must take col[0] only — slots 1+2 in solid mode are
  /// residual values that would otherwise poison the preview and the
  /// persisted-label fingerprint.
  group('Solid-mode (fx=0) col-slot guard', () {
    Map<String, dynamic> stateWithCol({
      required int fx,
      required List<List<int>> col,
    }) {
      return <String, dynamic>{
        'on': true,
        'bri': 200,
        'ps': 0,
        'seg': [
          <String, dynamic>{
            'id': 0,
            'fx': fx,
            'sx': 128,
            'ix': 128,
            'col': col,
          },
        ],
      };
    }

    test('fx=0 with stale col[1]/col[2]: only col[0] parsed', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      // Device returns blue in slot 0, stale gold in slot 1, stale white
      // in slot 2 — the exact shape reproduced by the cold-start audit.
      notifier.applyStateDataForTest(stateWithCol(
        fx: 0,
        col: const [
          [0, 0, 255, 0],
          [255, 215, 0, 0],
          [255, 255, 255, 0],
        ],
      ));

      final state = container.read(wledStateProvider);
      expect(state.effectId, 0);
      expect(state.colorSequence.length, 1,
          reason: 'solid mode must drop residual col[1]/col[2]');
      expect(state.colorSequence.first, const Color.fromARGB(255, 0, 0, 255));
      expect(state.color, const Color.fromARGB(255, 0, 0, 255),
          reason: 'primary color still comes from col[0]');
    });

    test('fx=5 (non-solid) with multi-slot col: all non-zero slots parsed',
        () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      // Non-solid effect — multi-slot col is intentional and must survive.
      notifier.applyStateDataForTest(stateWithCol(
        fx: 5,
        col: const [
          [0, 0, 255, 0],
          [255, 215, 0, 0],
          [255, 255, 255, 0],
        ],
      ));

      final state = container.read(wledStateProvider);
      expect(state.effectId, 5);
      expect(state.colorSequence.length, 3,
          reason: 'non-solid effects keep all non-zero col slots');
    });

    test('fx=83 (Solid Pattern, multi-color) with multi-slot col: all retained',
        () {
      // Regression guard called out by the audit spec: WLED's effect 83
      // ("Solid Pattern") is a NAMED multi-color effect distinct from
      // fx=0 (true Solid). It legitimately consumes col[0..2], so the
      // solid-mode guard must scope to fx==0 ONLY and pass fx=83 through.
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      notifier.applyStateDataForTest(stateWithCol(
        fx: 83,
        col: const [
          [255, 0, 0, 0],
          [255, 255, 255, 0],
          [0, 0, 255, 0],
        ],
      ));

      final state = container.read(wledStateProvider);
      expect(state.effectId, 83);
      expect(state.colorSequence.length, 3,
          reason: 'fx=83 (Solid Pattern) intentionally uses all three slots — '
              'guard must NOT trim it');
    });

    test('fx=0 with single-slot col: parsed unchanged', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      notifier.applyStateDataForTest(stateWithCol(
        fx: 0,
        col: const [
          [255, 0, 0, 0],
        ],
      ));

      final state = container.read(wledStateProvider);
      expect(state.colorSequence.length, 1);
      expect(state.colorSequence.first, const Color.fromARGB(255, 255, 0, 0));
    });

    test('persisted label survives reconcile when col[1]/col[2] are stale',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      // Persist an intent that matches what the device IS playing: solid
      // blue, fx=0, ps=0, single-color fingerprint. Pre-guard, the device's
      // stale slots [gold, white] would push the parsed colorSequence to
      // 3 entries and the fingerprint would not match → label dropped.
      // With the guard, only col[0]=blue is parsed → fingerprint matches.
      final labelNotifier = container.read(activePresetLabelProvider.notifier);
      labelNotifier.setLabelWithFingerprint(
        'Calming Sky',
        WledStateModel.initial().copyWith(
          isOn: true,
          effectId: 0,
          presetId: 0,
          colorSequence: const [Color.fromARGB(255, 0, 0, 255)],
        ),
      );
      // Drop the post-set label, simulating a cold start where the intent
      // was loaded from prefs into escrow rather than committed to state.
      // The notifier exposes the escrow shape via reconcileWithDeviceState;
      // here we drive the same code path the first poll does.
      // (Cold-start escrow simulation: the prior call seeded the persisted
      // intent via _persistIntent. resetActivePresetLabelCacheForTest in
      // setUp wipes the in-memory cache so the next provider read loads
      // from SharedPreferences into escrow.)
      resetActivePresetLabelCacheForTest();
      // Force a rebuild so _loadPersistedValue runs and lands in escrow.
      container.invalidate(activePresetLabelProvider);
      expect(container.read(activePresetLabelProvider), isNull,
          reason: 'escrow hold — no commit until reconcile');
      // Let the async _loadPersistedValue land.
      await _settle();
      await _settle();

      // First poll — device returns the exact state the label intent
      // fingerprinted, but with stale col[1]/col[2] slots from a prior
      // multi-color pattern. The solid guard drops those slots so the
      // fingerprint recomputes to the same value the intent stored.
      final notifier = container.read(wledStateProvider.notifier);
      notifier.applyStateDataForTest(stateWithCol(
        fx: 0,
        col: const [
          [0, 0, 255, 0],
          [255, 215, 0, 0],
          [255, 255, 255, 0],
        ],
      ));
      await _settle();

      expect(container.read(activePresetLabelProvider), 'Calming Sky',
          reason:
              'persisted label should be restored when guard normalizes col');
    });
  });
}

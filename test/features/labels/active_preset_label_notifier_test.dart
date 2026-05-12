import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/labels/label_intent.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

WledStateModel _state({
  int effectId = 0,
  int presetId = 0,
  Color color = const Color(0xFFFFFFFF),
  List<Color> colorSequence = const [],
  bool isOn = true,
}) {
  return WledStateModel(
    isOn: isOn,
    brightness: 200,
    speed: 128,
    intensity: 128,
    color: color,
    connected: true,
    warmWhite: 0,
    supportsRgbw: false,
    effectId: effectId,
    paletteId: 0,
    presetId: presetId,
    reverse: false,
    colorSequence: colorSequence,
    colorNames: const [],
    customEffectName: null,
    colorGroupSize: 1,
    spacing: 0,
  );
}

/// Wait long enough for the notifier's fire-and-forget _loadPersistedValue
/// future to complete. SharedPreferences mock resolves on the next event
/// loop turn, so a single pumpEventQueue() suffices.
Future<void> _settleAsyncLoad() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  // setMockInitialValues sets the SharedPreferences singleton state;
  // resetActivePresetLabelCacheForTest wipes the module-level cache used
  // by the notifier so each test starts from a clean slate.
  setUp(() {
    resetActivePresetLabelCacheForTest();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ActivePresetLabelNotifier cold-start reconcile', () {
    test('matching device state → label restored from escrow', () async {
      final intent = LabelIntent(
        label: 'KC Royals Twinkle',
        effectId: 43,
        presetId: 0,
        colorFingerprint: 'ff0000ffd700',
        writtenAt: DateTime(2026, 5, 12),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_preset_label_intent': intent.encode(),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activePresetLabelProvider.notifier);
      await _settleAsyncLoad();

      // Before reconcile: intent is in escrow, state is still null.
      expect(container.read(activePresetLabelProvider), isNull);
      expect(notifier.pendingLabelIntentForTest, isNotNull);
      expect(notifier.pendingLabelIntentForTest!.label, 'KC Royals Twinkle');

      // Reconcile with matching device state.
      notifier.reconcileWithDeviceState(_state(
        effectId: 43,
        presetId: 0,
        colorSequence: const [Color(0xFFFF0000), Color(0xFFFFD700)],
      ));

      expect(container.read(activePresetLabelProvider), 'KC Royals Twinkle');
      expect(notifier.pendingLabelIntentForTest, isNull,
          reason: 'escrow is single-use');
    });

    test('effectId mismatch → label cleared and persisted intent dropped',
        () async {
      final intent = LabelIntent(
        label: 'KC Royals Twinkle',
        effectId: 43,
        presetId: 0,
        colorFingerprint: 'ff0000ffd700',
        writtenAt: DateTime(2026, 5, 12),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_preset_label_intent': intent.encode(),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activePresetLabelProvider.notifier);
      await _settleAsyncLoad();

      // Device drifted to a different effect (someone changed it via web UI).
      notifier.reconcileWithDeviceState(_state(
        effectId: 0, // ← was 43
        presetId: 0,
        colorSequence: const [Color(0xFFFFFFFF)],
      ));

      expect(container.read(activePresetLabelProvider), isNull);
      expect(notifier.pendingLabelIntentForTest, isNull);

      // Verify the persisted intent was actually wiped from prefs.
      // Persistence is async; let it settle.
      await _settleAsyncLoad();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_preset_label_intent'), isNull);
    });

    test('color mismatch → label cleared', () async {
      final intent = LabelIntent(
        label: 'Diamond Family Shimmer',
        effectId: 84,
        presetId: 0,
        colorFingerprint: 'b9f2ffffd700',
        writtenAt: DateTime(2026, 5, 12),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_preset_label_intent': intent.encode(),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activePresetLabelProvider.notifier);
      await _settleAsyncLoad();

      // effectId matches but colors differ → controller drifted to a
      // different design with the same effect.
      notifier.reconcileWithDeviceState(_state(
        effectId: 84,
        presetId: 0,
        colorSequence: const [Color(0xFFFF0000), Color(0xFFFFD700)],
      ));

      expect(container.read(activePresetLabelProvider), isNull);
    });

    test('fresh install (no persisted intent) → state stays null', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activePresetLabelProvider.notifier);
      await _settleAsyncLoad();

      expect(container.read(activePresetLabelProvider), isNull);
      expect(notifier.pendingLabelIntentForTest, isNull);

      // Reconcile is a no-op on empty escrow.
      notifier.reconcileWithDeviceState(_state(effectId: 0));
      expect(container.read(activePresetLabelProvider), isNull);
    });

    test('reconcile-no-pending after escrow already drained → no-op', () async {
      final intent = LabelIntent(
        label: 'Test',
        effectId: 0,
        presetId: 0,
        colorFingerprint: 'ffffff',
        writtenAt: DateTime(2026, 5, 12),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_preset_label_intent': intent.encode(),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activePresetLabelProvider.notifier);
      await _settleAsyncLoad();

      // First reconcile commits the label.
      notifier.reconcileWithDeviceState(_state(
        effectId: 0,
        colorSequence: const [Color(0xFFFFFFFF)],
      ));
      expect(container.read(activePresetLabelProvider), 'Test');

      // Second reconcile with a mismatching state must not clear the
      // committed label — escrow was already drained.
      notifier.reconcileWithDeviceState(_state(
        effectId: 99, // would mismatch if escrow still held intent
        colorSequence: const [Color(0xFF000000)],
      ));
      expect(container.read(activePresetLabelProvider), 'Test',
          reason: 'reconcile after escrow drained is a no-op');
    });
  });

  group('Migration from legacy active_preset_label key', () {
    test('old key present, new key absent → old key migrated and deleted',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_preset_label': 'Warm White', // legacy bare string
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activePresetLabelProvider.notifier);
      await _settleAsyncLoad();

      final prefs = await SharedPreferences.getInstance();
      // Legacy key is wiped — no longer reproduces the cold-start bug.
      expect(prefs.getString('active_preset_label'), isNull);
      // New key was never populated (no fingerprint to reconcile against).
      expect(prefs.getString('active_preset_label_intent'), isNull);
      // State stays null — the legacy bare label was deliberately discarded.
      expect(container.read(activePresetLabelProvider), isNull);
    });

    test('both keys present → legacy deleted, new key honored', () async {
      final intent = LabelIntent(
        label: 'Real Label',
        effectId: 0,
        presetId: 0,
        colorFingerprint: 'ffffff',
        writtenAt: DateTime(2026, 5, 12),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_preset_label': 'Stale Legacy',
        'active_preset_label_intent': intent.encode(),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activePresetLabelProvider.notifier);
      await _settleAsyncLoad();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_preset_label'), isNull);

      // Reconcile against matching state — new-key intent commits.
      notifier.reconcileWithDeviceState(_state(
        effectId: 0,
        colorSequence: const [Color(0xFFFFFFFF)],
      ));
      expect(container.read(activePresetLabelProvider), 'Real Label');
    });
  });

  group('setLabelWithFingerprint', () {
    test('writes intent that round-trips to a matching reconcile', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activePresetLabelProvider.notifier);
      await _settleAsyncLoad();

      final state = _state(
        effectId: 43,
        presetId: 0,
        colorSequence: const [Color(0xFFFF0000), Color(0xFFFFD700)],
      );
      notifier.setLabelWithFingerprint('KC Royals Twinkle', state);

      expect(container.read(activePresetLabelProvider), 'KC Royals Twinkle');

      // Let _persistIntent settle, then simulate cold restart.
      await _settleAsyncLoad();
      resetActivePresetLabelCacheForTest();
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final notifier2 = container2.read(activePresetLabelProvider.notifier);
      await _settleAsyncLoad();

      // Escrow holds the intent until reconcile is called.
      expect(container2.read(activePresetLabelProvider), isNull);
      expect(notifier2.pendingLabelIntentForTest?.label, 'KC Royals Twinkle');

      notifier2.reconcileWithDeviceState(state);
      expect(container2.read(activePresetLabelProvider), 'KC Royals Twinkle');
    });
  });
}

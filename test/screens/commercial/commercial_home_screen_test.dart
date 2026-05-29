// Cross-surface parity assertion for the Now Playing label after Item #88e.
//
// Before #88e, CommercialHomeScreen._DashboardTab read activePresetLabelProvider
// directly (raw user intent), while residential wled_dashboard_page._buildNowPlayingBar
// read displayPatternNameProvider (4-priority resolution). Both surfaces could
// render different text for the same controller state.
//
// After #88e, both surfaces read displayPatternNameProvider. This test mounts
// a minimal widget that mirrors what CommercialHomeScreen._NowPlayingSection
// now consumes (the resolver output), and asserts that the same provider state
// produces the same text on both surfaces by construction.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/labels/label_intent.dart';
import 'package:nexgen_command/features/wled/display_pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal reconstruction of CommercialHomeScreen._NowPlayingSection's data
/// flow: read displayPatternNameProvider, render in a Text widget. Mirrors
/// the production code so any drift in the provider chain shows up here.
///
/// We can't import the private _NowPlayingSection directly from the
/// production file, so the test reproduces the consumer pattern. Both
/// surfaces (this test widget AND production _NowPlayingSection) now read
/// the SAME provider, so identical state must produce identical text.
class _ParityHarness extends ConsumerWidget {
  const _ParityHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(displayPatternNameProvider);
    return MaterialApp(home: Scaffold(body: Text(label))); // ignore: avoid_unnecessary_containers
  }
}

/// Spins up a ProviderContainer-backed ProviderScope that pre-populates
/// SharedPreferences with the given Now Playing intent + sets the
/// activePresetLabelProvider through the same setLabelWithFingerprint
/// path the production callers use. Returns the harness for pumping.
Future<void> _pumpWithState(
  WidgetTester tester, {
  required WledStateModel deviceState,
  String? presetLabel,
  WledStateModel? labelDeviceState,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The harness reads displayPatternNameProvider, which reads
        // wledStateProvider + activePresetLabelProvider + allFavoritesProvider.
        // Stub the WLED state via an override that returns our scripted model.
        wledStateProvider.overrideWith(_StubWledNotifier.new),
        _stubInitialWledState.overrideWith((ref) => deviceState),
      ],
      child: const _ParityHarness(),
    ),
  );

  // Set the active preset label after the tree is mounted, using the same
  // public API production callers use. This populates SharedPreferences
  // through the deprecated setter (degenerate fingerprint), but for an
  // already-mounted ProviderContainer the in-memory state reads
  // immediately.
  final container = ProviderScope.containerOf(
    tester.element(find.byType(_ParityHarness)),
  );
  if (presetLabel != null) {
    container.read(activePresetLabelProvider.notifier).setLabelWithFingerprint(
          presetLabel,
          labelDeviceState ?? deviceState,
        );
    await tester.pump();
  }
}

/// Test-only override hook so we can supply a starting WledStateModel via
/// ProviderScope.overrides. Not used by production.
final _stubInitialWledState =
    Provider<WledStateModel>((ref) => WledStateModel.initial());

/// Test-only WledNotifier subclass that bypasses _startPolling (no Timer in
/// tests) and returns whatever the override-provider supplies as initial
/// state. Reads _stubInitialWledState once at build.
class _StubWledNotifier extends WledNotifier {
  @override
  WledStateModel build() {
    final initial = ref.read(_stubInitialWledState);
    return initial;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetActivePresetLabelCacheForTest();
  });

  group('CommercialHomeScreen Now Playing parity (#88e)', () {
    testWidgets(
        'cold-start with persisted label matching device → label rendered',
        (tester) async {
      // Pulla diag sample shape: controller playing fx=0 (Solid), ps=0, one
      // color. Persisted "Blue Line Vibes" with a matching fingerprint
      // should survive cold-start reconcile and render on commercial.
      final deviceState = WledStateModel.initial().copyWith(
        isOn: true,
        effectId: 0,
        presetId: 0,
        colorSequence: const [Color(0xFF0040FF)], // blue
      );
      final matchingIntent = LabelIntent.fromDeviceState(
        label: 'Blue Line Vibes',
        deviceState: deviceState,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_preset_label_intent': matchingIntent.encode(),
      });

      await _pumpWithState(tester, deviceState: deviceState);
      // Allow the async _loadPersistedValue future to settle.
      await tester.pump(const Duration(milliseconds: 50));

      // Trigger reconcile by calling reconcileWithDeviceState directly via
      // the container. In production WledNotifier._applyStateData does
      // this on first poll; in this test we drive it explicitly since
      // _StubWledNotifier overrides build() to skip polling.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_ParityHarness)),
      );
      container
          .read(activePresetLabelProvider.notifier)
          .reconcileWithDeviceState(deviceState);
      await tester.pump();

      // The displayPatternNameProvider should now return "Blue Line Vibes".
      // The same string would render on residential wled_dashboard_page's
      // Now Playing bar via the identical resolver read.
      expect(find.text('Blue Line Vibes'), findsOneWidget);
    });

    testWidgets(
        'cold-start with persisted label NOT matching device → label cleared, '
        'effect-name fallback wins on commercial', (tester) async {
      // Persisted intent says "Blue Line Vibes" with a blue fingerprint, but
      // the device is actually playing red. Reconcile drops the stale
      // label. displayPatternNameProvider falls through to P3 (effect
      // name) which for fx=84 is "Solid Pattern Tri" per the device catalog.
      final actualDevice = WledStateModel.initial().copyWith(
        isOn: true,
        effectId: 84, // 'Solid Pattern Tri' per device /json/effects
        presetId: 0,
        colorSequence: const [Color(0xFFFF0000)],
      );
      final staleIntent = LabelIntent(
        label: 'Blue Line Vibes',
        effectId: 0, // mismatches device's fx=84
        presetId: 0,
        colorFingerprint: '0040ff', // mismatches device's ff0000
        writtenAt: DateTime.utc(2026, 5, 11),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_preset_label_intent': staleIntent.encode(),
      });

      await _pumpWithState(tester, deviceState: actualDevice);
      await tester.pump(const Duration(milliseconds: 50));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_ParityHarness)),
      );
      container
          .read(activePresetLabelProvider.notifier)
          .reconcileWithDeviceState(actualDevice);
      await tester.pump();

      // Stale label gone; P3 effect-name fallback wins.
      expect(find.text('Blue Line Vibes'), findsNothing);
      expect(find.text('Solid Pattern Tri'), findsOneWidget,
          reason:
              'After reconcile drops stale label, P3 effect-name fallback fires. '
              'Identical to what residential dashboard would show.');
    });

    testWidgets('lights off state → "Lights Off" on commercial',
        (tester) async {
      // displayPatternNameProvider P0: isOn=false → "Lights Off".
      // Before #88e, commercial showed "Nothing playing" via the
      // _NowPlayingSection fallback when the raw label was empty.
      // After #88e, both surfaces show "Lights Off" — parity restored.
      final offState = WledStateModel.initial().copyWith(isOn: false);

      await _pumpWithState(tester, deviceState: offState);
      await tester.pump();

      expect(find.text('Lights Off'), findsOneWidget);
    });

    testWidgets(
        'parity: same provider state produces same text on both surfaces',
        (tester) async {
      // The fundamental parity assertion: both residential and commercial
      // now read displayPatternNameProvider. For any provider state S,
      // residential render == commercial render.
      //
      // We verify this structurally: residential's
      // wled_dashboard_page.dart:969 reads displayPatternNameProvider AS
      // ITS EFFECT NAME source; commercial's CommercialHomeScreen.dart:204
      // (post-#88e) reads the SAME provider for its Now Playing label.
      // The harness in this test reads it too — so the rendered text from
      // the harness is exactly the text both production surfaces would
      // render for the same container state.
      final state = WledStateModel.initial().copyWith(
        isOn: true,
        effectId: 12, // 'Fade' per device /json/effects
        presetId: 0,
      );
      await _pumpWithState(tester, deviceState: state);
      await tester.pump();

      // No persisted label; P2 fires only when activePreset is non-null.
      // Falls through to P3 effect name. Expected: 'Fade'.
      expect(find.text('Fade'), findsOneWidget);

      // Now set a label and re-pump. Same state, different active label.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_ParityHarness)),
      );
      container.read(activePresetLabelProvider.notifier).setLabelWithFingerprint(
            'Diamond Family Shimmer',
            state,
          );
      await tester.pump();

      expect(find.text('Diamond Family Shimmer'), findsOneWidget,
          reason: 'P2 active-preset label wins over P3 effect name');
      expect(find.text('Fade'), findsNothing);
    });
  });
}

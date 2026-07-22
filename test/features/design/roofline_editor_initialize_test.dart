import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';

// Safety re-confirmation for the new roofline-setup entry points: entering the
// architectural editor must never crash or blank. initialize() (unchanged by
// this feature) is the load-not-mint spine:
//   - no controller / no user → a clean empty config (create-mode), no throw
//   - a controller WITH a pixelMap → loads it (verified by inspection at
//     roofline_config_providers.dart:397-413; the loaded branch needs Firestore
//     and is exercised on the bench, not here).
void main() {
  test('initialize() with no controller → clean empty create-mode (no throw, '
      'no blank-with-garbage)', () async {
    final container = ProviderContainer(overrides: [
      effectiveUserUidProvider.overrideWithValue(null),
      activePixelMapControllerIdProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(rooflineConfigEditorProvider.notifier);
    await notifier.initialize();

    final state = container.read(rooflineConfigEditorProvider);
    expect(state, isNotNull, reason: 'entry yields a config, never null-crash');
    expect(state!.segments, isEmpty,
        reason: 'no controller → create-mode empty (nothing to blank)');
  });
}

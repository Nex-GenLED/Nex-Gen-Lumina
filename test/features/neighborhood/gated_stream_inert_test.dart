// Proves the defense-in-depth guard used by latestSyncCommandProvider and
// neighborhoodSchedulesProvider: an erroring source stream (e.g. a
// permission-denied read of a gated neighborhoods subcollection) wrapped in
// `.handleError(...)` does NOT surface as an AsyncError on the StreamProvider —
// so a denied read can never propagate an error that blanks the dashboard.
//
// A full test through the real providers would need to force NeighborhoodService
// (which requires FirebaseAuth) to emit a permission-denied stream; without
// firebase_auth_mocks that isn't available, so this validates the exact
// StreamProvider + handleError interaction the guard relies on, with a positive
// control (the same stream WITHOUT the guard does surface AsyncError).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

StreamProvider<int?> _erroringSource() => StreamProvider<int?>((ref) {
      final c = StreamController<int?>();
      c.addError(Exception('permission-denied'));
      // ignore: unawaited_futures
      c.close();
      return c.stream;
    });

Future<void> _pump() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

void main() {
  test('erroring stream WITHOUT the guard → StreamProvider surfaces AsyncError '
      '(positive control: this is what blanked the dashboard)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final unguarded = _erroringSource();

    container.listen(unguarded, (_, __) {}, onError: (_, __) {});
    await _pump();
    expect(container.read(unguarded).hasError, isTrue);
  });

  test('erroring stream WRAPPED in handleError → StreamProvider stays inert '
      '(no AsyncError) — the guard', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Same shape as latestSyncCommandProvider / neighborhoodSchedulesProvider.
    final guarded = StreamProvider<int?>((ref) {
      final c = StreamController<int?>();
      c.addError(Exception('permission-denied'));
      // ignore: unawaited_futures
      c.close();
      return c.stream.handleError((Object e, StackTrace st) {/* swallow */});
    });

    container.listen(guarded, (_, __) {}, onError: (_, __) {});
    await _pump();
    expect(container.read(guarded).hasError, isFalse,
        reason: 'a swallowed stream error must not become an AsyncError that '
            'would blank the home screen');
  });
}

// Strings proposal item 7 (FACTS T-F2): customers never update firmware, so
// Lumina's reply says what is true instead of what to try.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';

void main() {
  test('the no-audio-effects reply does not ask for a firmware update', () {
    expect(
        kAudioModeNoEffectsReply,
        'Your controller has AudioReactive firmware but no audio effects were '
        "detected. Audio Mode isn't available on this controller.");
    expect(kAudioModeNoEffectsReply.toLowerCase(), isNot(contains('updat')));
  });
}

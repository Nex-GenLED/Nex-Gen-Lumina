import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_logic.dart';

/// Design Studio Slice 2 — per-channel capture state for the "Map Roofline"
/// installer step, keyed by channelIndex within the controller being set up.
///
/// Container-scoped (like the wizard's other step providers), so it survives
/// leaving and returning to the step mid-walk — the marks persist. Reset by
/// [resetInstallerWizardState].
class ChannelCaptureState {
  final List<CaptureMark> marks;

  /// The installer explicitly chose "Map later" for this channel.
  final bool skipped;

  /// This channel's map has been compiled + saved to Firestore.
  final bool saved;

  const ChannelCaptureState({
    this.marks = const [],
    this.skipped = false,
    this.saved = false,
  });

  bool get hasMarks => marks.isNotEmpty;

  /// A channel counts as "addressed" once it's been saved or explicitly skipped.
  bool get isAddressed => saved || skipped;

  ChannelCaptureState copyWith({
    List<CaptureMark>? marks,
    bool? skipped,
    bool? saved,
  }) {
    return ChannelCaptureState(
      marks: marks ?? this.marks,
      skipped: skipped ?? this.skipped,
      saved: saved ?? this.saved,
    );
  }
}

class RooflineCaptureNotifier
    extends StateNotifier<Map<int, ChannelCaptureState>> {
  RooflineCaptureNotifier() : super(const {});

  ChannelCaptureState channel(int channelIndex) =>
      state[channelIndex] ?? const ChannelCaptureState();

  void _set(int channelIndex, ChannelCaptureState s) {
    state = {...state, channelIndex: s};
  }

  /// Append a mark in INSERTION order (so [undoLast] removes the truly
  /// most-recent tap; [compileMarksToChannelSegments] sorts internally, so
  /// storage order doesn't affect the compiled feature list). Adding clears any
  /// prior "skipped"/"saved" flag — the channel is being (re)mapped.
  void addMark(int channelIndex, CaptureMark mark) {
    final cur = channel(channelIndex);
    _set(channelIndex,
        cur.copyWith(marks: [...cur.marks, mark], skipped: false, saved: false));
  }

  /// Remove the most recently added mark.
  void undoLast(int channelIndex) {
    final cur = channel(channelIndex);
    if (cur.marks.isEmpty) return;
    final marks = [...cur.marks]..removeLast();
    _set(channelIndex, cur.copyWith(marks: marks, saved: false));
  }

  /// Replace the mark at [index] (e.g. adjust its pixel ±N). Preserves order.
  void updateMark(int channelIndex, int index, CaptureMark mark) {
    final cur = channel(channelIndex);
    if (index < 0 || index >= cur.marks.length) return;
    final marks = [...cur.marks];
    marks[index] = mark;
    _set(channelIndex, cur.copyWith(marks: marks, saved: false));
  }

  void removeMark(int channelIndex, int index) {
    final cur = channel(channelIndex);
    if (index < 0 || index >= cur.marks.length) return;
    final marks = [...cur.marks]..removeAt(index);
    _set(channelIndex, cur.copyWith(marks: marks, saved: false));
  }

  /// Replace all marks for a channel (used by copy-across-channels, which
  /// copies compiled segments back into an equivalent mark set — or the UI can
  /// set marks directly).
  void setMarks(int channelIndex, List<CaptureMark> marks) {
    final sorted = [...marks]..sort((a, b) => a.pixel.compareTo(b.pixel));
    _set(channelIndex, channel(channelIndex).copyWith(marks: sorted, saved: false, skipped: false));
  }

  void markSaved(int channelIndex) {
    _set(channelIndex, channel(channelIndex).copyWith(saved: true, skipped: false));
  }

  void markSkipped(int channelIndex) {
    _set(channelIndex, channel(channelIndex).copyWith(skipped: true));
  }

  void reset() => state = const {};
}

/// Per-channel capture state for the active Map-Roofline session.
final rooflineCaptureProvider =
    StateNotifierProvider<RooflineCaptureNotifier, Map<int, ChannelCaptureState>>(
  (ref) => RooflineCaptureNotifier(),
);

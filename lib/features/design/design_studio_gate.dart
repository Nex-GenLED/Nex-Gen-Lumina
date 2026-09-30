import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_segmentation.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

// +110 package E2, item 1a — "may Design Studio open?"
//
// Design Studio's selection unit is the named roofline feature (corner, peak,
// run). Until a roofline is SEGMENTED — it has a map, and every mapped channel
// has its features marked — there is nothing to select, and the old studio
// either composed onto a whole-house strip or did nothing at all (audit
// row 2). The gate names what is missing and opens the walkthrough that fixes
// it. It never lets the studio no-op.
//
// The roofline it asks about is the EXPLICIT controller
// (activePixelMapControllerIdProvider: the selected one, else the account's
// only one). With two controllers and none selected there is no roofline to
// gate on, and the gate says so rather than guessing.

/// Why Design Studio is (not) open.
enum DesignStudioGateState {
  /// The roofline is still being read.
  loading,

  /// The account has no controller record yet.
  noController,

  /// Two or more controllers and none selected: nothing to gate on.
  chooseController,

  /// The controller has no roofline map at all.
  noMap,

  /// There is a map, but no channel has its features marked.
  unsegmented,

  /// Some channels are marked and some are not.
  partlySegmented,

  /// Every mapped channel is marked: the studio may open.
  ready,
}

/// The gate's answer plus the sentences the blocked view shows.
class DesignStudioGate {
  const DesignStudioGate({
    required this.state,
    required this.title,
    required this.message,
    required this.segmentation,
    this.actionLabel,
  });

  final DesignStudioGateState state;

  /// Short heading, e.g. "Mark your roofline first".
  final String title;

  /// What is missing, in the customer's words.
  final String message;

  /// The primary button's label, or null when there is nothing to tap.
  final String? actionLabel;

  /// The segmentation the answer was read from ([RooflineSegmentation.none]
  /// when it is not known yet).
  final RooflineSegmentation segmentation;

  bool get isReady => state == DesignStudioGateState.ready;

  /// True when the primary action is the feature walkthrough.
  bool get opensWalkthrough =>
      state == DesignStudioGateState.noMap ||
      state == DesignStudioGateState.unsegmented ||
      state == DesignStudioGateState.partlySegmented;

  static const DesignStudioGate _loading = DesignStudioGate(
    state: DesignStudioGateState.loading,
    title: 'Checking your roofline…',
    message: 'One moment while your roofline map loads.',
    segmentation: RooflineSegmentation.none,
  );

  static const DesignStudioGate _noController = DesignStudioGate(
    state: DesignStudioGateState.noController,
    title: 'No controller yet',
    message: 'Design Studio paints your roofline by its corners, peaks and '
        'runs. Your installer sets up your controller and roofline first — '
        "once that's done, Design Studio opens here.",
    segmentation: RooflineSegmentation.none,
  );

  static const DesignStudioGate _chooseController = DesignStudioGate(
    state: DesignStudioGateState.chooseController,
    title: 'Choose a controller',
    message: 'You have more than one controller. Choose the one you want to '
        'design for on the Home screen, then come back to Design Studio.',
    segmentation: RooflineSegmentation.none,
  );

  static const DesignStudioGate _noMap = DesignStudioGate(
    state: DesignStudioGateState.noMap,
    title: "Your roofline isn't mapped yet",
    message: 'Design Studio needs to know where your corners, peaks and runs '
        "are. Mark them once — one light at a time on the house — and you'll "
        'be able to paint each section.',
    actionLabel: 'Mark corners and peaks',
    segmentation: RooflineSegmentation.none,
  );
}

/// The gate for the roofline the app is reading right now.
final designStudioGateProvider = Provider<DesignStudioGate>((ref) {
  final controllersAsync = ref.watch(controllersStreamProvider);
  final controllers = controllersAsync.valueOrNull ?? const <ControllerInfo>[];
  final selected = ref.watch(selectedControllerIdProvider);
  final selectedIp = ref.watch(selectedDeviceIpProvider);

  if (controllers.isEmpty && controllersAsync.isLoading) {
    return DesignStudioGate._loading;
  }
  if (controllers.isEmpty && (selectedIp == null || selectedIp.isEmpty)) {
    return DesignStudioGate._noController;
  }
  if (controllers.length > 1 &&
      (selected == null || selected.isEmpty) &&
      ref.watch(activePixelMapControllerIdProvider) == null) {
    return DesignStudioGate._chooseController;
  }

  final segAsync = ref.watch(rooflineSegmentationProvider);
  return segAsync.when(
    loading: () => DesignStudioGate._loading,
    // An unreadable map reads as "not mapped": the walkthrough writes a new
    // one either way, and a spinner that never ends is the silence row 2
    // was about.
    error: (_, __) => DesignStudioGate._noMap,
    data: (seg) => gateForSegmentation(seg),
  );
});

/// Pure: the gate for a known [seg].
DesignStudioGate gateForSegmentation(RooflineSegmentation seg) {
  if (!seg.hasMap) return DesignStudioGate._noMap;
  if (seg.isSegmented) {
    return DesignStudioGate(
      state: DesignStudioGateState.ready,
      title: 'Ready',
      message: '',
      segmentation: seg,
    );
  }
  if (seg.isPartlySegmented) {
    final n = seg.unmarkedChannels.length;
    final names =
        seg.unmarkedChannels.map((c) => 'Channel ${c + 1}').join(', ');
    return DesignStudioGate(
      state: DesignStudioGateState.partlySegmented,
      title: 'Almost there',
      message: n == 1
          ? "$names's corners and peaks aren't marked yet. Mark them and "
              'Design Studio opens.'
          : "The corners and peaks on $names aren't marked yet. Mark them "
              'and Design Studio opens.',
      actionLabel: 'Mark the rest',
      segmentation: seg,
    );
  }
  return DesignStudioGate(
    state: DesignStudioGateState.unsegmented,
    title: "Your roofline's corners and peaks aren't marked yet",
    message: 'Design Studio paints by section — a corner, a peak, a run. '
        'Your roofline is traced but its sections have no names yet. Mark '
        'them once, one light at a time on the house, and each section '
        'becomes something you can select and paint.',
    actionLabel: 'Mark corners and peaks',
    segmentation: seg,
  );
}

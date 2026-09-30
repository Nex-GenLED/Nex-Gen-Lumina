import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_studio_feature_flag.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_segmentation.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';

// +110 package E2, item 1a — "may Design Studio open?"
//
// Design Studio's selection unit is the named roofline feature (corner, peak,
// run). Until a roofline is SEGMENTED — it has a map, and every mapped channel
// has its features marked — there is nothing to select by section, and the
// old studio either composed onto a whole-house strip or did nothing at all
// (audit row 2). The gate names what is missing and opens the walkthrough
// that fixes it. It never lets the studio no-op.
//
// +110 E2 follow-up D1 — the segmentation requirement is SOFT by default.
// No production install had its sections marked when the gate shipped, so a
// hard gate would have closed the studio on every customer at once. Now:
//
//   * no controller, two controllers with none selected, and no map at all
//     still BLOCK — there is nothing to paint on;
//   * an unmarked (or partly marked) map OPENS the studio with a dismissible
//     banner that offers the walkthrough (DesignStudioGateState.openUnmarked),
//     unless the gate is HARD for this install;
//   * the gate is hard when the fleet flag
//     config/design_studio.requireSegmentation is true, or when the map
//     carries installer-written features (an `architectural_role` on any
//     segment: only the installer's Map Roofline step and the installer
//     Roofline Setup Wizard write it) — an installer who marked sections at
//     install meant the studio to work by section.
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

  /// There is a map, but no channel has its features marked (hard gate).
  unsegmented,

  /// Some channels are marked and some are not (hard gate).
  partlySegmented,

  /// The map is not (fully) marked, but the gate is soft: the studio opens
  /// with a banner that offers the walkthrough.
  openUnmarked,

  /// Every mapped channel is marked: the studio may open.
  ready,
}

/// The gate's answer plus the sentences the blocked view (or banner) shows.
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

  /// True when the studio may open (fully marked, or soft-gated).
  bool get isReady =>
      state == DesignStudioGateState.ready ||
      state == DesignStudioGateState.openUnmarked;

  /// True when the studio is open but should show the "mark your sections"
  /// banner (D1 soft gate).
  bool get showsBanner => state == DesignStudioGateState.openUnmarked;

  /// True when the primary action is the feature walkthrough (a map exists,
  /// its sections are not all marked).
  bool get opensWalkthrough =>
      state == DesignStudioGateState.unsegmented ||
      state == DesignStudioGateState.partlySegmented ||
      state == DesignStudioGateState.openUnmarked;

  /// True when the primary action is tracing the roofline: there is no map
  /// yet, and the walkthrough marks sections ON a traced map.
  bool get opensTrace => state == DesignStudioGateState.noMap;

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
        'are. Trace your roofline on your house photo first (or ask your '
        "installer), then mark its corners and peaks, and you'll be able to "
        'paint each section.',
    actionLabel: 'Trace your roofline',
    segmentation: RooflineSegmentation.none,
  );
}

/// D1 — the soft-gate banner, once dismissed, stays dismissed for the rest
/// of the app session (not per visit: a customer who has no intention of
/// marking sections should not be asked on every open).
final designStudioBannerDismissedProvider =
    StateProvider<bool>((ref) => false);

/// Pure: true when [config] carries a feature the installer wrote. Only the
/// installer's Map Roofline step and the installer Roofline Setup Wizard set
/// `architectural_role`; the customer walkthrough sets `type` and
/// `feature_confirmed` and leaves the role alone.
bool mapCarriesInstallerFeatures(RooflineConfiguration? config) {
  if (config == null) return false;
  for (final s in config.segments) {
    if (s.architecturalRole != null) return true;
  }
  return false;
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

  // D1 — hard when the fleet says so, or when the installer marked sections
  // on this install. The flag's loading window reads as OFF: a customer never
  // meets the hard gate because the flag had not arrived yet.
  final fleetRequires = ref
      .watch(designStudioRequireSegmentationProvider)
      .maybeWhen(data: (v) => v, orElse: () => false);
  final installerMarked = mapCarriesInstallerFeatures(
      ref.watch(currentRooflineConfigProvider).valueOrNull);
  final requireSegmentation = fleetRequires || installerMarked;

  final segAsync = ref.watch(rooflineSegmentationProvider);
  return segAsync.when(
    loading: () => DesignStudioGate._loading,
    // An unreadable map reads as "not mapped": the walkthrough writes a new
    // one either way, and a spinner that never ends is the silence row 2
    // was about.
    error: (_, __) => DesignStudioGate._noMap,
    data: (seg) =>
        gateForSegmentation(seg, requireSegmentation: requireSegmentation),
  );
});

/// Pure: the gate for a known [seg]. With [requireSegmentation] false (the
/// default, as in production) an unmarked or partly marked map opens the
/// studio behind a banner instead of blocking it; no map at all still blocks.
DesignStudioGate gateForSegmentation(
  RooflineSegmentation seg, {
  bool requireSegmentation = false,
}) {
  if (!seg.hasMap) return DesignStudioGate._noMap;
  if (seg.isSegmented) {
    return DesignStudioGate(
      state: DesignStudioGateState.ready,
      title: 'Ready',
      message: '',
      segmentation: seg,
    );
  }
  if (!requireSegmentation) {
    final partly = seg.isPartlySegmented;
    return DesignStudioGate(
      state: DesignStudioGateState.openUnmarked,
      title: partly
          ? "Some sections aren't marked yet"
          : "Your sections aren't marked yet",
      message: partly
          ? 'Mark the rest of your corners and peaks and every section becomes '
              'something you can select and paint.'
          : 'Mark your corners and peaks once and each section of your '
              'roofline becomes something you can select and paint.',
      actionLabel: partly ? 'Mark the rest' : 'Mark corners and peaks',
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

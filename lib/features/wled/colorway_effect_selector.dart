import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart' show PatternRepository;
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart' show WledStateModel;
import 'package:nexgen_command/features/wled/wled_repository.dart' show WledRepository;
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/schedule/schedule_off_warning.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/effect_speed_slider.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/nav.dart' show AppRoutes;
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';

/// Compose a richer Now Playing label for the Colorway / Architectural
/// Apply path. Stopgap for the current single-string `activePresetLabelProvider`
/// model — the systemic fix (NowPlayingContext struct + migration of all
/// 12 Apply paths) is tracked as Item #81 for v1.0.1.
///
/// Returns `"{parent name} {parent description}, {palette name}"` when the
/// parent has both, or `"{parent name}, {palette name}"` when description is
/// null/empty. Falls back to the bare palette name when the parent is null
/// or has an empty name.
@visibleForTesting
String composeColorwayLabel(LibraryNode paletteNode, LibraryNode? parentNode) {
  final paletteName = paletteNode.name;
  if (parentNode == null || parentNode.name.isEmpty) return paletteName;
  final desc = parentNode.description;
  final parentLabel = (desc != null && desc.isNotEmpty)
      ? '${parentNode.name} $desc'
      : parentNode.name;
  return '$parentLabel, $paletteName';
}

/// A design chosen from the library in SELECTION mode — returned to the caller
/// (e.g. the schedule "choose a pattern" flow) instead of being applied. Same
/// shape the legacy schedule picker returned (`PatternSelection`): the caller
/// maps it straight into whatever it stores. [wledPayload] is the RAW design
/// payload (pre channel-filter), matching `GradientPattern.toWledPayload()` /
/// `CustomDesign.toWledPayload()` so it round-trips into a ScheduleItem.
class LibraryDesignSelection {
  final String id;
  final String name;
  final String imageUrl;
  final Map<String, dynamic> wledPayload;
  const LibraryDesignSelection({
    required this.id,
    required this.name,
    required this.wledPayload,
    this.imageUrl = '',
  });
}

/// Effect selector page that replaces the pattern grid.
/// Shows a large live preview with filter chips and curated effect grid.
class ColorwayEffectSelectorPage extends ConsumerStatefulWidget {
  final LibraryNode paletteNode;

  /// When non-null, this selector is operating inside the Game Day
  /// picker. Committing a pattern (via [_applyPattern]) will persist
  /// the design to the team's GameDayAutopilotConfig via saveDesign.
  /// Preview-apply (the debounced [_sendToWled] path) is intentionally
  /// NOT wired to saveDesign — that path fires on every knob twist
  /// and would otherwise spam Firestore with intermediate states.
  final String? teamSlug;

  /// When non-null, this selector is in SELECTION mode (e.g. the schedule
  /// pattern picker): committing RETURNS the chosen design via this callback
  /// instead of applying to lights or persisting to Game Day. Null (the
  /// default) preserves the normal apply-on-tap behavior byte-for-byte.
  final void Function(LibraryDesignSelection selection)? onDesignSelected;

  /// DESIGN-EDIT mode. When non-null this tuner is editing a STORED design
  /// rather than browsing a catalog palette: the seven selector providers are
  /// seeded from the design, the three catalog exits are hidden, and the only
  /// commit is "Save to design" → `updateDesign` with the original id.
  ///
  /// [paletteNode] is still required and still drives every existing build
  /// path — `forDesign` synthesises one from the design so catalog mode's code
  /// is byte-identical rather than threaded with null checks.
  final CustomDesign? editingDesign;

  bool get isDesignEdit => editingDesign != null;

  const ColorwayEffectSelectorPage({
    super.key,
    required this.paletteNode,
    this.teamSlug,
    this.onDesignSelected,
    this.editingDesign,
  });

  /// Opens the tuner on a stored effect design.
  ///
  /// The synthesised node carries the design's name and its colours, which is
  /// all the existing build code reads off `paletteNode` (`_paletteColors`,
  /// the header, the preview). No metadata is copied, so `_isBrightnessGradient`
  /// is false and the gradient branch is unreachable in design-edit mode — a
  /// stored design is never a brightness-gradient catalog node.
  factory ColorwayEffectSelectorPage.forDesign({
    Key? key,
    required CustomDesign design,
  }) {
    final colors = <Color>[];
    for (final ch in design.channels.where((c) => c.included)) {
      for (final g in ch.colorGroups) {
        colors.add(g.flutterColor);
        if (colors.length >= 3) break;
      }
      if (colors.length >= 3) break;
    }
    return ColorwayEffectSelectorPage(
      key: key,
      paletteNode: LibraryNode(
        id: 'design_${design.id}',
        name: design.name,
        nodeType: LibraryNodeType.palette,
        themeColors: colors.isEmpty ? const <Color>[Colors.white] : colors,
      ),
      editingDesign: design,
    );
  }

  @override
  ConsumerState<ColorwayEffectSelectorPage> createState() =>
      _ColorwayEffectSelectorPageState();
}

class _ColorwayEffectSelectorPageState
    extends ConsumerState<ColorwayEffectSelectorPage> {
  Timer? _debounceTimer;

  /// SELECTION MODE only. The pre-preview device look, snapshotted on entry
  /// (see [initState]) so both exits — Save ("Set design") and Cancel (backing
  /// out / dispose) — can RESTORE it. The live preview writes to the real
  /// lights on every adjustment ([_sendToWled]); but choosing a pattern for a
  /// SCHEDULE must not leave it applied now, so we undo the preview on exit.
  ///
  /// This is [WledStateModel] — the freshest app-side device model (polled
  /// ~1.5s by WledNotifier) — not a byte-exact external device snapshot; the
  /// app only holds what this model can express (accepted trade-off). Restore
  /// re-applies it via [WledRepository.applyJson], the SAME mechanism the
  /// preview uses (no config/preset write). Null once restored/consumed so we
  /// never restore twice.
  WledStateModel? _capturedLook;

  /// DESIGN-EDIT only. The seven selector providers as they were on entry.
  ///
  /// They are GLOBAL StateProviders shared with catalog browsing, so seeding
  /// them from a design would otherwise leak that design's settings into the
  /// next catalog palette the user opens. Restored on cancel and on save.
  SelectorState? _providerSnapshot;
  bool _snapshotRestored = false;

  // ── Restore cache (selection mode) ──────────────────────────────────────
  // The CANCEL exit runs in [dispose], where flutter_riverpod forbids `ref`.
  // So we snapshot everything the restore write needs — the repository, the
  // demo-mode flag, and the fully channel-filtered restore payload — while
  // `ref` is live (on entry and refreshed each build via [_refreshRestoreCache]).
  // [_restoreCapturedLook] then touches ONLY these fields, never `ref`, so it
  // is safe to fire from dispose().
  WledRepository? _restoreRepo;
  bool _restoreDemoMode = false;
  Map<String, dynamic>? _restorePayload;

  List<Color> get _paletteColors =>
      widget.paletteNode.themeColors ?? [Colors.white];

  @override
  void initState() {
    super.initState();
    // CAPTURE-ON-ENTRY (selection mode): snapshot the pre-preview device look
    // now, before any [_sendToWled] preview write can fire. Read synchronously
    // from the polled wledStateProvider so it reflects the device state the
    // user is leaving — held in a local field, NOT re-read later (the poll
    // would pick up our own preview writes and pollute it).
    if (widget.onDesignSelected != null) {
      _capturedLook = ref.read(wledStateProvider);
      _refreshRestoreCache();
    }
    // Initialize selector state from palette metadata (architectural patterns
    // store grouping/spacing here) or fall back to defaults.
    final meta = widget.paletteNode.metadata;
    final initGrouping = (meta?['grouping'] as int?) ?? (meta?['bandWidth'] as int?) ?? 1;
    final initSpacing = (meta?['spacing'] as int?) ?? 0;
    final isBrGradient = meta?['type'] == 'brightness_gradient';
    // Resolve initial gradient preset index from node ID suffix
    int initPreset = 0;
    if (isBrGradient) {
      final nodeId = widget.paletteNode.id;
      final suffix = nodeId.contains('_gradients_') ? nodeId.split('_gradients_').last : '';
      final presets = PatternRepository.brightnessGradientPresets;
      for (var pi = 0; pi < presets.length; pi++) {
        if (presets[pi].id == suffix) { initPreset = pi; break; }
      }
    }
    // DESIGN-EDIT: snapshot the shared providers BEFORE anything overwrites
    // them, so cancel can put them back for the next catalog visit.
    if (widget.isDesignEdit) {
      _providerSnapshot = _readSelectorState();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isDesignEdit) {
        // Seeding only SETS providers — it deliberately does not call
        // _sendToWled(), so opening the editor does not touch the house. The
        // house changes when the user moves a control (live preview) or
        // commits, exactly as in catalog mode.
        _seedFromDesign(widget.editingDesign!);
        return;
      }
      ref.read(selectorEffectIdProvider.notifier).state = 0;
      ref.read(selectorSpeedProvider.notifier).state = getSpeedProfile(0).rawDefault;
      ref.read(selectorIntensityProvider.notifier).state = 128;
      ref.read(selectorColorGroupProvider.notifier).state = initGrouping;
      ref.read(selectorSpacingProvider.notifier).state = initSpacing;
      ref.read(selectorGradientPresetProvider.notifier).state = initPreset;
      ref.read(selectorBreathingProvider.notifier).state = false;
      ref.read(selectorMotionTypeProvider.notifier).state = null;
      ref.read(selectorColorBehaviorProvider.notifier).state = null;
    });
  }

  /// The seven selector providers, read into one value.
  SelectorState _readSelectorState() => SelectorState(
        effectId: ref.read(selectorEffectIdProvider),
        speed: ref.read(selectorSpeedProvider),
        intensity: ref.read(selectorIntensityProvider),
        grouping: ref.read(selectorColorGroupProvider),
        spacing: ref.read(selectorSpacingProvider),
        colors: _paletteColsRgbw(),
        brightness: widget.editingDesign?.brightness ?? 255,
      );

  /// Write a [SelectorState] into the seven providers. Never pushes to the
  /// controller — see the note at the seed call site.
  void _writeSelectorState(SelectorState s) {
    ref.read(selectorEffectIdProvider.notifier).state = s.effectId;
    ref.read(selectorSpeedProvider.notifier).state = s.speed;
    ref.read(selectorIntensityProvider.notifier).state = s.intensity;
    ref.read(selectorColorGroupProvider.notifier).state = s.grouping;
    ref.read(selectorSpacingProvider.notifier).state = s.spacing;
    // Gradient-only inputs: reset rather than derived. A stored design is
    // never a brightness gradient (see `forDesign`), so leaving a previous
    // palette's values in place would be stale state, not preserved state.
    ref.read(selectorGradientPresetProvider.notifier).state = 0;
    ref.read(selectorBreathingProvider.notifier).state = false;
    ref.read(selectorMotionTypeProvider.notifier).state = null;
    ref.read(selectorColorBehaviorProvider.notifier).state = null;
  }

  /// Seed from the design's OWN channel fields rather than from
  /// `design.toWledPayload()`.
  ///
  /// Both describe the same design, but `toWledPayload` substitutes fx 83 for
  /// a multi-colour Solid (design_models.dart:246-249). Seeding through it
  /// would show fx 83 in the picker and then WRITE 83 back on save, silently
  /// rewriting a stored `fx: 0`. The channel is the stored truth; the payload
  /// is a rendering of it.
  void _seedFromDesign(CustomDesign design) {
    final ch = design.channels.where((c) => c.included).firstOrNull;
    _writeSelectorState(SelectorState(
      effectId: ch?.effectId ?? 0,
      speed: ch?.speed ?? 128,
      intensity: ch?.intensity ?? 128,
      colors: _paletteColsRgbw(),
      brightness: design.brightness,
    ));
  }

  /// Restore the shared providers to their pre-entry values. Idempotent.
  ///
  /// NOTE ON SCOPE: this restores APP state only. It deliberately does not
  /// re-push the pre-edit look to the controller, unlike selection mode's
  /// `_restoreCapturedLook`. The house keeps whatever the live preview last
  /// showed until the user deliberately applies something. That asymmetry is
  /// intentional and is called out in audit/DESIGN_CARD_P4.md — aligning the
  /// two is a one-line change if the preview-should-be-undone reading wins.
  void _restoreProviderSnapshot() {
    final snap = _providerSnapshot;
    if (snap == null || _snapshotRestored) return;
    _snapshotRestored = true;
    _writeSelectorState(snap);
  }

  /// The palette's colours as RGBW `col` entries — the same derivation the
  /// preview and commit paths use.
  List<List<int>> _paletteColsRgbw() {
    final cols = _paletteColors
        .take(3)
        .map((c) => rgbToRgbw((c.r * 255).round(), (c.g * 255).round(),
            (c.b * 255).round(), forceZeroWhite: true))
        .toList();
    if (cols.isEmpty) cols.add(rgbToRgbw(255, 255, 255));
    return cols;
  }

  /// FOURTH EXIT — design-edit only. Writes the tuner's current state back to
  /// the design it was opened on, through the same `updateDesign` every other
  /// design writer uses, carrying the ORIGINAL id so `saveDesign` routes to
  /// update and never to create.
  ///
  /// Only fx / speed / intensity / brightness are written. Colours are not:
  /// the tuner has no colour editor, it renders whatever the node supplies.
  /// `grp` / `spc` are not written either — see the report; `ChannelDesign`
  /// has no field for them.
  Future<void> _saveToDesign() async {
    final design = widget.editingDesign;
    if (design == null) return;
    final state = _readSelectorState();
    final updated = design.copyWith(
      channels: [
        for (final ch in design.channels)
          ch.included
              ? ch.copyWith(
                  effectId: state.effectId,
                  speed: state.speed,
                  intensity: state.intensity,
                )
              : ch,
      ],
      updatedAt: DateTime.now(),
    );
    final ok = await ref.read(updateDesignProvider)(updated);
    _restoreProviderSnapshot();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Saved "${design.name}"' : 'Save failed'),
    ));
    if (ok) Navigator.of(context).maybePop(true);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    // CANCEL exit (selection mode): if a pre-preview look was captured and NOT
    // yet consumed by a Save, the user is backing out of the effect editor
    // (the parent LibraryBrowserScreen owns the back button, so its pop
    // disposes us) — restore the device now. Fire-and-forget and ref-free:
    // [_restoreCapturedLook] uses only the cached repo/payload (dispose cannot
    // touch `ref`). A failed write is benign — the next apply self-corrects.
    if (_capturedLook != null) {
      _restoreCapturedLook();
    }
    // DESIGN-EDIT cancel: put the shared selector providers back. Safe from
    // dispose because it only writes to Riverpod-owned notifiers, which
    // outlive this widget — the same reasoning LibraryBrowserScreen.dispose
    // uses for the mood filter.
    _restoreProviderSnapshot();
    super.dispose();
  }

  /// Snapshot everything the restore write needs while `ref` is live: the
  /// repository, the demo-mode flag, and the fully channel-filtered restore
  /// payload built from [_capturedLook]. Called on entry and refreshed on each
  /// build so the CANCEL path (dispose, where `ref` is forbidden) has a current
  /// cache. No-op outside selection mode / once the look is consumed.
  void _refreshRestoreCache() {
    final look = _capturedLook;
    if (look == null) return;
    _restoreDemoMode = ref.read(demoModeProvider);
    _restoreRepo = ref.read(wledRepositoryProvider);
    final channels = ref.read(effectiveChannelIdsProvider);
    if (channels.isEmpty) {
      _restorePayload = null; // U1 gate not satisfied yet — nothing to send
      return;
    }
    _restorePayload = applyChannelFilter(
      _buildLookPayload(look),
      channels,
      ref.read(deviceChannelsProvider),
    );
  }

  /// Build the raw (pre channel-filter) WLED payload that reproduces [look] —
  /// the app-expressible restore of the pre-preview state. Palette is restored
  /// verbatim (not effect-derived) so the prior look round-trips as closely as
  /// the app holds.
  Map<String, dynamic> _buildLookPayload(WledStateModel look) {
    final List<List<int>> cols = look.colorSequence.isNotEmpty
        ? look.colorSequence
            .take(3)
            .map((c) => rgbToRgbw((c.r * 255).round(), (c.g * 255).round(),
                (c.b * 255).round(), forceZeroWhite: true))
            .toList()
        : [
            rgbToRgbw((look.color.r * 255).round(), (look.color.g * 255).round(),
                (look.color.b * 255).round(), forceZeroWhite: true)
          ];
    return <String, dynamic>{
      'on': look.isOn,
      'bri': look.brightness,
      'seg': [
        {
          'fx': look.effectId,
          'sx': look.speed,
          'ix': look.intensity,
          'pal': look.paletteId,
          'grp': look.colorGroupSize,
          'spc': look.spacing,
          'col': cols,
        }
      ],
    };
  }

  /// Restore the pre-preview device look captured on entry ([_capturedLook]),
  /// undoing the live preview. Uses ONLY the cached repo/payload (never `ref`),
  /// so it is safe to fire from [dispose]. Same mechanism as the preview —
  /// [WledRepository.applyJson] through the channel-filter chokepoint — NOT a
  /// config/preset write.
  ///
  /// Returns true only when the restore write actually succeeds. On failure
  /// (off-LAN, dropped, U1 gate) it does NOT clear [_capturedLook] and does NOT
  /// report success, leaving the snapshot in place so the next [_sendToWled] or
  /// manual apply corrects the device (per the locked no-cross-death-persistence
  /// decision — leftover preview is a benign, self-correcting state).
  Future<bool> _restoreCapturedLook() async {
    if (_capturedLook == null) return true; // nothing to restore / consumed
    if (_restoreDemoMode) {
      _capturedLook = null; // demo: no device, nothing to undo
      return true;
    }
    final repo = _restoreRepo;
    final payload = _restorePayload;
    if (repo == null || payload == null) {
      return false; // no device / U1 gate — keep snapshot for a later retry
    }
    try {
      final ok = await repo.applyJson(payload);
      if (ok) _capturedLook = null; // consumed — never restore twice
      return ok;
    } catch (e) {
      debugPrint('Selection-mode restore failed (device offline?): $e');
      return false; // keep snapshot; next apply self-corrects
    }
  }

  /// Whether this palette node carries architectural spacing metadata.
  bool get _isArchitectural =>
      widget.paletteNode.metadata?['grouping'] != null &&
      widget.paletteNode.metadata?['spacing'] != null;

  /// Whether this palette node is a brightness gradient pattern.
  bool get _isBrightnessGradient =>
      widget.paletteNode.metadata?['type'] == 'brightness_gradient';

  /// Compute gradient colors from the base (100%) color and preset steps.
  List<Color> _gradientColorsForPreset(int presetIndex) {
    final presets = PatternRepository.brightnessGradientPresets;
    final preset = presets[presetIndex.clamp(0, presets.length - 1)];
    final baseColor = widget.paletteNode.themeColors!.first;
    final r = (baseColor.r * 255).round();
    final g = (baseColor.g * 255).round();
    final b = (baseColor.b * 255).round();
    return preset.steps
        .map((pct) => Color.fromARGB(
              255,
              (r * pct).round().clamp(0, 255),
              (g * pct).round().clamp(0, 255),
              (b * pct).round().clamp(0, 255),
            ))
        .toList();
  }

  /// Returns the effective WLED effect ID. When effect 0 (Solid) is selected
  /// with multiple palette colors, substitutes effect 83 (Solid Pattern)
  /// which distributes colors in repeating blocks using `grp`.
  /// Architectural patterns keep effect 0 — their spacing comes from grp/spc,
  /// not from multi-color distribution.
  int _effectiveEffectId(int selectedId) {
    if (selectedId == 0 && _paletteColors.length > 1 && !_isArchitectural) return 83;
    return selectedId;
  }

  void _sendToWled() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
      final demoMode = ref.read(demoModeProvider);
      if (demoMode) return;

      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return;

      final colorGroup = ref.read(selectorColorGroupProvider);
      final spacing = ref.read(selectorSpacingProvider);

      // For brightness gradients, derive colors and effect from gradient state
      final List<List<int>> cols;
      final int fxId;
      final int speed;
      if (_isBrightnessGradient) {
        final presetIdx = ref.read(selectorGradientPresetProvider);
        final breathing = ref.read(selectorBreathingProvider);
        final gradColors = _gradientColorsForPreset(presetIdx);
        cols = PatternRepository.colorsToWledCol(gradColors);
        fxId = breathing ? 2 : 83;
        speed = breathing ? 100 : 0;
      } else {
        final effectId = ref.read(selectorEffectIdProvider);
        cols = _paletteColors
            .take(3)
            .map((c) => rgbToRgbw((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), forceZeroWhite: true))
            .toList();
        if (cols.isEmpty) cols.add(rgbToRgbw(255, 255, 255));
        fxId = _effectiveEffectId(effectId);
        speed = ref.read(selectorSpeedProvider);
      }

      // ONE builder for every exit (selector_payload.dart). `pal` is derived
      // from the effect's colour behaviour there, not hardcoded — palette-
      // driven effects sweep a gradient of the USER's colours (pal 4);
      // col-based effects keep them discrete (pal 5).
      var payload = buildSelectorPayload(SelectorState(
        effectId: fxId,
        speed: speed,
        intensity: ref.read(selectorIntensityProvider),
        grouping: colorGroup,
        spacing: spacing,
        colors: cols,
      ));

      // Apply channel filter so all targeted segments receive the change
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isEmpty) {
        debugPrint('ColorwayEffectSelector preview apply: skip (U1 gate)');
        return;
      }
      payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));

      await repo.applyJson(payload);
    });
  }

  Future<void> _applyPattern() async {
    final colorGroup = ref.read(selectorColorGroupProvider);
    final spacing = ref.read(selectorSpacingProvider);
    final intensity = ref.read(selectorIntensityProvider);

    // Resolve effect, speed, and colors depending on pattern type
    final int fxId;
    final int speed;
    final List<Color> previewColors;
    final String effectName;
    if (_isBrightnessGradient) {
      final breathing = ref.read(selectorBreathingProvider);
      final presetIdx = ref.read(selectorGradientPresetProvider);
      previewColors = _gradientColorsForPreset(presetIdx);
      fxId = breathing ? 2 : 83;
      speed = breathing ? 100 : 0;
      effectName = breathing ? 'Breathing' : 'Static';
    } else {
      final effectId = ref.read(selectorEffectIdProvider);
      previewColors = _paletteColors;
      fxId = _effectiveEffectId(effectId);
      speed = ref.read(selectorSpeedProvider);
      effectName = WledEffectsCatalog.getName(effectId);
    }

    final currentState = ref.read(wledStateProvider);
    bool appliedToDevice = false;

    // Try to send to device
    final repo = ref.read(wledRepositoryProvider);
    if (repo != null) {
      final List<List<int>> cols;
      if (_isBrightnessGradient) {
        cols = PatternRepository.colorsToWledCol(previewColors);
      } else {
        final raw = previewColors
            .take(3)
            .map((c) => rgbToRgbw((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), forceZeroWhite: true))
            .toList();
        if (raw.isEmpty) raw.add(rgbToRgbw(255, 255, 255));
        cols = raw;
      }

      // Same builder as the preview path and save-to-design, so the payload
      // persisted to Game Day cannot drift from the one previewed.
      var payload = buildSelectorPayload(SelectorState(
        effectId: fxId,
        speed: speed,
        intensity: intensity,
        grouping: colorGroup,
        spacing: spacing,
        colors: cols,
      ));

      // SELECTION MODE (e.g. the schedule picker) — the SAVE exit. The live
      // preview HAS been applying to the lights on each adjustment; committing
      // "Set design" must (1) hand the chosen design's RAW payload back to the
      // caller for the schedule to store, and (2) RESTORE the pre-preview look
      // — setting a design for a SCHEDULE must not leave it applied now. Do NOT
      // apply the selection to the lights and do NOT persist to Game Day.
      // Returned shape mirrors the legacy _PatternPickerSheet's PatternSelection.
      if (widget.onDesignSelected != null) {
        final selection = LibraryDesignSelection(
          id: widget.paletteNode.id,
          name: '${widget.paletteNode.name} - $effectName',
          wledPayload: payload,
        );
        // Undo the preview via the same applyJson mechanism (see
        // _restoreCapturedLook). Await so the restore write lands before the
        // callback tears down the picker stack. A failed restore is benign and
        // self-correcting — it must NOT lose the user's selection, so we hand
        // back the design regardless.
        await _restoreCapturedLook();
        if (!mounted) return;
        widget.onDesignSelected!(selection);
        return;
      }

      // Apply channel filter so all targeted segments receive the pattern
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isEmpty) {
        debugPrint('ColorwayEffectSelector apply: skip (U1 gate)');
        return;
      }
      payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));

      try {
        await repo.applyJson(payload);
        appliedToDevice = currentState.connected;
      } catch (e) {
        debugPrint('Pattern apply failed (device offline?): $e');
      }

      // Game Day persistence — when teamSlug is set, this selector is
      // operating as a Game Day design picker, so persist the choice
      // to the team's GameDayAutopilotConfig via the existing
      // saveDesign provider method. The displayed design name matches
      // the local-preview label used below ("<palette> - <effect>") so
      // the Game Day card label is consistent with what the user just
      // saw committed.
      if (widget.teamSlug != null) {
        try {
          final designName = '${widget.paletteNode.name} - $effectName';
          await ref
              .read(gameDayAutopilotNotifierProvider.notifier)
              .saveDesign(
                teamSlug: widget.teamSlug!,
                designName: designName,
                wledPayload: payload,
                effectId: fxId,
                speed: speed,
                intensity: intensity,
                brightness: (payload['bri'] as num?)?.toInt() ?? 200,
              );
        } catch (e, st) {
          // A failed save must LOOK failed — persisting the design IS the
          // point of the Game Day picker's Apply (BUG-GD-PICKER-1 item 4).
          // Surface the error instead of swallowing it, and skip the success
          // snackbar / preview-sync below so the UI never implies the design
          // stuck. Post-fix this path is essentially unreachable (jsonEncode
          // makes the write succeed); it now fires only on a genuine Firestore
          // error or a future nested-array regression the sanitizer rejects.
          debugPrint('[GameDayPicker/Colorway] saveDesign failed: $e\n$st');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  "Applied to your lights, but couldn't save this design "
                  'for Game Day. Please try again.',
                ),
                backgroundColor: Colors.red.shade800,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }
    }

    // Always update local preview AND Explore hero from the as-sent payload.
    // Single chokepoint also arms poll-overwrite suppression so the home
    // dashboard preview doesn't snap back to the device's (lossy) echo.
    ref.read(wledStateProvider.notifier).applyPreviewSync(
      colors: previewColors,
      effectId: fxId,
      speed: speed,
      intensity: intensity,
      effectName: '${widget.paletteNode.name} - $effectName',
      colorGroupSize: colorGroup,
      spacing: spacing,
    );

    // Write the Now Playing label so displayPatternNameProvider's Priority 2
    // wins over Priority 3 (the WledStateModel.effectName leak above, which
    // shows "1 On 2 Off - Solid" instead of richer context). The leaf node
    // name alone (e.g. "1 On 2 Off") is uninformative without the parent
    // kelvin/color folder, so compose "<parent>, <leaf>" — e.g.
    // "3500K Soft White, 1 On 2 Off". Item #81 (v1.0.1) replaces this with
    // a structured NowPlayingContext for all Apply paths.
    final parentId = widget.paletteNode.parentId;
    LibraryNode? parentNode;
    if (parentId != null) {
      parentNode = await ref.read(patternRepositoryProvider).getNodeById(parentId);
    }
    final composedLabel = composeColorwayLabel(widget.paletteNode, parentNode);
    ref
        .read(activePresetLabelProvider.notifier)
        .setLabelWithFingerprint(composedLabel, ref.read(wledStateProvider));

    // Show feedback with offline awareness
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appliedToDevice
                ? 'Applied: $effectName'
                : 'Preview: $effectName (device offline)',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: appliedToDevice
              ? NexGenPalette.gunmetal
              : Colors.orange.shade800,
        ),
      );
    }
    if (appliedToDevice) maybeShowManualApplyOffWarning(ref);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the ref-free restore cache current for the CANCEL (dispose) path.
    if (_capturedLook != null) _refreshRestoreCache();
    final effectId = ref.watch(selectorEffectIdProvider);
    final speed = ref.watch(selectorSpeedProvider);
    final intensity = ref.watch(selectorIntensityProvider);
    final colorGroup = ref.watch(selectorColorGroupProvider);
    final motionFilter = ref.watch(selectorMotionTypeProvider);
    final colorFilter = ref.watch(selectorColorBehaviorProvider);

    // For brightness gradient patterns, derive preview colors from the active preset
    final gradientPresetIdx = ref.watch(selectorGradientPresetProvider);
    final breathing = ref.watch(selectorBreathingProvider);
    final gradientPreviewColors = _isBrightnessGradient
        ? _gradientColorsForPreset(gradientPresetIdx)
        : _paletteColors;
    final gradientPreviewFx = _isBrightnessGradient
        ? (breathing ? 2 : 83)
        : effectId;
    final gradientPreviewSpeed = _isBrightnessGradient
        ? (breathing ? 100 : 0)
        : speed;

    final effect = WledEffectsCatalog.getById(effectId);
    final hasMultipleColors = _paletteColors.length > 1;
    final showColorLayout = !_isBrightnessGradient &&
        ((effect?.usesColorLayout ?? false) || (effectId == 0 && hasMultipleColors));

    // Build filtered effect list (only used for non-gradient patterns)
    final bool showingTopPicks = motionFilter == null && colorFilter == null;
    final List<WledEffect> displayEffects = showingTopPicks
        ? WledEffectsCatalog.topPicks
        : WledEffectsCatalog.filterEffects(
            motionType: motionFilter,
            colorBehavior: colorFilter,
          );

    return CustomScrollView(
      slivers: [
        // Channel/Area selector
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ChannelSelectorBar(),
          ),
        ),

        // Apply button row
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Color palette preview
                Expanded(
                  child: Row(
                    children: [
                      for (final color in gradientPreviewColors.take(3))
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: NexGenPalette.line),
                          ),
                        ),
                    ],
                  ),
                ),
                // Open in full pattern editor (not applicable for gradients)
                if (!_isBrightnessGradient)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      onPressed: () {
                        final effectId = ref.read(selectorEffectIdProvider);
                        final speed = ref.read(selectorSpeedProvider);
                        final intensity = ref.read(selectorIntensityProvider);
                        final pattern = EditablePattern.fromGradientColors(
                          id: widget.paletteNode.id,
                          name: widget.paletteNode.name,
                          colors: _paletteColors,
                          effectId: effectId,
                          speed: speed,
                          intensity: intensity,
                        );
                        context.push(AppRoutes.editPattern, extra: pattern);
                      },
                      icon: const Icon(Icons.tune, size: 22),
                      tooltip: 'Open in Pattern Editor',
                      style: IconButton.styleFrom(
                        foregroundColor: NexGenPalette.textMedium,
                      ),
                    ),
                  ),
                // Commit button. Three modes, one control:
                //   • DESIGN-EDIT → the FOURTH exit, _saveToDesign, writing
                //     back to the design this tuner was opened on. The three
                //     catalog exits are unreachable here because _applyPattern
                //     is not wired in this mode.
                //   • SELECTION → commits the choice back to the caller (the
                //     schedule) and restores the pre-preview look rather than
                //     applying now, so it reads "Set design".
                //   • CATALOG → applies to the lights.
                ElevatedButton.icon(
                  onPressed:
                      widget.isDesignEdit ? _saveToDesign : _applyPattern,
                  icon: Icon(
                      widget.isDesignEdit ? Icons.save_outlined : Icons.check,
                      size: 18),
                  label: Text(widget.isDesignEdit
                      ? 'Save to design'
                      : widget.onDesignSelected != null
                          ? 'Set design'
                          : 'Apply'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: NexGenPalette.matteBlack,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Roofline preview
        SliverToBoxAdapter(child: _buildRooflinePreview(gradientPreviewFx, gradientPreviewSpeed)),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // ---- Brightness Gradient controls ----
        if (_isBrightnessGradient) ...[
          SliverToBoxAdapter(child: _buildGradientPresetSelector(gradientPresetIdx)),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
          SliverToBoxAdapter(child: _buildBandWidthSelector(colorGroup)),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
          SliverToBoxAdapter(child: _buildBreathingToggle(breathing)),
          SliverPadding(padding: EdgeInsets.only(bottom: navBarTotalHeight(context))),
        ],

        // ---- Standard effect controls ----
        if (!_isBrightnessGradient) ...[
          // Color layout selector (conditional)
          // Hidden in DESIGN-EDIT: `grp`/`spc` have no field on ChannelDesign,
          // so a change here could not be saved and `toWledPayload` would
          // re-assert the #88 defaults on the next apply. Offering a control
          // whose value is silently discarded is worse than not offering it.
          // See audit/DESIGN_CARD_P4.md for the model gap this reflects.
          if (showColorLayout && !widget.isDesignEdit)
            SliverToBoxAdapter(child: _buildColorLayoutSelector(colorGroup)),
          if (widget.isDesignEdit)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Editing a saved design: effect, speed and intensity are '
                  'saved back. Colours and pixel layout are not editable here.',
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 11),
                ),
              ),
            ),

          // Speed slider
          SliverToBoxAdapter(
            child: EffectSpeedSlider(
              rawSpeed: speed,
              effectId: effectId,
              onChanged: (raw) {
                ref.read(selectorSpeedProvider.notifier).state = raw;
                _sendToWled();
              },
            ),
          ),

          // Intensity slider
          SliverToBoxAdapter(
            child: _buildSlider(
              label: 'Intensity',
              value: intensity,
              onChanged: (v) {
                ref.read(selectorIntensityProvider.notifier).state = v.round();
                _sendToWled();
              },
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Motion type filter chips
          SliverToBoxAdapter(child: _buildMotionFilterRow(motionFilter)),

          const SliverToBoxAdapter(child: SizedBox(height: 6)),

          // Color behavior filter chips
          SliverToBoxAdapter(child: _buildColorFilterRow(colorFilter)),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    showingTopPicks ? 'TOP PICKS' : '${displayEffects.length} EFFECTS',
                    style: TextStyle(
                      color: NexGenPalette.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  if (!showingTopPicks) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        ref.read(selectorMotionTypeProvider.notifier).state = null;
                        ref.read(selectorColorBehaviorProvider.notifier).state = null;
                      },
                      child: Text(
                        'Clear filters',
                        style: TextStyle(
                          color: NexGenPalette.cyan,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 6)),

          // Effect list
          SliverPadding(
            padding: EdgeInsets.only(left: 16, right: 16, bottom: navBarTotalHeight(context)),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final effect = displayEffects[index];
                  final isSelected = effect.id == effectId;
                  return _buildEffectTile(effect, isSelected);
                },
                childCount: displayEffects.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Brightness Gradient Controls
  // ---------------------------------------------------------------------------

  /// CONTROL 1 — Gradient Preset Selector (horizontal pill chips)
  Widget _buildGradientPresetSelector(int activeIndex) {
    final presets = PatternRepository.brightnessGradientPresets;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Brightness Pattern',
            style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(presets.length, (i) {
              final preset = presets[i];
              final isSelected = i == activeIndex;
              return GestureDetector(
                onTap: () {
                  ref.read(selectorGradientPresetProvider.notifier).state = i;
                  _sendToWled();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? NexGenPalette.cyan.withValues(alpha: 0.2)
                        : NexGenPalette.gunmetal,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    preset.name,
                    style: TextStyle(
                      color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          // LED dot preview showing the brightness gradient pattern
          _buildGradientDotPreview(activeIndex, ref.watch(selectorColorGroupProvider)),
        ],
      ),
    );
  }

  /// Shows a row of LED dots at varying brightness levels for the active preset.
  Widget _buildGradientDotPreview(int presetIndex, int bandWidth) {
    final colors = _gradientColorsForPreset(presetIndex);
    final dots = <Widget>[];
    for (int i = 0; i < 18; i++) {
      final colorIdx = (i ~/ bandWidth) % colors.length;
      dots.add(Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: colors[colorIdx],
          shape: BoxShape.circle,
          border: Border.all(color: NexGenPalette.line, width: 0.5),
        ),
      ));
    }
    return Row(
      children: [
        Text('Pattern:', style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 11)),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: dots),
          ),
        ),
      ],
    );
  }

  /// CONTROL 2 — Band Width Selector (1 LED or 2 LED per brightness step)
  Widget _buildBandWidthSelector(int activeBandWidth) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Text(
            'LEDs per Step',
            style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 12),
          ),
          const Spacer(),
          for (final bw in [1, 2]) ...[
            if (bw == 2) const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                ref.read(selectorColorGroupProvider.notifier).state = bw;
                _sendToWled();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: activeBandWidth == bw
                      ? NexGenPalette.cyan.withValues(alpha: 0.2)
                      : NexGenPalette.gunmetal,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: activeBandWidth == bw ? NexGenPalette.cyan : NexGenPalette.line,
                    width: activeBandWidth == bw ? 2 : 1,
                  ),
                ),
                child: Text(
                  '$bw LED',
                  style: TextStyle(
                    color: activeBandWidth == bw ? NexGenPalette.cyan : NexGenPalette.textMedium,
                    fontSize: 13,
                    fontWeight: activeBandWidth == bw ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// CONTROL 3 — Breathing Toggle
  Widget _buildBreathingToggle(bool isBreathing) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Text(
            'Breathing',
            style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 13),
          ),
          const Spacer(),
          Switch(
            value: isBreathing,
            onChanged: (v) {
              ref.read(selectorBreathingProvider.notifier).state = v;
              _sendToWled();
            },
            activeThumbColor: NexGenPalette.cyan,
            activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.3),
            inactiveThumbColor: NexGenPalette.textSecondary,
            inactiveTrackColor: NexGenPalette.gunmetal,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Roofline Preview
  // ---------------------------------------------------------------------------

  Widget _buildRooflinePreview(int effectId, int speed) {
    final houseImageUrl = ref.watch(currentUserProfileProvider).maybeWhen(
      data: (u) => u?.housePhotoUrl,
      orElse: () => null,
    );
    final hasCustomImage = houseImageUrl != null && houseImageUrl.isNotEmpty;

    return Container(
      height: 140,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexGenPalette.line),
        color: NexGenPalette.matteBlack,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // House image
            if (hasCustomImage)
              Image.network(houseImageUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/images/Demohomephoto.jpg', fit: BoxFit.cover,
                ),
              )
            else
              Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover),

            // Gradient overlay for legibility
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Animated roofline overlay with current pattern
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedRooflineOverlay(
                    previewColors: _isBrightnessGradient
                        ? _gradientColorsForPreset(ref.watch(selectorGradientPresetProvider))
                        : _paletteColors,
                    previewEffectId: effectId,
                    previewSpeed: speed,
                    forceOn: true,
                    targetAspectRatio: constraints.maxWidth / constraints.maxHeight,
                    useBoxFitCover: true,
                    colorGroupSize: ref.watch(selectorColorGroupProvider),
                    spacing: ref.watch(selectorSpacingProvider),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filter Chip Rows
  // ---------------------------------------------------------------------------

  Widget _buildMotionFilterRow(MotionType? selected) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildFilterChip(
            label: 'All',
            icon: '⭐',
            isSelected: selected == null,
            onTap: () => ref.read(selectorMotionTypeProvider.notifier).state = null,
          ),
          for (final type in MotionType.values) ...[
            const SizedBox(width: 6),
            _buildFilterChip(
              label: type.displayName,
              icon: type.icon,
              isSelected: selected == type,
              onTap: () => ref.read(selectorMotionTypeProvider.notifier).state =
                  selected == type ? null : type,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColorFilterRow(ColorBehavior? selected) {
    // Simplified color behavior options - merge usesSelected + blends into "My Colors"
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildFilterChip(
            label: 'Any Color',
            isSelected: selected == null,
            onTap: () => ref.read(selectorColorBehaviorProvider.notifier).state = null,
            subtle: true,
          ),
          const SizedBox(width: 6),
          _buildFilterChip(
            label: 'My Colors',
            isSelected: selected == ColorBehavior.usesSelectedColors,
            onTap: () => ref.read(selectorColorBehaviorProvider.notifier).state =
                selected == ColorBehavior.usesSelectedColors ? null : ColorBehavior.usesSelectedColors,
            subtle: true,
          ),
          const SizedBox(width: 6),
          _buildFilterChip(
            label: 'Blended',
            isSelected: selected == ColorBehavior.blendsSelectedColors,
            onTap: () => ref.read(selectorColorBehaviorProvider.notifier).state =
                selected == ColorBehavior.blendsSelectedColors ? null : ColorBehavior.blendsSelectedColors,
            subtle: true,
          ),
          const SizedBox(width: 6),
          _buildFilterChip(
            label: 'Auto Colors',
            isSelected: selected == ColorBehavior.generatesOwnColors,
            onTap: () => ref.read(selectorColorBehaviorProvider.notifier).state =
                selected == ColorBehavior.generatesOwnColors ? null : ColorBehavior.generatesOwnColors,
            subtle: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    String? icon,
    required bool isSelected,
    required VoidCallback onTap,
    bool subtle = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (subtle ? NexGenPalette.cyan.withValues(alpha: 0.15) : NexGenPalette.cyan.withValues(alpha: 0.2))
              : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Text(icon, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectTile(WledEffect effect, bool isSelected) {
    // Color behavior badge text
    final badgeText = effect.colorBehavior.shortName;
    final badgeColor = switch (effect.colorBehavior) {
      ColorBehavior.usesSelectedColors => NexGenPalette.cyan,
      ColorBehavior.blendsSelectedColors => Colors.purpleAccent,
      ColorBehavior.generatesOwnColors => Colors.orange,
      ColorBehavior.usesPalette => Colors.tealAccent,
    };

    return InkWell(
      onTap: () {
        ref.read(selectorEffectIdProvider.notifier).state = effect.id;
        // Reset speed to this effect's profile default for best experience
        ref.read(selectorSpeedProvider.notifier).state =
            getSpeedProfile(effect.id).rawDefault;
        _sendToWled();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? NexGenPalette.cyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: NexGenPalette.cyan, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            // Mini preview
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: EffectPreviewWidget(
                  effectId: effect.id,
                  colors: _paletteColors,
                  borderRadius: 8,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Effect name + color behavior badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    effect.name,
                    style: TextStyle(
                      color: isSelected
                          ? NexGenPalette.cyan
                          : NexGenPalette.textHigh,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor.withValues(alpha: 0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Checkmark if selected
            if (isSelected)
              Icon(
                Icons.check,
                color: NexGenPalette.cyan,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Color Layout & Sliders (unchanged)
  // ---------------------------------------------------------------------------

  Widget _buildColorLayoutSelector(int colorGroup) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LEDs per color',
            style: TextStyle(
              color: NexGenPalette.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (i) {
              final value = i + 1;
              final isSelected = colorGroup == value;
              return GestureDetector(
                onTap: () {
                  ref.read(selectorColorGroupProvider.notifier).state = value;
                  _sendToWled();
                },
                child: Container(
                  width: 48,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? NexGenPalette.cyan.withValues(alpha: 0.2)
                        : NexGenPalette.gunmetal,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? NexGenPalette.cyan
                          : NexGenPalette.line,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$value',
                      style: TextStyle(
                        color: isSelected
                            ? NexGenPalette.cyan
                            : NexGenPalette.textMedium,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          _buildColorLayoutPreview(colorGroup),
        ],
      ),
    );
  }

  Widget _buildColorLayoutPreview(int colorGroup) {
    final colors = _paletteColors.take(3).toList();
    if (colors.isEmpty) colors.add(Colors.white);
    final spc = ref.watch(selectorSpacingProvider);
    final cycle = colorGroup + spc;

    final dots = <Widget>[];
    for (int i = 0; i < 18; i++) {
      final bool lit = spc == 0 || cycle == 0 || (i % cycle) < colorGroup;
      final Color dotColor;
      if (lit) {
        final colorIndex = (i ~/ colorGroup) % colors.length;
        dotColor = colors[colorIndex];
      } else {
        dotColor = colors.first.withValues(alpha: 0.10);
      }
      dots.add(Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: NexGenPalette.line,
            width: 0.5,
          ),
        ),
      ));
    }

    return Row(
      children: [
        Text(
          'Pattern:',
          style: TextStyle(
            color: NexGenPalette.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: dots),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required int value,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                color: NexGenPalette.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: NexGenPalette.cyan,
                inactiveTrackColor: NexGenPalette.trackDark,
                thumbColor: NexGenPalette.cyan,
                overlayColor: NexGenPalette.cyan.withValues(alpha: 0.2),
                trackHeight: 4,
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

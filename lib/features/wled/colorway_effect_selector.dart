import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/rainbow_scope.dart';
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
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_design_save.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart'
    show showScheduleEditor, PatternSelection;

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

/// DESIGN-EDIT live preview: [payload] with the brightness of the design being
/// edited instead of the catalog's.
///
/// `buildSelectorPayload` always states `bri`, and the preview never passed
/// one — so opening a stored design in the tuner and touching any control
/// drove the lights to `bri: 255`, whatever the design stores. "Save to design"
/// then kept the stored level (it never writes brightness), leaving the lights
/// showing a look the design would not come back as. The preview now follows
/// [CustomDesign.appliedBrightness], the rule every apply path uses: the stored
/// level when the design states one, otherwise no `bri` at all. Catalog mode
/// ([design] null) is returned untouched.
@visibleForTesting
Map<String, dynamic> designEditPreviewPayload(
  Map<String, dynamic> payload,
  CustomDesign? design,
) {
  if (design == null) return payload;
  final bri = design.appliedBrightness;
  return <String, dynamic>{
    for (final e in payload.entries)
      if (e.key != 'bri') e.key: e.value,
    if (bri != null) 'bri': bri,
  };
}

/// A design chosen from the library in SELECTION mode — returned to the caller
/// (e.g. the schedule "choose a pattern" flow) instead of being applied. Same
/// shape the legacy schedule picker returned (`PatternSelection`): the caller
/// maps it straight into whatever it stores. [wledPayload] is the RAW design
/// payload (pre channel-filter), matching `GradientPattern.toWledPayload()` /
/// `CustomDesign.toWledPayload()` so it round-trips into a ScheduleItem.
class LibraryDesignSelection {
  final String id;

  /// Display name of the choice, "`<palette> - <effect>`".
  final String name;
  final String imageUrl;
  final Map<String, dynamic> wledPayload;

  /// The palette's own name, without the effect suffix. Destinations that
  /// derive the effect from [wledPayload] (Game Day) store THIS, so the label
  /// they show can never disagree with the payload they fire.
  final String? paletteName;

  const LibraryDesignSelection({
    required this.id,
    required this.name,
    required this.wledPayload,
    this.imageUrl = '',
    this.paletteName,
  });

  /// [paletteName] when known, else [name].
  String get baseName => paletteName ?? name;
}

/// Effect selector page that replaces the pattern grid.
/// Shows a large live preview with filter chips and curated effect grid.
class ColorwayEffectSelectorPage extends ConsumerStatefulWidget {
  final LibraryNode paletteNode;

  /// When non-null, this selector is in SAVE mode (the schedule, Game Day and
  /// Favorites pickers): committing RETURNS the chosen design via this
  /// callback for the CALLER to persist, and nothing here writes to the
  /// controller unless the user taps "Preview on lights". Null (the default)
  /// is APPLY mode: the commit button applies to the lights and persists
  /// nothing; a secondary "Save…" offers Favorites / Game Day / schedule.
  ///
  /// The selector itself never persists a design anywhere. The Game Day
  /// `saveDesign` side-channel that once lived here (keyed on a `teamSlug`
  /// parameter, and fired by the SAME button that applied to the lights) is
  /// gone as of 2026-09-25; GameDayDesignPickerScreen supplies the save
  /// through this callback instead.
  final void Function(LibraryDesignSelection selection)? onDesignSelected;

  /// SAVE mode's destination, for the commit button: "Save to Favorites",
  /// "Save to Game Day", "Save to schedule". Null reads "Save".
  final String? saveDestinationLabel;

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

  /// CELEBRATION MODE. When true the effect list is replaced by
  /// [WledEffectsCatalog.celebrationPicks] — the attention-grabbing subset —
  /// and the motion/colour filter chips are hidden, because the whole list is
  /// already one deliberate filter. Everything else (live on-device preview,
  /// speed/intensity, the tile grid) is the SAME widget: the celebration
  /// picker is this page in a narrower mode, not a second grid.
  ///
  /// Pair with [onDesignSelected] — celebration mode always returns the choice
  /// rather than persisting a base design.
  final bool celebrationMode;

  /// CELEBRATION MODE only. Seeds the picker with the choice already stored on
  /// the team's config, so reopening it lands on the current celebration
  /// instead of effect 0 (Solid) — which is not in the curated list, showed a
  /// stray "Static" speed hint, and left nothing selected.
  ///
  /// Null (the default) falls back to the first curated pick. Ignored outside
  /// celebration mode, so the other three modes seed exactly as before.
  final int? initialEffectId;
  final int? initialSpeed;
  final int? initialIntensity;

  const ColorwayEffectSelectorPage({
    super.key,
    required this.paletteNode,
    this.onDesignSelected,
    this.saveDestinationLabel,
    this.editingDesign,
    this.celebrationMode = false,
    this.initialEffectId,
    this.initialSpeed,
    this.initialIntensity,
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

  /// SAVE mode: true once the user tapped "Preview on lights". Until then no
  /// adjustment reaches the controller — choosing a design for a schedule,
  /// Game Day or Favorites must not light the house on its own.
  bool _livePreviewOn = false;

  /// SAVE mode that is not the celebration picker (celebration keeps its
  /// always-live preview and its own "Set celebration" commit).
  bool get _isSaveMode =>
      widget.onDesignSelected != null && !widget.celebrationMode;

  /// SELECTION and DESIGN-EDIT modes. The pre-preview device look, snapshotted
  /// on entry (see [initState]) so the CANCEL exit can RESTORE it. The live
  /// preview writes to the real lights on every adjustment ([_sendToWled]),
  /// and neither mode is an "apply this now" gesture:
  ///
  ///   • SELECTION — choosing a pattern for a SCHEDULE must not leave it
  ///     applied now, so BOTH exits (Save and Cancel) restore.
  ///   • DESIGN-EDIT — backing out of an edit must not leave a half-tuned
  ///     look on the house, so CANCEL restores. SAVE does NOT: the user just
  ///     committed that look, so leaving it lit is the coherent outcome.
  ///     `_saveToDesign` therefore CONSUMES the snapshot without replaying it,
  ///     which is what stops `dispose` from undoing a successful save.
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

  /// The Blocks | Alternating chip, snapshotted with [_providerSnapshot]. It
  /// is not a [SelectorState] field (the layout RESOLVES to fx/pal/sx/ix/grp
  /// before a payload exists), so it rides alongside.
  SolidLayout? _providerSnapshotLayout;
  bool _snapshotRestored = false;

  /// The ten notifiers, captured while `ref` is LIVE.
  ///
  /// `_restoreProviderSnapshot` runs from [dispose], where flutter_riverpod
  /// forbids `ref` — reaching them via `ref.read(p.notifier)` there throws
  /// `Bad state: Cannot use "ref" after the widget was disposed`. (That is the
  /// #84 crash class; `LibraryBrowserScreen.dispose` carries the same note for
  /// the mood filter.) The StateControllers themselves are owned by the
  /// ProviderContainer and outlive this widget, so holding them is safe —
  /// it is the `ref` lookup that is not.
  List<StateController<Object?>>? _selectorNotifiers;

  void _captureSelectorNotifiers() {
    _selectorNotifiers = <StateController<Object?>>[
      ref.read(selectorEffectIdProvider.notifier),
      ref.read(selectorSpeedProvider.notifier),
      ref.read(selectorIntensityProvider.notifier),
      ref.read(selectorColorGroupProvider.notifier),
      ref.read(selectorSpacingProvider.notifier),
      ref.read(selectorGradientPresetProvider.notifier),
      ref.read(selectorBreathingProvider.notifier),
      ref.read(selectorMotionTypeProvider.notifier),
      ref.read(selectorColorBehaviorProvider.notifier),
      ref.read(selectorSolidLayoutProvider.notifier),
    ];
  }

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
    if (widget.onDesignSelected != null || widget.isDesignEdit) {
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
      _captureSelectorNotifiers();
      _providerSnapshot = _readSelectorState();
      _providerSnapshotLayout = ref.read(selectorSolidLayoutProvider);
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
      // CELEBRATION seeds from the stored choice (or the first curated pick);
      // every other mode keeps the historical effect-0 seed byte-for-byte.
      // Otherwise seed from the caller's stored choice when it has one (the
      // Game Day picker passes the plan's current effect, so the editor opens
      // on what the card shows), else the historical effect-0 seed.
      final seedFx = widget.celebrationMode
          ? _celebrationSeedEffectId()
          : (widget.initialEffectId ?? 0);
      ref.read(selectorEffectIdProvider.notifier).state = seedFx;
      ref.read(selectorSpeedProvider.notifier).state =
          widget.initialSpeed ?? getSpeedProfile(seedFx).rawDefault;
      ref.read(selectorIntensityProvider.notifier).state =
          widget.initialIntensity ?? 128;
      ref.read(selectorColorGroupProvider.notifier).state = initGrouping;
      ref.read(selectorSpacingProvider.notifier).state = initSpacing;
      ref.read(selectorGradientPresetProvider.notifier).state = initPreset;
      ref.read(selectorBreathingProvider.notifier).state = false;
      ref.read(selectorMotionTypeProvider.notifier).state = null;
      ref.read(selectorColorBehaviorProvider.notifier).state = null;
      // Seeded like the nine above. It used to be the one provider left
      // alone here, so a catalog card opened on whatever chip the last visit
      // (or the last design edit) had left.
      ref.read(selectorSolidLayoutProvider.notifier).state = SolidLayout.blocks;
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

  /// Write a [SelectorState] and the Solid [layout] into the ten providers.
  /// Never pushes to the controller — see the note at the seed call site.
  void _writeSelectorState(SelectorState s, {required SolidLayout layout}) {
    // Through the CAPTURED notifiers — never `ref` — because this also runs
    // from dispose. See [_selectorNotifiers].
    final n = _selectorNotifiers;
    if (n == null) return;
    n[0].state = s.effectId;
    n[1].state = s.speed;
    n[2].state = s.intensity;
    n[3].state = s.grouping;
    n[4].state = s.spacing;
    // Gradient-only inputs: reset rather than derived. A stored design is
    // never a brightness gradient (see `forDesign`), so leaving a previous
    // palette's values in place would be stale state, not preserved state.
    n[5].state = 0;
    n[6].state = false;
    n[7].state = null;
    n[8].state = null;
    n[9].state = layout;
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
    _writeSelectorState(
      SelectorState(
        effectId: ch?.effectId ?? 0,
        speed: ch?.speed ?? 128,
        intensity: ch?.intensity ?? 128,
        // Were not passed at all → the tuner opened every design at grp 1 /
        // spc 0 whatever it had been saved with (followup N3b).
        grouping: ch?.grouping ?? kDesignDefaultGrp,
        spacing: ch?.spacing ?? kDesignDefaultSpc,
        colors: _paletteColsRgbw(),
        brightness: design.brightness,
      ),
      // The chip used to be left wherever the previous visit put it, which
      // had nothing to do with what this design fires as.
      layout: ch?.solidLayout ?? SolidLayout.blocks,
    );
  }

  /// Restore the shared providers to their pre-entry values. Idempotent.
  ///
  /// SCOPE: app state only. The DEVICE is restored separately by
  /// [_restoreCapturedLook], which design-edit now shares with selection mode
  /// — cancelling an edit undoes its live preview on the house, not just in
  /// the picker. (Phase C shipped these asymmetric; closeout aligned them.)
  void _restoreProviderSnapshot() {
    final snap = _providerSnapshot;
    if (snap == null || _snapshotRestored) return;
    _snapshotRestored = true;
    // DEFERRED past the current frame. Two separate rules bite here and the
    // microtask is what satisfies both:
    //   1. `ref` is dead in dispose — handled by [_selectorNotifiers], which
    //      the microtask body uses instead (it must NOT touch `ref`).
    //   2. Riverpod forbids MUTATING a provider from a lifecycle callback at
    //      all ("Tried to modify a provider while the widget tree was
    //      building"), because its listeners would rebuild mid-teardown.
    // Same shape as LibraryBrowserScreen.dispose's mood-filter reset, for the
    // same two reasons.
    Future.microtask(() {
      // Best-effort. If the whole ProviderContainer was torn down between
      // dispose and this microtask (app shutdown, or a test scope ending),
      // the StateControllers are disposed and writing throws
      // `Bad state: Tried to use StateController after dispose was called`.
      // There is nothing left to restore in that case, so swallow it rather
      // than surface an unhandled error from a teardown path.
      try {
        _writeSelectorState(snap,
            layout: _providerSnapshotLayout ?? SolidLayout.blocks);
      } catch (e) {
        debugPrint('Selector snapshot restore skipped (container gone): $e');
      }
    });
  }

  /// The `pal` the as-sent payload carries on its first design seg (the #67
  /// exclusion segs have no `fx`), for the dashboard hero's local preview.
  static int? _wirePal(Map<String, dynamic> payload) {
    final segs = payload['seg'];
    if (segs is! List) return null;
    for (final s in segs) {
      if (s is Map && s.containsKey('fx')) {
        final pal = s['pal'];
        return pal is num ? pal.toInt() : null;
      }
    }
    return null;
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
  /// fx / speed / intensity, the spacing (`grp` / `spc`) and — when Solid is
  /// being substituted for this palette — the Blocks | Alternating layout are
  /// written. Colours are not: the tuner has no colour editor, it renders
  /// whatever the node supplies. (`grp` / `spc` used to be dropped here
  /// because `ChannelDesign` had no field for them; the layout was dropped
  /// for the same reason, so a design saved as Alternating fired as Blocks.)
  Future<void> _saveToDesign() async {
    final design = widget.editingDesign;
    if (design == null) return;
    final state = _readSelectorState();
    // Only when the chip is live for this design; otherwise keep what the
    // channel stores rather than stamping an unrelated effect with the chip's
    // current (irrelevant) value.
    final layout = _activeSolidFields() != null
        ? ref.read(selectorSolidLayoutProvider)
        : null;
    final updated = design.copyWith(
      channels: [
        for (final ch in design.channels)
          ch.included
              ? ch.copyWith(
                  effectId: state.effectId,
                  speed: state.speed,
                  intensity: state.intensity,
                  grouping: state.grouping,
                  spacing: state.spacing,
                  solidLayout: layout,
                )
              : ch,
      ],
      updatedAt: DateTime.now(),
    );
    final ok = await ref.read(updateDesignProvider)(updated);
    // CONSUME the captured look without replaying it: the design now stores
    // what the lights are showing, so undoing the preview would contradict the
    // save the user just made. Clearing it is also what stops dispose's cancel
    // path from firing a restore behind a successful save.
    if (ok) _capturedLook = null;
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
    // CANCEL exit (selection AND design-edit): if a pre-preview look was
    // captured and NOT yet consumed, the user is backing out of the editor
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
    if (_isSaveMode && !_livePreviewOn) {
      // No preview ever reached the lights: nothing to undo, and a restore
      // write would itself be a controller command a Save must not issue.
      _capturedLook = null;
      return true;
    }
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

  /// Whether this node lives under the Rainbow root. Only then are rainbow-
  /// family effects offered, and only then do they go out with `pal:0` so
  /// the firmware's hue wheel renders the full spectrum (rainbow_scope.dart).
  bool get _isRainbowPalette => isRainbowLibraryNode(widget.paletteNode);

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
    // ONE rule, shared with the previews (solid_palette_blocks.dart), so the
    // tile and the dot row can never disagree with what this sends.
    return _solidFieldsFor(selectedId)?.fx ?? selectedId;
  }

  /// The Solid-layout wire fields for [selectedId], or null when Solid is not
  /// being substituted (one colour, architectural node, or not Solid at all).
  /// Blocks → fx 83 + pal:5; Alternating → fx 84 (3 colours) or fx 83 + pal:0
  /// (2 colours), bands of `selectorColorGroupProvider` LEDs via grp.
  SolidLayoutFields? _solidFieldsFor(int selectedId) {
    if (!isSolidPaletteSubstitution(
      effectId: selectedId,
      colorCount: _paletteColors.length,
      isArchitectural: _isArchitectural,
    )) {
      return null;
    }
    return solidLayoutFields(
      layout: ref.read(selectorSolidLayoutProvider),
      colorCount: _paletteColors.length,
      ledsPerColor: ref.read(selectorColorGroupProvider),
    );
  }

  /// The fields for the CURRENTLY selected effect, or null (also null for
  /// brightness gradients, which resolve fx 83 on their own path).
  SolidLayoutFields? _activeSolidFields() {
    if (_isBrightnessGradient) return null;
    return _solidFieldsFor(ref.read(selectorEffectIdProvider));
  }

  void _sendToWled() {
    // SAVE mode: the lights are untouched until "Preview on lights".
    if (_isSaveMode && !_livePreviewOn) return;
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
      // Solid layout (Blocks/Alternating) may pin sx/ix/grp/pal; a Rainbow-
      // folder card pins pal:0 for rainbow-family effects. Both are explicit,
      // deliberate exceptions to the derived-palette rule — see SelectorState.
      final solid = _activeSolidFields();
      var payload = buildSelectorPayload(SelectorState(
        effectId: fxId,
        speed: solid?.sx ?? speed,
        intensity: solid?.ix ?? ref.read(selectorIntensityProvider),
        grouping: solid?.grp ?? colorGroup,
        spacing: spacing,
        colors: cols,
        paletteOverride: solid?.pal ??
            rainbowPaletteOverride(
                effectId: fxId, rainbowScope: _isRainbowPalette),
      ));

      payload = designEditPreviewPayload(payload, widget.editingDesign);

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

  /// Everything a commit needs, from the SAME builder the live preview uses
  /// ([_sendToWled]), so what was previewed is what gets applied, saved or
  /// handed back — and so a Save never needs a device to build its payload.
  _Commit _buildCommit() {
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

    // Same overrides as the preview path, so what was previewed is what
    // gets committed (and what a saved design round-trips back to).
    final solid = _activeSolidFields();
    final payload = buildSelectorPayload(SelectorState(
      effectId: fxId,
      speed: solid?.sx ?? speed,
      intensity: solid?.ix ?? intensity,
      grouping: solid?.grp ?? colorGroup,
      spacing: spacing,
      colors: cols,
      paletteOverride: solid?.pal ??
          rainbowPaletteOverride(
              effectId: fxId, rainbowScope: _isRainbowPalette),
    ));
    return _Commit(
      payload: payload,
      fxId: fxId,
      speed: speed,
      intensity: intensity,
      colorGroup: colorGroup,
      spacing: spacing,
      effectName: effectName,
      previewColors: previewColors,
      pal: _wirePal(payload),
    );
  }

  /// The commit button. SAVE mode hands the design back (no controller
  /// write of its own); APPLY mode writes it to the lights and persists
  /// nothing.
  Future<void> _applyPattern() async {
    final commit = _buildCommit();
    final fxId = commit.fxId;
    final speed = commit.speed;
    final intensity = commit.intensity;
    final colorGroup = commit.colorGroup;
    final spacing = commit.spacing;
    final previewColors = commit.previewColors;
    final effectName = commit.effectName;
    // The `pal` the as-sent payload carries, for the local preview below.
    final int? sentPal = commit.pal;
    var payload = commit.payload;

    // SAVE mode (schedule / Game Day / Favorites pickers, and celebration).
    // Hand the chosen design's RAW payload back to the caller to persist,
    // and — only if "Preview on lights" was used — RESTORE the pre-preview
    // look, because choosing a design for later must not leave it applied
    // now. Nothing is applied and nothing is persisted here.
    if (widget.onDesignSelected != null) {
      final selection = LibraryDesignSelection(
        id: widget.paletteNode.id,
        name: '${widget.paletteNode.name} - $effectName',
        paletteName: widget.paletteNode.name,
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

    // APPLY mode: write to the lights.
    bool appliedToDevice = false;
    final repo = ref.read(wledRepositoryProvider);
    if (repo != null) {
      // Apply channel filter so all targeted segments receive the pattern
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isEmpty) {
        // P1 (residential path audit §9.1 item 9 / S19). This returned in
        // silence: the user tapped Apply and NOTHING happened — no lights, no
        // preview, no message. The gate closes whenever /json/cfg could not be
        // read with at least one LED bus, which is guaranteed off-LAN
        // (CloudRelayRepository.getConfig returns null) and also happens when
        // the controller has no buses configured yet.
        debugPrint('ColorwayEffectSelector apply: skip (U1 gate)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                "Couldn't read this controller's channels, so there is nothing "
                'to apply to. Connect to your home Wi-Fi and try again, or set '
                'up the controller in System → Hardware.',
              ),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));

      try {
        // P1 (audit §9.1 item 9 / S18): the applyJson RESULT is the truth about
        // whether the lights changed. This used to discard it and report the
        // PREVIOUS poll's `connected` flag instead, so a POST that timed out or
        // came back non-2xx still said "Applied: <effect>".
        appliedToDevice = await repo.applyJson(payload);
        if (!appliedToDevice) {
          debugPrint('Pattern apply: applyJson returned false');
        }
      } catch (e) {
        debugPrint('Pattern apply failed (device offline?): $e');
      }
    }

    // Always update local preview AND Explore hero from the as-sent payload.
    // Single chokepoint also arms poll-overwrite suppression so the home
    // dashboard preview doesn't snap back to the device's (lossy) echo.
    ref.read(wledStateProvider.notifier).applyPreviewSync(
      colors: previewColors,
      effectId: fxId,
      // The as-sent `pal`, so the Home hero draws Blocks / Alternating right
      // away instead of with the previous look's palette until the next poll.
      paletteId: sentPal,
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

  // ── Commit controls ────────────────────────────────────────────────────

  /// The controls under the preview. Three modes:
  ///   • DESIGN-EDIT → "Save to design" (writes back to the stored design).
  ///   • SAVE (onDesignSelected) → "Preview on lights" + "Save to `<dest>`".
  ///     Save hands the design back and never writes to the controller;
  ///     Preview is the ONLY thing here that does.
  ///   • APPLY (Explore) → "Save…" (Favorites / Game Day / schedule, no
  ///     controller write) + "Apply" (controller write, no persistence).
  List<Widget> _commitButtons() {
    final primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: NexGenPalette.cyan,
      foregroundColor: NexGenPalette.matteBlack,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    final secondaryStyle = OutlinedButton.styleFrom(
      foregroundColor: NexGenPalette.cyan,
      side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.5)),
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    if (widget.isDesignEdit) {
      return [
        ElevatedButton.icon(
          key: const ValueKey('save-to-design'),
          onPressed: _saveToDesign,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Save to design'),
          style: primaryStyle,
        ),
      ];
    }
    if (_isSaveMode) {
      final dest = widget.saveDestinationLabel;
      return [
        OutlinedButton.icon(
          key: const ValueKey('preview-on-lights'),
          onPressed: _previewOnLights,
          icon: Icon(
              _livePreviewOn ? Icons.visibility : Icons.visibility_outlined,
              size: 18),
          label: Text(_livePreviewOn ? 'Previewing' : 'Preview on lights'),
          style: secondaryStyle,
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          key: const ValueKey('save-design'),
          onPressed: _applyPattern,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(dest == null ? 'Save' : 'Save to $dest'),
          style: primaryStyle,
        ),
      ];
    }
    return [
      OutlinedButton.icon(
        key: const ValueKey('save-elsewhere'),
        onPressed: _showSaveSheet,
        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
        label: const Text('Save…'),
        style: secondaryStyle,
      ),
      const SizedBox(width: 8),
      ElevatedButton.icon(
        key: const ValueKey('apply-design'),
        onPressed: _applyPattern,
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Apply'),
        style: primaryStyle,
      ),
    ];
  }

  /// SAVE mode's one controller write: turn the live preview on (it then
  /// follows every adjustment, exactly as APPLY mode's preview does) and send
  /// the current look. Save / Cancel restore the captured look afterwards.
  void _previewOnLights() {
    if (!_livePreviewOn) setState(() => _livePreviewOn = true);
    _sendToWled();
    final dest = widget.saveDestinationLabel;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Previewing on your lights — nothing is saved until '
            'you tap ${dest == null ? 'Save' : 'Save to $dest'}.'),
        duration: const Duration(seconds: 2),
        backgroundColor: NexGenPalette.gunmetal,
      ),
    );
  }

  /// APPLY mode's secondary: persist the current design somewhere without
  /// touching the lights.
  Future<void> _showSaveSheet() async {
    final commit = _buildCommit();
    final selection = LibraryDesignSelection(
      id: widget.paletteNode.id,
      name: '${widget.paletteNode.name} - ${commit.effectName}',
      paletteName: widget.paletteNode.name,
      wledPayload: commit.payload,
    );
    final choice = await showModalBottomSheet<_SaveTarget>(
      context: context,
      useRootNavigator: true,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Save "${selection.name}"',
                style: const TextStyle(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ListTile(
              key: const ValueKey('save-target-favorites'),
              leading: const Icon(Icons.star_border_rounded,
                  color: NexGenPalette.cyan),
              title: const Text('Save to Favorites',
                  style: TextStyle(color: NexGenPalette.textHigh)),
              onTap: () => Navigator.of(ctx).pop(_SaveTarget.favorites),
            ),
            ListTile(
              key: const ValueKey('save-target-game-day'),
              leading:
                  const Icon(Icons.stadium_rounded, color: NexGenPalette.cyan),
              title: const Text('Save to Game Day',
                  style: TextStyle(color: NexGenPalette.textHigh)),
              subtitle: const Text('Pick a team',
                  style: TextStyle(color: NexGenPalette.textMedium)),
              onTap: () => Navigator.of(ctx).pop(_SaveTarget.gameDay),
            ),
            ListTile(
              key: const ValueKey('save-target-schedule'),
              leading: const Icon(Icons.schedule_rounded,
                  color: NexGenPalette.cyan),
              title: const Text('Save to schedule',
                  style: TextStyle(color: NexGenPalette.textHigh)),
              subtitle: const Text('Opens a new schedule with this design',
                  style: TextStyle(color: NexGenPalette.textMedium)),
              onTap: () => Navigator.of(ctx).pop(_SaveTarget.schedule),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (choice) {
      case _SaveTarget.favorites:
        try {
          await ref.read(favoritesNotifierProvider.notifier).addToFavorites(
                patternId: favoritePatternIdFor(selection),
                patternName: selection.name,
                wledPayload: selection.wledPayload,
              );
          messenger.showSnackBar(SnackBar(
              content: Text('Saved "${selection.name}" to Favorites')));
        } catch (e) {
          messenger
              .showSnackBar(SnackBar(content: Text('Could not save: $e')));
        }
      case _SaveTarget.gameDay:
        final teamSlug = await _pickGameDayTeam();
        if (teamSlug == null || !mounted) return;
        try {
          await saveGameDayDesignSelection(ref, teamSlug, selection);
          messenger.showSnackBar(SnackBar(
              content: Text('Saved "${selection.name}" to Game Day')));
        } catch (e) {
          messenger
              .showSnackBar(SnackBar(content: Text('Could not save: $e')));
        }
      case _SaveTarget.schedule:
        showScheduleEditor(
          context,
          ref,
          initialPattern: PatternSelection(
            id: selection.id,
            name: selection.name,
            imageUrl: selection.imageUrl,
            wledPayload: selection.wledPayload,
          ),
        );
    }
  }

  Future<String?> _pickGameDayTeam() async {
    final configs =
        ref.read(gameDayAutopilotConfigsProvider).valueOrNull ?? const [];
    if (configs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add a team on the Game Day screen first.')));
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in configs)
              ListTile(
                key: ValueKey('save-target-team-${c.teamSlug}'),
                leading: Icon(Icons.stadium_rounded, color: c.primaryColor),
                title: Text(c.teamName,
                    style: const TextStyle(color: NexGenPalette.textHigh)),
                onTap: () => Navigator.of(ctx).pop(c.teamSlug),
              ),
          ],
        ),
      ),
    );
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

    // Watched here so the effect tiles, the dot row AND the hero rebuild when
    // the Blocks/Alternating toggle changes (the helpers below use ref.read).
    ref.watch(selectorSolidLayoutProvider);

    final effect = WledEffectsCatalog.getById(effectId);
    final hasMultipleColors = _paletteColors.length > 1;
    final showColorLayout = !_isBrightnessGradient &&
        ((effect?.usesColorLayout ?? false) || (effectId == 0 && hasMultipleColors));

    // CELEBRATION MODE takes its own, much smaller render path — see
    // [_buildCelebrationBody]. Returning here rather than threading more
    // `if (celebrationMode)` branches through the sliver list below is what
    // keeps the other three modes' render path literally unchanged.
    if (widget.celebrationMode) {
      return _buildCelebrationBody(effectId, speed, intensity);
    }

    // Build filtered effect list (only used for non-gradient patterns)
    final bool showingTopPicks = motionFilter == null && colorFilter == null;
    // Rainbow-family effects are offered ONLY under the Rainbow root. They
    // used to reach every palette through topPicks (which carried fx 9) and
    // through the unfiltered "All"/"Any Color" list — the Rainbow leak.
    final List<WledEffect> displayEffects = scopeRainbowEffects(
      showingTopPicks
          ? WledEffectsCatalog.topPicks
          : WledEffectsCatalog.filterEffects(
              motionType: motionFilter,
              colorBehavior: colorFilter,
            ),
      rainbowScope: _isRainbowPalette,
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
                // Open in full pattern editor (not applicable for gradients,
                // and not from a SAVE-mode picker: the editor applies live and
                // returns nothing to the destination).
                if (!_isBrightnessGradient && !_isSaveMode)
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
                ..._commitButtons(),
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
          // Color layout selector (conditional). Shown in DESIGN-EDIT too,
          // since 2026-09-22: it was hidden there while `ChannelDesign` had no
          // field for `grp`/`spc` (a change could not be saved), but spacing
          // has persisted since followup N3b and the Blocks | Alternating
          // layout now has its own field — `_saveToDesign` writes all three.
          if (showColorLayout)
            SliverToBoxAdapter(child: _buildColorLayoutSelector(colorGroup)),
          if (widget.isDesignEdit)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Editing a saved design: effect, speed, intensity, spacing '
                  'and layout are saved back. Colours are not editable here.',
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

          // Motion / colour filter chips. Celebration mode never reaches
          // here — it returns its own body above, with no filters at all.
          SliverToBoxAdapter(child: _buildMotionFilterRow(motionFilter)),
          const SliverToBoxAdapter(child: SizedBox(height: 6)),
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

  // ---------------------------------------------------------------------------
  // Celebration mode
  // ---------------------------------------------------------------------------

  /// The effect the celebration picker should open on.
  ///
  /// Prefers the team's stored choice, but only when it is actually in the
  /// curated list — a config written before this list was curated can hold an
  /// id that is no longer offered, and selecting nothing is worse than
  /// selecting the first pick.
  int _celebrationSeedEffectId() {
    final stored = widget.initialEffectId;
    if (stored != null &&
        WledEffectsCatalog.celebrationPickIds.contains(stored)) {
      return stored;
    }
    return WledEffectsCatalog.celebrationPickIds.first;
  }

  /// CELEBRATION MODE's whole layout: the curated effect list, the two knobs
  /// that actually reach the fired celebration (`sx` / `ix`), and one commit.
  ///
  /// Deliberately NOT here, and why:
  ///   • the LEDs-per-color selector — `grp`/`spc` are base-design geometry;
  ///     a celebration overlays whatever the house is already showing.
  ///   • the roofline preview strip — it renders the BASE design's colours at
  ///     140px and was overflowing its right edge; the per-tile mini previews
  ///     already show what each effect does.
  ///   • the motion / colour filter chips and the "N EFFECTS / Clear filters"
  ///     row — there is one fixed list, so there is nothing to filter.
  ///
  /// [Material] and [SafeArea] are supplied HERE rather than by the caller
  /// because celebration is the only mode pushed as a bare route body; the
  /// other three render inside a Scaffold that already provides both. Without
  /// the Material ancestor every Text falls back to Flutter's un-styled
  /// default (the yellow double-underline); without the SafeArea the header
  /// sits under the status bar.
  Widget _buildCelebrationBody(int effectId, int speed, int intensity) {
    final picks = scopeRainbowEffects(WledEffectsCatalog.celebrationPicks, rainbowScope: _isRainbowPalette);
    return Material(
      color: NexGenPalette.matteBlack,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildCelebrationHeader()),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),

            // Speed — drives `sx` on the fired celebration.
            SliverToBoxAdapter(
              child: EffectSpeedSlider(
                key: const ValueKey('celebration-speed'),
                rawSpeed: speed,
                effectId: effectId,
                onChanged: (raw) {
                  ref.read(selectorSpeedProvider.notifier).state = raw;
                  _sendToWled();
                },
              ),
            ),

            // Intensity — drives `ix`.
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

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'CELEBRATION EFFECTS',
                  style: TextStyle(
                    color: NexGenPalette.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 6)),

            // The SAME tile the catalog list uses — see [_buildEffectTile].
            SliverPadding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 24,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final effect = picks[index];
                    return _buildEffectTile(effect, effect.id == effectId);
                  },
                  childCount: picks.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCelebrationHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('celebration-back'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 22),
            tooltip: 'Back',
            style: IconButton.styleFrom(
              foregroundColor: NexGenPalette.textHigh,
            ),
          ),
          Expanded(
            child: Text(
              widget.paletteNode.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            key: const ValueKey('celebration-save'),
            onPressed: _applyPattern,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Set celebration'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: NexGenPalette.matteBlack,
              minimumSize: const Size(0, 40),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRooflinePreview(int effectId, int speed) {
    final houseImageUrl = ref.watch(currentUserProfileProvider).maybeWhen(
      data: (u) => u?.housePhotoUrl,
      orElse: () => null,
    );
    final hasCustomImage = houseImageUrl != null && houseImageUrl.isNotEmpty;

    // What the hero draws: the fx / pal that reach the WIRE, not the catalog
    // id. [effectId] arrives as the gradient's real fx (83, or 2 breathing) or
    // the raw catalog id; Solid with a multi-colour palette goes out as fx 83
    // + pal 5 (Blocks) or fx 84 / fx 83 + pal 0 (Alternating), and the painter
    // tells those apart by `pal`. Passing the raw 0 with no palette, as this
    // did until 2026-09-22, drew every layout as alternating bands whatever
    // the chips said. A brightness gradient is fx 83 + pal 5 with its steps as
    // col[], which the device lays out positionally too — so it draws as
    // blocks now, as it renders.
    final heroFx =
        _isBrightnessGradient ? effectId : _effectiveEffectId(effectId);
    final heroPal = _isBrightnessGradient
        ? WledEffectsCatalog.paletteForEffect(heroFx)
        : (_activeSolidFields()?.pal ??
            rainbowPaletteOverride(
                effectId: heroFx, rainbowScope: _isRainbowPalette) ??
            WledEffectsCatalog.paletteForEffect(heroFx));

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
                    previewEffectId: heroFx,
                    previewPaletteId: heroPal,
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
                  // Preview what tapping this tile SENDS, not the catalog id:
                  // Solid with a multi-colour palette goes out as fx 83
                  // (Blocks) or fx 84 / fx 83+pal:0 (Alternating). Passing
                  // the raw 0 previewed a single flat colour.
                  effectId: _effectiveEffectId(effect.id),
                  colors: _paletteColors,
                  borderRadius: 8,
                  alternatingLedsPerColor: _solidFieldsFor(effect.id) != null &&
                          ref.read(selectorSolidLayoutProvider) ==
                              SolidLayout.alternating
                      ? ref.read(selectorColorGroupProvider)
                      : null,
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
          // Blocks vs Alternating — only meaningful when Solid is being
          // substituted for a multi-colour palette. Both names are new
          // product copy: docs/guides-2026-09 has no term for either layout,
          // the catalog calls them "Solid Pattern" / "Solid Pattern Tri", and
          // the AI composer's enum says `alternating`. Flagged in the report.
          if (_solidFieldsFor(ref.watch(selectorEffectIdProvider)) != null) ...[
            Text(
              'Layout',
              style: TextStyle(
                color: NexGenPalette.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final layout in SolidLayout.values) ...[
                  _buildFilterChip(
                    label: layout == SolidLayout.blocks
                        ? 'Blocks'
                        : 'Alternating',
                    isSelected:
                        ref.watch(selectorSolidLayoutProvider) == layout,
                    onTap: () {
                      ref.read(selectorSolidLayoutProvider.notifier).state =
                          layout;
                      _sendToWled();
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
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
          const SizedBox(height: 12),
          // The OFF count. There was no control for `spc` anywhere in the
          // tuner — it could only be inherited from whichever "N On M Off"
          // card was opened (max 4 off) and could never be changed, so going
          // from "4 off" to "6 off" was impossible here (followup N3b).
          Text(
            'Dark LEDs between',
            style: TextStyle(
              color: NexGenPalette.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _buildSpacingSelector(ref.watch(selectorSpacingProvider)),
          const SizedBox(height: 8),
          _buildColorLayoutPreview(colorGroup),
        ],
      ),
    );
  }

  /// 0–10 dark LEDs between bands (`spc`). Horizontally scrollable so eleven
  /// 40 px chips fit a phone without shrinking below a tappable size.
  Widget _buildSpacingSelector(int spacing) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(11, (value) {
          final isSelected = spacing == value;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                ref.read(selectorSpacingProvider.notifier).state = value;
                _sendToWled();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? NexGenPalette.cyan.withValues(alpha: 0.2)
                      : NexGenPalette.gunmetal,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
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
            ),
          );
        }),
      ),
    );
  }

  Widget _buildColorLayoutPreview(int colorGroup) {
    final colors = _paletteColors.take(3).toList();
    if (colors.isEmpty) colors.add(Colors.white);
    final spc = ref.watch(selectorSpacingProvider);
    final cycle = colorGroup + spc;

    // Solid + multi-colour palette is sent as fx 83 + pal:5, and the device
    // lays the palette out POSITIONALLY — N contiguous blocks in col[] order
    // (thirds for three colours), regardless of `grp`. This row used to cycle
    // colours per dot for that case and showed a bulb-by-bulb alternation the
    // roofline never produces; it was the most-reported preview/reality
    // mismatch. Every other effect keeps its real grp-band rendering.
    // Decision comes from the same helper the apply path uses.
    final solidBlocks = isSolidPaletteSubstitution(
          effectId: ref.watch(selectorEffectIdProvider),
          colorCount: colors.length,
          isArchitectural: _isArchitectural,
        ) &&
        ref.watch(selectorSolidLayoutProvider) == SolidLayout.blocks;
    // (Alternating keeps the `(i ~/ colorGroup) % N` rendering below — that IS
    // the device's grp expansion, and is now the only case it is drawn for.)
    const dotCount = 18;

    final dots = <Widget>[];
    for (int i = 0; i < dotCount; i++) {
      final bool lit = spc == 0 || cycle == 0 || (i % cycle) < colorGroup;
      final Color dotColor;
      if (lit) {
        final colorIndex = solidBlocks
            ? solidPaletteBlockIndex(i, dotCount, colors.length)
            : (i ~/ colorGroup) % colors.length;
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

/// What [_ColorwayEffectSelectorPageState._buildCommit] resolves for a commit.
class _Commit {
  final Map<String, dynamic> payload;
  final int fxId;
  final int speed;
  final int intensity;
  final int colorGroup;
  final int spacing;
  final String effectName;
  final List<Color> previewColors;
  final int? pal;
  const _Commit({
    required this.payload,
    required this.fxId,
    required this.speed,
    required this.intensity,
    required this.colorGroup,
    required this.spacing,
    required this.effectName,
    required this.previewColors,
    required this.pal,
  });
}

enum _SaveTarget { favorites, gameDay, schedule }

/// The favorites document id for a catalog design: palette + effect, so the
/// same palette with two effects is two favorites, not one overwrite.
String favoritePatternIdFor(LibraryDesignSelection selection) {
  final seg = selection.wledPayload['seg'];
  final first = seg is List && seg.isNotEmpty ? seg.first : seg;
  final fx = first is Map ? first['fx'] : null;
  return fx == null ? selection.id : '${selection.id}_fx$fx';
}

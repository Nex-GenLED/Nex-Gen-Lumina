import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/device_identity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_save_errors.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/schedule/schedule_off_warning.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/manual_editor/design_preview.dart';
import 'package:nexgen_command/features/design/manual_editor/edit_history.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/manual_editor/selection_logic.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_walkthrough.dart';
import 'package:nexgen_command/features/design/roofline_segmentation.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';
import 'package:nexgen_command/features/design/widgets/design_dialogs.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/device_write_reporter.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';

/// Design Studio Slice 4 — the manual per-pixel editor body (rendered inside
/// the studio's "Manual Design" mode). Select pixels (singles, drag ranges,
/// every-Nth, by-feature, anchors), paint them, undo/redo, live-preview on the
/// lights, apply, and save as a CustomDesign to the shared /designs library.
class ManualDesignEditor extends ConsumerStatefulWidget {
  const ManualDesignEditor({super.key, this.initialDesign});

  /// Optional design to open into the editor (a saved manual OR AI design).
  final CustomDesign? initialDesign;

  @override
  ConsumerState<ManualDesignEditor> createState() => _ManualDesignEditorState();
}

class _ManualDesignEditorState extends ConsumerState<ManualDesignEditor> {
  static const _base = [10, 10, 12, 0];

  EditHistory? _history;
  int? _activeChannel;
  final Map<int, Set<int>> _selection = {};
  List<int> _paintColor = kSmartPresetPalette[3].rgbw; // cyan default
  bool _livePreview = false;
  Timer? _previewThrottle;
  bool _busy = false;
  final _previewReporter = DeviceWriteReporter(what: 'preview');

  PixelDesignDocument get _doc => _history!.current;

  @override
  void dispose() {
    _previewThrottle?.cancel();
    _goToController.dispose();
    super.dispose();
  }

  Map<int, int> _channelLengths() {
    final channels = ref.read(deviceChannelsProvider);
    return {for (final c in channels) c.id: (c.stop - c.start).clamp(0, 100000)};
  }

  void _ensureInit() {
    if (_history != null) return;
    final lengths = _channelLengths();
    if (lengths.isEmpty) return;
    PixelDesignDocument doc;
    if (widget.initialDesign != null) {
      final groups = <int, List<LedColorGroup>>{
        for (final ch in widget.initialDesign!.channels)
          if (ch.included) ch.channelId: ch.colorGroups,
      };
      doc = PixelDesignDocument.fromLedColorGroups(
          baseColor: _base, channelLengths: lengths, groupsByChannel: groups);
    } else {
      doc = PixelDesignDocument.blank(baseColor: _base, channelLengths: lengths);
    }
    _history = EditHistory(doc);
    _activeChannel = lengths.keys.first;
  }

  // ── Editing ─────────────────────────────────────────────────────────────

  void _commit(PixelDesignDocument next) {
    _history!.push(next);
    setState(() {});
    if (_livePreview) _scheduleLivePreview();
  }

  void _paintSelection() {
    if (_selection.values.every((s) => s.isEmpty)) return;
    var doc = _doc;
    for (final e in _selection.entries) {
      doc = doc.paint(e.key, e.value, _paintColor);
    }
    _commit(doc);
  }

  void _clearSelectionToBase() {
    var doc = _doc;
    for (final e in _selection.entries) {
      doc = doc.clearToBase(e.key, e.value);
    }
    _commit(doc);
  }

  void _undo() {
    _history!.undo();
    setState(() {});
    if (_livePreview) _scheduleLivePreview();
  }

  void _redo() {
    _history!.redo();
    setState(() {});
    if (_livePreview) _scheduleLivePreview();
  }

  // ── Selection ───────────────────────────────────────────────────────────

  Set<int> _sel(int channel) => _selection.putIfAbsent(channel, () => {});

  void _toggle(int channel, int index) {
    final s = _sel(channel);
    if (!s.remove(index)) s.add(index);
    setState(() {});
  }

  void _selectRange(int channel, int a, int b) {
    final s = _sel(channel);
    for (int i = a <= b ? a : b; i <= (a <= b ? b : a); i++) {
      s.add(i);
    }
    setState(() {});
  }

  void _addAll(int channel, Iterable<int> indices) {
    _sel(channel).addAll(indices);
    setState(() {});
  }

  void _clearSelection() {
    _selection.clear();
    setState(() {});
  }

  void _selectFeature(FeatureFilter filter) {
    final what = switch (filter) {
      FeatureFilter.allCorners => 'corners',
      FeatureFilter.allPeaks => 'peaks',
      FeatureFilter.allRuns => 'runs',
    };
    _selectMapped(what, (segs) => featureIndices(segs, filter));
  }

  void _selectAnchors() => _selectMapped('anchors', anchorIndices);

  // ── Sections: the selection unit (+110 E2 item 1b) ──────────────────────
  //
  // The owner's report from the device: selecting one pixel out of hundreds
  // on a linear strip is unusable at roofline scale. The named features the
  // roofline walkthrough marks — corners, peaks, runs — are what a customer
  // thinks in. So the FIRST thing on the channel is its sections: tap one to
  // select it, then Paint. The strip below still toggles single lights, for
  // fine-tuning INSIDE a selected section.

  /// The id of the section the customer last selected, per channel.
  final Map<int, String> _selectedSection = {};

  /// The named features on [ch], in roofline order.
  List<RooflineSegment> _sectionsFor(int ch) {
    final config = ref.read(currentRooflineConfigProvider).valueOrNull;
    final segs = config?.segmentsForChannel(ch) ?? const <RooflineSegment>[];
    if (!isChannelFeatureMarked(segs)) return const [];
    final len = _channelLengths()[ch] ?? 0;
    return [
      for (final s in segs)
        if (s.startPixel < len && s.pixelCount > 0) s,
    ]..sort((a, b) => a.startPixel.compareTo(b.startPixel));
  }

  /// Selects exactly [seg]'s lights on [ch] (replacing the selection there),
  /// or adds them when [add].
  void _selectSection(int ch, RooflineSegment seg, {bool add = false}) {
    final len = _channelLengths()[ch] ?? 0;
    final indices = segmentIndices(seg).where((i) => i >= 0 && i < len);
    final s = _sel(ch);
    if (!add) s.clear();
    s.addAll(indices);
    _selectedSection[ch] = seg.id;
    setState(() {});
    _stripKey.currentState?.reveal(seg.startPixel, seg.endPixel.clamp(0, len - 1));
  }

  /// "Corner 2", "Peak", "Run 3" — or the name the installer gave it.
  static String sectionLabel(RooflineSegment seg, List<RooflineSegment> all) {
    final kind = featureKindOf(seg);
    final kindName = switch (kind) {
      RooflineFeatureKind.corner => 'Corner',
      RooflineFeatureKind.peak => 'Peak',
      RooflineFeatureKind.run => 'Run',
      RooflineFeatureKind.column => 'Column',
      RooflineFeatureKind.connector => 'Connector',
    };
    final name = seg.name.trim();
    final generic = name.isEmpty ||
        RegExp(r'^(segment|section|run|corner|peak)\s*\d*$', caseSensitive: false)
            .hasMatch(name);
    if (!generic) return name;
    final sameKind = all.where((s) => featureKindOf(s) == kind).toList();
    if (sameKind.length <= 1) return kindName;
    final n = sameKind.indexWhere((s) => s.id == seg.id) + 1;
    return '$kindName $n';
  }

  static IconData _sectionIcon(RooflineFeatureKind kind) => switch (kind) {
        RooflineFeatureKind.corner => Icons.turn_right,
        RooflineFeatureKind.peak => Icons.change_history,
        RooflineFeatureKind.run => Icons.horizontal_rule,
        RooflineFeatureKind.column => Icons.view_column_outlined,
        RooflineFeatureKind.connector => Icons.link,
      };

  Widget _buildSections(int ch, int len) {
    final sections = _sectionsFor(ch);
    if (sections.isEmpty) {
      return Container(
        key: const ValueKey('editor-no-sections'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              "Channel sections aren't marked yet — select by light for now, "
              'or mark the corners and peaks to paint by section.',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
            ),
            OutlinedButton.icon(
              onPressed: () => openRooflineFeatureWalkthrough(context),
              icon: const Icon(Icons.touch_app_outlined, size: 16),
              label: const Text('Mark corners and peaks'),
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: NexGenPalette.cyan),
            ),
          ],
        ),
      );
    }
    final selectedId = _selectedSection[ch];
    final selected = _sel(ch);
    return Column(
      key: const ValueKey('editor-sections'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sections — tap one, then Paint',
            style: TextStyle(color: NexGenPalette.textMedium)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final seg in sections)
              _SectionChip(
                key: ValueKey('section-${seg.id}'),
                label: sectionLabel(seg, sections),
                icon: _sectionIcon(featureKindOf(seg)),
                lights: seg.pixelCount,
                // "Selected" means its lights are all in the selection —
                // whether they got there by a tap here or by hand.
                selected: seg.id == selectedId &&
                    segmentIndices(seg)
                        .where((i) => i < len)
                        .every(selected.contains),
                onTap: () => _selectSection(ch, seg),
                onLongPress: () => _selectSection(ch, seg, add: true),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Hold a section to add it to the selection. Tap a light below to '
          'fine-tune inside it.',
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
        ),
      ],
    );
  }

  /// Adds the map-derived [pick] to the selection — and SAYS SO when there is
  /// nothing to pick. These tools used to be silent no-ops whenever the map
  /// held no such feature, which is every production map today (audit F5): the
  /// user tapped "All corners", nothing happened, and nothing said why.
  void _selectMapped(
    String what,
    Set<int> Function(List<RooflineSegment> channelSegments) pick,
  ) {
    final ch = _activeChannel;
    if (ch == null) return;
    final config = ref.read(currentRooflineConfigProvider).valueOrNull;
    final len = _channelLengths()[ch] ?? 0;
    final segs = config?.segmentsForChannel(ch) ?? const <RooflineSegment>[];
    // Only LEDs that exist on this channel count as "found".
    final found = pick(segs).where((i) => i >= 0 && i < len).toSet();
    if (found.isEmpty) {
      final noMap = config == null || config.segments.isEmpty;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(noMap
              ? "Nothing to select — your roofline isn't mapped yet."
              : 'Nothing to select — Channel ${ch + 1} has no $what marked '
                  'in your roofline map.'),
          duration: const Duration(seconds: 5),
        ));
      return;
    }
    _addAll(ch, found);
  }

  // Last values used in the pattern dialog, per editor session. They used to
  // be locals re-initialised on every open (Start 0 / End last / Every 3), so
  // adjusting a pattern meant re-entering it from scratch.
  int? _patStart, _patEnd;
  int _patOn = 1, _patOff = 2;

  /// The "N on, M off" pattern tool (was "Every-Nth").
  ///
  /// Every-Nth only ever ADDED to the selection, and Paint only ever ADDS
  /// pixels, so re-running it to widen a pattern produced the UNION of old and
  /// new — every-5th re-run as every-7th left 41 LEDs lit where a clean
  /// every-7th is 19 (followup N3a). "Paint pattern" now writes BOTH halves in
  /// one undoable step: the lit LEDs get the paint colour and the dark LEDs in
  /// the range are cleared, so changing "4 off" to "6 off" gives exactly the
  /// new pattern. "Select" replaces the selection inside the range.
  Future<void> _everyNthDialog() async {
    final ch = _activeChannel;
    if (ch == null) return;
    final len = _channelLengths()[ch] ?? 0;
    if (len <= 0) return;

    final result = await showOnOffPatternDialog(
      context,
      length: len,
      start: (_patStart ?? 0).clamp(0, len - 1),
      end: (_patEnd ?? len - 1).clamp(0, len - 1),
      on: _patOn,
      off: _patOff,
    );
    // Remember the numbers even on Cancel — the next open resumes from them.
    _patStart = result.start;
    _patEnd = result.end;
    _patOn = result.on;
    _patOff = result.off;
    final action = result.action;
    if (action == null || !mounted) return;

    final start = result.start, end = result.end;
    final pattern = onOffPatternInRange(
        start: start, end: end, on: result.on, off: result.off);
    // Selection is REPLACED inside the range (not unioned with what was there).
    _sel(ch)
      ..removeWhere((i) => i >= start && i <= end)
      ..addAll(pattern.lit);
    if (action == OnOffPatternAction.paint) {
      _commit(_doc.clearToBase(ch, pattern.dark).paint(ch, pattern.lit, _paintColor));
    } else {
      setState(() {});
    }
  }

  // ── Go to LED (audit F2) ────────────────────────────────────────────────

  final _goToController = TextEditingController();
  final _stripKey = GlobalKey<_SelectionStripState>();
  String? _goToError;

  /// Selects LED `57` or the range `12-40` typed into the "Go to LED" box and
  /// brings it into view, zoomed in. The strip draws a whole channel in one
  /// row — ~2 px per LED at 128–162 LEDs, where a fingertip covers ~20 — so a
  /// specific pixel could not be reached by touch at all.
  void _goToLed() {
    final ch = _activeChannel;
    if (ch == null) return;
    final len = _channelLengths()[ch] ?? 0;
    final target = parseLedTarget(_goToController.text, len);
    if (target == null) {
      setState(() => _goToError = 'Enter an LED 0–${len - 1}, or a range like 12-40');
      return;
    }
    FocusScope.of(context).unfocus();
    _goToError = null;
    _selectRange(ch, target.start, target.end); // calls setState
    _stripKey.currentState?.reveal(target.start, target.end);
  }

  // ── Apply / preview / save ──────────────────────────────────────────────

  Map<int, List<PixelSpan>> _spans() {
    final groups = _doc.toLedColorGroups(onlyPainted: true);
    return {for (final e in groups.entries) e.key: ledColorGroupsToSpans(e.value)};
  }

  /// The brightness this editor's own writes state: the stored level of the
  /// design being EDITED, so the lights show it as it will come back. A new
  /// painting has none yet — null leaves the controller's level alone, and
  /// [_save] records that level.
  int? get _designBrightness => widget.initialDesign?.appliedBrightness;

  /// Row 40: every channel this editor paints (the base colour covers each
  /// of them), never the Home channel bar's selection.
  List<int> _targets() =>
      designTargetChannels(ref.read, _doc.channelLengths.keys);

  void _scheduleLivePreview() {
    _previewThrottle?.cancel();
    _previewThrottle = Timer(const Duration(milliseconds: 300), () async {
      // Was fire-and-forget with the result dropped: a controller that had
      // stopped answering looked exactly like one following along (F7).
      final ok = await applyBaseAndSpans(ref,
          baseRgbw: _doc.baseColor,
          spansByChannel: _spans(),
          label: 'Design (preview)',
          brightness: _designBrightness,
          targetChannels: _targets());
      if (mounted) _previewReporter.report(context, ok);
    });
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final result = await applyBaseAndSpansDetailed(ref,
          baseRgbw: _doc.baseColor,
          spansByChannel: _spans(),
          label: 'Custom Design',
          brightness: _designBrightness,
          targetChannels: _targets());
      final ok = result.isOk;
      if (mounted) {
        // Row 42: the result's own sentence. A closed gate (no controller,
        // away from home) says WHY, through the shared reason.
        final blocked = result == SpineWriteResult.noDevice ||
            result == SpineWriteResult.noChannels;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          // #94 — an identity refusal must say so, not blame the network.
          content: Text(ok
              ? 'Applied to your lights'
              : (takeIdentityRefusalMessage() ??
                  (blocked ? applyBlockedReason(ref.read) : null) ??
                  result.userMessage ??
                  "Couldn't reach your lights.")),
          backgroundColor: ok ? Colors.green : Colors.red.shade800,
          duration: Duration(seconds: ok ? 3 : 6),
        ));
      }
      if (ok) maybeShowManualApplyOffWarning(ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prompts for a name on a NEW design. Defaults to "Custom Design N"
  /// (N = one more than the count already matching that pattern) instead of
  /// the old hardcoded 'Custom Design', which made every per-pixel design in
  /// My Designs share one name (audit/MY_DESIGNS_AUDIT.md §6.1).
  Future<String?> _promptForName() async {
    final existing =
        ref.read(designsStreamProvider).valueOrNull ?? const <CustomDesign>[];
    return showNameDesignDialog(context,
        initialName: nextCustomDesignName(existing));
  }

  Future<void> _save() async {
    final uid = ref.read(effectiveUserUidProvider);
    if (uid == null) {
      // Used to return without a word — Save looked like it did nothing.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sign in to save designs. Nothing was saved.'),
        backgroundColor: Colors.red.shade800,
      ));
      return;
    }

    // EDIT vs NEW. When the editor was opened on a stored design, save must
    // UPDATE THAT DOC — carrying its id forward is what routes
    // `DesignService.saveDesign` to `updateDesign` rather than `createDesign`
    // (design_service.dart:43-49), so editing never forks a second copy.
    final existing = widget.initialDesign;
    final String name;
    if (existing != null) {
      name = existing.name; // an edit keeps the name; Rename owns changing it
    } else {
      final chosen = await _promptForName();
      if (chosen == null) return; // cancelled — do not write
      final trimmed = chosen.trim();
      if (trimmed.isEmpty) return;
      name = trimmed;
    }
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final groups = _doc.toLedColorGroups(); // full coverage → self-contained
      final channels = [
        for (final e in groups.entries)
          ChannelDesign(
            channelId: e.key,
            channelName: 'Channel ${e.key + 1}',
            colorGroups: e.value,
            ledCount: _doc.channelLength(e.key),
          ),
      ];
      // BRIGHTNESS. This editor has no brightness control: the user paints
      // while watching the lights at whatever level they are at, so THAT is
      // the level the design is recorded at and comes back at. (It used to
      // store the model's default 200, which no apply path could honour
      // without overriding a level somebody had actually set.) An edit of a
      // design that already states one keeps it — it was chosen elsewhere
      // (the Pattern Editor's slider) and this editor previews with it. With
      // no controller connected there is no level to record. (The repository
      // is checked first so an editor with no controller never spins up the
      // state notifier — and its poll timers — just to learn that.)
      final wledState = ref.read(wledRepositoryProvider) == null
          ? null
          : ref.read(wledStateProvider);
      final live = wledState == null
          ? null
          : liveBrightnessToStore(
              connected: wledState.connected,
              brightness: wledState.brightness);
      final keepStored = existing != null && existing.statesBrightness;

      // copyWith on the loaded doc for an edit: every field the editor does
      // not own (tags, description, composedPattern, roofline/segment
      // metadata) round-trips untouched.
      final design = existing != null
          ? existing.copyWith(
              name: name,
              channels: channels,
              updatedAt: DateTime.now(),
              // Whatever it was when it was opened, it has now been painted.
              perPixel: true,
              brightness: keepStored ? null : live,
              brightnessStated: keepStored ? true : live != null,
            )
          : CustomDesign(
              id: '',
              name: name,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              ownerId: uid,
              channels: channels,
              brightness: live ?? 200,
              brightnessStated: live != null,
              // STATED, not inferred: a painted design that is one colour (or
              // blank) is a single group per channel and is otherwise
              // indistinguishable from a captured solid — it used to be
              // classed "effect", so Edit opened the colourway tuner instead
              // of this editor.
              perPixel: true,
            );
      await ref.read(designServiceProvider).saveDesign(uid, design);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(existing != null
                ? 'Updated "$name"'
                : 'Saved "$name" to My Designs'),
            backgroundColor: NexGenPalette.cyan));
      }
    } catch (e, st) {
      // There was NO catch here. DesignService rethrows, so a denied or failed
      // write escaped as an unhandled async error and the screen showed
      // nothing: buttons greyed, came back, design not in My Designs (F6).
      debugPrint('ManualDesignEditor save failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(describeDesignSaveError(e, isEdit: existing != null)),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 7),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _ensureInit();
    final lengths = _channelLengths();
    if (_history == null || lengths.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Connect your controller to paint pixels.',
              style: TextStyle(color: NexGenPalette.textMedium)),
        ),
      );
    }
    final ch = _activeChannel!;
    final frame = frameFromDocument(_doc);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignPreview(frame: frame, height: 200),
          const SizedBox(height: 12),
          // Channel tabs.
          if (lengths.length > 1)
            Wrap(spacing: 8, children: [
              for (final id in lengths.keys)
                ChoiceChip(
                  selected: id == ch,
                  label: Text('Channel ${id + 1}'),
                  onSelected: (_) => setState(() => _activeChannel = id),
                ),
            ]),
          const SizedBox(height: 8),
          // Sections first: the selection unit (item 1b).
          _buildSections(ch, lengths[ch] ?? 0),
          const SizedBox(height: 10),
          // Selection strip (tap toggle + drag range) — fine-tuning.
          _SelectionStrip(
            key: _stripKey,
            length: lengths[ch] ?? 0,
            selected: _sel(ch),
            colorAt: (i) => _toColorLocal(_doc.colorAt(ch, i)),
            onToggle: (i) => _toggle(ch, i),
            onRange: (a, b) => _selectRange(ch, a, b),
          ),
          const SizedBox(height: 8),
          // Go to LED — reach one specific pixel (or a range) by NUMBER.
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                key: const ValueKey('go-to-led'),
                controller: _goToController,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _goToLed(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  // A short label and a hint: the long label was cut short at
                  // large text (+110 E2 accessibility).
                  labelText: 'Go to LED',
                  hintText: '57 or 12-40',
                  labelStyle: const TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
                  errorText: _goToError,
                  errorMaxLines: 3,
                  helperText: '${_sel(ch).length} selected on Channel ${ch + 1} '
                      '(LEDs 0–${(lengths[ch] ?? 1) - 1})',
                  helperMaxLines: 3,
                  helperStyle: const TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton(onPressed: _goToLed, child: const Text('Select')),
            ),
          ]),
          const SizedBox(height: 10),
          // Selection tools.
          Wrap(spacing: 8, runSpacing: 8, children: [
            _tool('All corners', () => _selectFeature(FeatureFilter.allCorners)),
            _tool('All peaks', () => _selectFeature(FeatureFilter.allPeaks)),
            _tool('All runs', () => _selectFeature(FeatureFilter.allRuns)),
            _tool('Anchors', _selectAnchors),
            _tool('On / off pattern', _everyNthDialog),
            _tool('Clear sel.', _clearSelection),
          ]),
          const Divider(color: NexGenPalette.line, height: 24),
          // Palette.
          const Text('Paint color', style: TextStyle(color: NexGenPalette.textMedium)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in kSmartPresetPalette)
              GestureDetector(
                onTap: () => setState(() => _paintColor = p.rgbw),
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, p.rgbw[0], p.rgbw[1], p.rgbw[2]),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _eq(p.rgbw, _paintColor) ? NexGenPalette.cyan : NexGenPalette.line,
                      width: _eq(p.rgbw, _paintColor) ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _paintSelection, icon: const Icon(Icons.brush, size: 18), label: const Text('Paint')),
            OutlinedButton.icon(onPressed: _clearSelectionToBase, icon: const Icon(Icons.format_color_reset, size: 18), label: const Text('Erase')),
            IconButton(onPressed: _history!.canUndo ? _undo : null, icon: const Icon(Icons.undo), color: Colors.white),
            IconButton(onPressed: _history!.canRedo ? _redo : null, icon: const Icon(Icons.redo), color: Colors.white),
          ]),
          const Divider(color: NexGenPalette.line, height: 24),
          Row(children: [
            Switch(value: _livePreview, onChanged: (v) {
              setState(() => _livePreview = v);
              if (v) _scheduleLivePreview();
            }),
            const Text('Preview on lights', style: TextStyle(color: Colors.white)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
                onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Save'))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: FilledButton.icon(
                onPressed: _busy ? null : _apply, icon: const Icon(Icons.lightbulb, size: 18), label: const Text('Apply to Lights'))),
          ]),
        ],
      ),
    );
  }

  Widget _tool(String label, VoidCallback onTap) =>
      OutlinedButton(onPressed: onTap, child: Text(label));

  Color _toColorLocal(List<int> rgbw) => rgbw.length >= 3
      ? Color.fromARGB(255, rgbw[0], rgbw[1], rgbw[2])
      : Colors.black;

  bool _eq(List<int> a, List<int> b) =>
      a.length == b.length && a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3];
}

/// One roofline section on the active channel.
class _SectionChip extends StatelessWidget {
  const _SectionChip({
    super.key,
    required this.label,
    required this.icon,
    required this.lights,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final IconData icon;
  final int lights;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? NexGenPalette.cyan.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? NexGenPalette.cyan : NexGenPalette.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? NexGenPalette.cyan : Colors.white70),
              const SizedBox(width: 6),
              Text(
                '$label · $lights',
                style: TextStyle(
                  color: selected ? NexGenPalette.cyan : Colors.white,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal LED strip for selection: tap toggles a cell, a drag selects a
/// range. Each cell shows its current paint color; selected cells get a ring.
///
/// ZOOM + PAN (audit F2). The whole channel used to be squeezed into the
/// available width — `cell = width / length` — which at 128–162 LEDs is ~2 px
/// per LED with a fingertip covering ~20: no specific pixel could be aimed at
/// or even seen. The − / + buttons scale the cells (1× = fit, up to 32×); once
/// zoomed the strip scrolls sideways and shows LED numbers. At 1× a horizontal
/// drag selects a range as before; when zoomed a plain drag PANS and a
/// long-press-drag selects, so both remain possible.
class _SelectionStrip extends StatefulWidget {
  const _SelectionStrip({
    super.key,
    required this.length,
    required this.selected,
    required this.colorAt,
    required this.onToggle,
    required this.onRange,
  });

  final int length;
  final Set<int> selected;
  final Color Function(int) colorAt;
  final void Function(int) onToggle;
  final void Function(int a, int b) onRange;

  @override
  State<_SelectionStrip> createState() => _SelectionStripState();
}

class _SelectionStripState extends State<_SelectionStrip> {
  static const _zoomLevels = [1.0, 2.0, 4.0, 8.0, 16.0, 32.0];
  static const double _minRevealCell = 18; // px per LED after a "Go to LED"

  final _scroll = ScrollController();
  int _zoomIndex = 0;
  int? _dragStart;
  int? _lastTouched;
  double _viewport = 0;

  double get _zoom => _zoomLevels[_zoomIndex];
  double get _cell =>
      widget.length <= 0 ? 0 : (_viewport / widget.length) * _zoom;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _indexAt(double dxInContent) {
    if (widget.length <= 0 || _cell <= 0) return 0;
    return (dxInContent / _cell).floor().clamp(0, widget.length - 1);
  }

  void _setZoom(int index, {int? keepLed}) {
    final next = index.clamp(0, _zoomLevels.length - 1);
    // Keep the same LED under the middle of the viewport while zooming.
    final centreLed = keepLed ??
        (_scroll.hasClients && _cell > 0
            ? ((_scroll.offset + _viewport / 2) / _cell).floor()
            : widget.length ~/ 2);
    setState(() => _zoomIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centreOn(centreLed));
  }

  void _centreOn(int led) {
    if (!_scroll.hasClients) return;
    final target = (led + 0.5) * _cell - _viewport / 2;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  /// Zooms in far enough to see LEDs [a]–[b] individually and scrolls to them.
  void reveal(int a, int b) {
    if (widget.length <= 0 || _viewport <= 0) return;
    int idx = _zoomIndex;
    while (idx < _zoomLevels.length - 1 &&
        (_viewport / widget.length) * _zoomLevels[idx] < _minRevealCell) {
      idx++;
    }
    setState(() => _lastTouched = a);
    _setZoom(idx, keepLed: (a + b) ~/ 2);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) {
        _viewport = c.maxWidth;
        final zoomed = _zoomIndex > 0;
        final content = SizedBox(
          width: _cell * widget.length,
          height: zoomed ? 52 : 34,
          child: CustomPaint(
            painter: _StripPainter(
              length: widget.length,
              cell: _cell,
              colorAt: widget.colorAt,
              selected: widget.selected,
              showNumbers: _cell >= 8,
            ),
          ),
        );
        final gestures = GestureDetector(
          behavior: HitTestBehavior.opaque,
          // onTapUp, not onTapDown: a finger resting on the strip while the
          // PAGE scrolls must not toggle a pixel.
          onTapUp: (d) {
            final i = _indexAt(d.localPosition.dx);
            setState(() => _lastTouched = i);
            widget.onToggle(i);
          },
          // 1× — nothing to pan, so a plain drag selects (as before).
          onHorizontalDragStart: zoomed
              ? null
              : (d) => _dragStart = _indexAt(d.localPosition.dx),
          onHorizontalDragUpdate: zoomed
              ? null
              : (d) {
                  if (_dragStart == null) return;
                  final i = _indexAt(d.localPosition.dx);
                  setState(() => _lastTouched = i);
                  widget.onRange(_dragStart!, i);
                },
          onHorizontalDragEnd: zoomed ? null : (_) => _dragStart = null,
          // Zoomed — a plain drag pans the scroll view; long-press-drag selects.
          onLongPressStart: (d) {
            _dragStart = _indexAt(d.localPosition.dx);
            setState(() => _lastTouched = _dragStart);
            widget.onRange(_dragStart!, _dragStart!);
          },
          onLongPressMoveUpdate: (d) {
            if (_dragStart == null) return;
            final i = _indexAt(d.localPosition.dx);
            setState(() => _lastTouched = i);
            widget.onRange(_dragStart!, i);
          },
          onLongPressEnd: (_) => _dragStart = null,
          child: content,
        );
        return Container(
          decoration: BoxDecoration(
            color: NexGenPalette.matteBlack,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NexGenPalette.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            key: const ValueKey('strip-scroll'),
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: zoomed
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: gestures,
          ),
        );
      }),
      const SizedBox(height: 4),
      Row(children: [
        IconButton(
          key: const ValueKey('strip-zoom-out'),
          tooltip: 'Zoom out',
          visualDensity: VisualDensity.compact,
          onPressed: _zoomIndex > 0 ? () => _setZoom(_zoomIndex - 1) : null,
          icon: const Icon(Icons.zoom_out, color: Colors.white70),
        ),
        Text('${_zoom.toStringAsFixed(0)}×',
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        IconButton(
          key: const ValueKey('strip-zoom-in'),
          tooltip: 'Zoom in',
          visualDensity: VisualDensity.compact,
          onPressed: _zoomIndex < _zoomLevels.length - 1
              ? () => _setZoom(_zoomIndex + 1)
              : null,
          icon: const Icon(Icons.zoom_in, color: Colors.white70),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _zoomIndex == 0
                ? 'Tap a light · drag to select a range · zoom in to reach one LED'
                : 'Tap a light · drag to pan · press-and-hold then drag to select'
                    '${_lastTouched == null ? '' : '   ·   LED $_lastTouched'}',
            style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
          ),
        ),
      ]),
    ]);
  }
}

/// Paints the strip. A CustomPainter rather than a Row of N widgets: at 32× a
/// 162-LED channel is 5,000+ px wide and would otherwise build 162 containers
/// on every selection change.
class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.length,
    required this.cell,
    required this.colorAt,
    required this.selected,
    required this.showNumbers,
  }) : _selectionSnapshot = Set<int>.of(selected);

  final int length;
  final double cell;
  final Color Function(int) colorAt;
  final Set<int> selected;
  final bool showNumbers;
  final Set<int> _selectionSnapshot;

  @override
  void paint(Canvas canvas, Size size) {
    if (length <= 0 || cell <= 0) return;
    const pad = 3.0;
    final barHeight = showNumbers ? size.height - 18 : size.height;
    final gap = cell >= 4 ? 0.6 : 0.0;
    final fill = Paint();
    // WHITE ring: the default paint colour is cyan (#00E5FF), and a cyan
    // selection ring (#00D4FF) on a cyan pixel was indistinguishable.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = cell >= 6 ? 2 : 1;
    for (int i = 0; i < length; i++) {
      final rect = Rect.fromLTWH(
          i * cell + gap, pad, (cell - 2 * gap).clamp(0.5, cell), barHeight - 2 * pad);
      fill.color = colorAt(i);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), fill);
      if (selected.contains(i)) {
        if (cell >= 4) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(2)), ring);
        } else {
          // Too narrow for a ring: a white tick on top marks the selection.
          canvas.drawRect(Rect.fromLTWH(i * cell, 0, cell, pad), Paint()..color = Colors.white);
        }
      }
    }
    if (!showNumbers) return;
    // Label every LED when there is room, else every 5th / 10th.
    final every = cell >= 26 ? 1 : (cell >= 12 ? 5 : 10);
    for (int i = 0; i < length; i += every) {
      final tp = TextPainter(
        text: TextSpan(
            text: '$i',
            style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(i * cell + (cell - tp.width) / 2, barHeight + 2));
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.length != length ||
      old.cell != cell ||
      old.showNumbers != showNumbers ||
      old.colorAt != colorAt ||
      old._selectionSnapshot.length != _selectionSnapshot.length ||
      !old._selectionSnapshot.containsAll(_selectionSnapshot);
}

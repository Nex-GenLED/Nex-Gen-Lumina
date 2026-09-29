import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/channel_direction.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/wled/pattern_adjustment_pacer.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/features/wled/pattern_tweak_sender.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_effect_metadata.dart';
import 'package:nexgen_command/features/patterns/color_sequence_builder.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:nexgen_command/shared/write_result.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/effect_speed_slider.dart';

/// All WLED effects that respect user color selection (uses or blends colors).
/// Excludes effects that generate their own colors, use palettes, require 2D matrix, or require audio.
/// Organized by category for easier browsing.
const List<_EffectOption> _commonEffects = [
  // Basic effects
  _EffectOption(0, 'Solid', Icons.square_rounded),
  _EffectOption(1, 'Blink', Icons.flash_on),
  _EffectOption(2, 'Breathe', Icons.air),
  _EffectOption(12, 'Fade', Icons.gradient),
  _EffectOption(18, 'Dissolve', Icons.blur_on),
  _EffectOption(46, 'Gradient', Icons.linear_scale),
  _EffectOption(47, 'Loading', Icons.hourglass_empty),
  _EffectOption(56, 'Tri Fade', Icons.change_history),
  _EffectOption(62, 'Oscillate', Icons.swap_horiz),
  _EffectOption(83, 'Solid Pattern', Icons.grid_view),
  _EffectOption(84, 'Solid Pattern Tri', Icons.change_history_outlined),
  _EffectOption(85, 'Spots', Icons.blur_circular),
  _EffectOption(86, 'Spots Fade', Icons.blur_circular_outlined),
  _EffectOption(98, 'Percent', Icons.percent),
  _EffectOption(100, 'Heartbeat', Icons.favorite),
  _EffectOption(113, 'Washing Machine', Icons.local_laundry_service),

  // Wipe effects
  _EffectOption(3, 'Wipe', Icons.arrow_forward),
  _EffectOption(6, 'Sweep', Icons.compare_arrows),
  _EffectOption(55, 'Tri Wipe', Icons.arrow_right_alt),

  // Chase effects
  _EffectOption(13, 'Theater', Icons.theater_comedy),
  _EffectOption(15, 'Running', Icons.directions_run),
  _EffectOption(16, 'Saw', Icons.show_chart),
  _EffectOption(27, 'Android', Icons.android),
  _EffectOption(28, 'Chase', Icons.double_arrow),
  _EffectOption(31, 'Chase Flash', Icons.flash_on_outlined),
  _EffectOption(37, 'Chase 2', Icons.fast_forward),
  _EffectOption(50, 'Two Dots', Icons.more_horiz),
  _EffectOption(52, 'Running Dual', Icons.sync_alt),
  _EffectOption(54, 'Chase 3', Icons.fast_forward_outlined),
  _EffectOption(78, 'Railway', Icons.train),
  _EffectOption(111, 'Chunchun', Icons.auto_awesome),

  // Scanner effects
  _EffectOption(10, 'Scan', Icons.sensors),
  _EffectOption(11, 'Scan Dual', Icons.sensors_outlined),
  _EffectOption(40, 'Scanner', Icons.document_scanner),
  _EffectOption(41, 'Lighthouse', Icons.highlight),
  _EffectOption(58, 'ICU', Icons.visibility),
  _EffectOption(60, 'Scanner Dual', Icons.document_scanner_outlined),

  // Sparkle effects
  _EffectOption(17, 'Twinkle', Icons.auto_awesome),
  _EffectOption(20, 'Sparkle', Icons.star),
  _EffectOption(21, 'Sparkle Dark', Icons.star_border),
  _EffectOption(22, 'Sparkle+', Icons.star_half),
  _EffectOption(49, 'Fairy', Icons.auto_fix_high),
  _EffectOption(51, 'Fairytwinkle', Icons.auto_fix_normal),
  _EffectOption(87, 'Glitter', Icons.diamond),
  _EffectOption(103, 'Solid Glitter', Icons.diamond_outlined),

  // Meteor effects
  _EffectOption(59, 'Multi Comet', Icons.rocket),
  _EffectOption(76, 'Meteor', Icons.rocket_launch),
  _EffectOption(77, 'Meteor Smooth', Icons.rocket_launch_outlined),

  // Fire effects (that use selected colors)
  _EffectOption(102, 'Candle Multi', Icons.local_fire_department),

  // Strobe effects
  _EffectOption(23, 'Strobe', Icons.flash_on),
  // 25 Strobe Mega: retired 2026-09-29 (pattern_flash_safety.dart).
  _EffectOption(57, 'Lightning', Icons.bolt),

  // Ambient effects (that use selected colors)
  _EffectOption(96, 'Drip', Icons.water_drop),
  _EffectOption(112, 'Dancing Shadows', Icons.nightlight),

  // Game effects
  _EffectOption(44, 'Tetrix', Icons.view_module),
  _EffectOption(91, 'Bouncing Balls', Icons.sports_basketball),
  _EffectOption(95, 'Popcorn', Icons.local_dining),

  // Holiday effects
  _EffectOption(82, 'Halloween Eyes', Icons.visibility_outlined),
];

class _EffectOption {
  final int id;
  final String name;
  final IconData icon;
  const _EffectOption(this.id, this.name, this.icon);
}

/// Reusable pattern adjustment panel with speed, intensity, direction, effect, and color controls.
///
/// This widget can be embedded in multiple places (home screen, explore patterns, etc.)
/// and provides real-time debounced updates to the connected WLED device.
class PatternAdjustmentPanel extends ConsumerStatefulWidget {
  /// Initial speed value (0-255)
  final int initialSpeed;
  /// Initial intensity value (0-255)
  final int initialIntensity;
  /// Initial direction (false = left-to-right, true = right-to-left)
  final bool initialReverse;
  /// Initial effect ID (WLED fx value)
  final int? initialEffectId;
  /// Effect name to display (from Lumina AI or lookup table)
  final String? effectName;
  /// Initial colors for the color sequence builder (list of RGB arrays)
  final List<List<int>>? initialColors;
  /// Whether to show the color sequence builder
  final bool showColors;
  /// Whether to show pixel layout controls (grouping/spacing)
  final bool showPixelLayout;
  /// Whether to show the effect selector
  final bool showEffectSelector;
  /// Callback when any value changes (for external state tracking)
  final void Function(PatternAdjustmentValues values)? onChanged;
  /// Callback when colors are customized (pattern should be marked as "Custom")
  final VoidCallback? onCustomized;

  const PatternAdjustmentPanel({
    super.key,
    this.initialSpeed = 128,
    this.initialIntensity = 128,
    this.initialReverse = false,
    this.initialEffectId,
    this.effectName,
    this.initialColors,
    this.showColors = true,
    this.showPixelLayout = false,
    this.showEffectSelector = true,
    this.onChanged,
    this.onCustomized,
  });

  @override
  ConsumerState<PatternAdjustmentPanel> createState() => _PatternAdjustmentPanelState();
}

/// Values container for adjustment panel state
class PatternAdjustmentValues {
  final int speed;
  final int intensity;
  final bool reverse;
  final int? effectId;
  final List<List<int>>? colors;
  final int grouping;
  final int spacing;

  const PatternAdjustmentValues({
    required this.speed,
    required this.intensity,
    required this.reverse,
    this.effectId,
    this.colors,
    this.grouping = 1,
    this.spacing = 0,
  });
}

class _PatternAdjustmentPanelState extends ConsumerState<PatternAdjustmentPanel> {
  late int _speed;
  late int _intensity;
  late bool _reverse;
  int? _effectId;
  late List<List<int>>? _colors;
  int _grouping = 1;
  int _spacing = 0;

  /// When speed/intensity and grouping/spacing go out: a short debounce at
  /// home, ONE write when the drag settles away from home, never two in
  /// flight (pattern_adjustment_pacer.dart — +110 E1 follow-up 4).
  late final AdjustmentPacer _lookPacer = AdjustmentPacer(
    flush: _flushLook,
    isRemote: () => ref.read(isRemoteModeProvider),
  );
  late final AdjustmentPacer _layoutPacer = AdjustmentPacer(
    flush: _flushLayout,
    isRemote: () => ref.read(isRemoteModeProvider),
  );

  @override
  void initState() {
    super.initState();
    _speed = widget.initialSpeed;
    _intensity = widget.initialIntensity;
    _acceptedSpeed = _speed;
    _acceptedIntensity = _intensity;
    _reverse = widget.initialReverse;
    _effectId = widget.initialEffectId;
    _colors = widget.initialColors;
  }

  @override
  void didUpdateWidget(covariant PatternAdjustmentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update values if the widget is rebuilt with new initial values
    if (oldWidget.initialSpeed != widget.initialSpeed) {
      _speed = widget.initialSpeed;
      _acceptedSpeed = _speed;
    }
    if (oldWidget.initialIntensity != widget.initialIntensity) {
      _intensity = widget.initialIntensity;
      _acceptedIntensity = _intensity;
    }
    if (oldWidget.initialReverse != widget.initialReverse) {
      _reverse = widget.initialReverse;
    }
    if (oldWidget.initialEffectId != widget.initialEffectId) {
      _effectId = widget.initialEffectId;
    }
    if (oldWidget.initialColors != widget.initialColors) {
      _colors = widget.initialColors;
    }
  }

  @override
  void dispose() {
    _lookPacer.dispose();
    _layoutPacer.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged?.call(PatternAdjustmentValues(
      speed: _speed,
      intensity: _intensity,
      reverse: _reverse,
      effectId: _effectId,
      colors: _colors,
      grouping: _grouping,
      spacing: _spacing,
    ));
  }

  // ── Writes ──────────────────────────────────────────────────────────────
  //
  // Every control here is an ADJUSTMENT of the look that is playing, and goes
  // out through `sendChannelTweak` (pattern_tweak_sender.dart): only the
  // selected channels, only the changed fields, and never `on`.
  //
  // PRIORITY FIX (+110 E1, the foundation's customer walk B1). These used to
  // go through `applyChannelFilter`, the DESIGN-apply shape, which emits
  // `{id, on:false}` for every channel not selected and `on:true` for every
  // one that is. With the channel bar narrowed to channel 1, a speed drag
  // switched channel 2 off; with a channel left out of shows, the same drag
  // switched that one off even under "All Channels"; and a drag re-lit a
  // channel the customer had switched off by hand.

  /// The values the lights last accepted, so a refused write can put the
  /// control back where the lights actually are (row 80).
  late int _acceptedSpeed;
  late int _acceptedIntensity;
  int _acceptedGrouping = 1;
  int _acceptedSpacing = 0;

  /// Sends [fields] as an adjustment and reports a failure on screen through
  /// the shared failure state. Returns whether the lights took it.
  ///
  /// Reads through the ProviderContainer, not `ref`: the write can outlive
  /// this panel (the Tune section collapses), and a disposed `ref` throws.
  Future<bool> _sendAdjustment(Map<String, dynamic> fields) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final result = await container
        .read(wledStateProvider.notifier)
        .runAndReport(
          sendChannelTweak(container.read, fields),
          onFailure: kAdjustmentFailedMessage,
        );
    return result.ok;
  }

  /// The live grouping/spacing, carried on a colour or effect change. The wire
  /// normalizer states `grp:1, spc:0` on any segment that names a colour or an
  /// effect and leaves them out, so without these a colour-sequence tweak
  /// flattened a "1 On 2 Off" look the customer had not touched.
  Map<String, dynamic> _liveLayout() {
    final s = ref.read(wledStateProvider);
    return {'grp': s.colorGroupSize, 'spc': s.spacing};
  }

  /// Mirrors an accepted adjustment into the dashboard preview so the Home
  /// hero shows what the lights are doing (row 80). Only while the house is
  /// lit: the preview sync marks the lights on.
  void _syncAcceptedPreview({
    int? effectId,
    List<List<int>>? colors,
  }) {
    if (!mounted) return;
    final s = ref.read(wledStateProvider);
    if (!s.isOn) return;
    final previewColors = colors == null
        ? s.displayColors
        : [
            for (final c in colors)
              if (c.length >= 3)
                Color.fromARGB(255, c[0].clamp(0, 255), c[1].clamp(0, 255),
                    c[2].clamp(0, 255)),
          ];
    ref.read(wledStateProvider.notifier).applyPreviewSync(
          colors: previewColors.isEmpty ? s.displayColors : previewColors,
          effectId: effectId ?? s.effectId,
          speed: _speed,
          intensity: _intensity,
          brightness: s.brightness,
          colorGroupSize: _groupingForPreview(s.colorGroupSize),
          spacing: _spacingForPreview(s.spacing),
          paletteId: s.paletteId,
        );
  }

  int _groupingForPreview(int live) =>
      widget.showPixelLayout ? _grouping : live;
  int _spacingForPreview(int live) => widget.showPixelLayout ? _spacing : live;

  Future<void> _applyEffect(int effectId) async {
    // Selecting an effect starts it at its curated roofline speed (item D);
    // the slider stays free above and below it. An effect whose speed is not
    // a pace keeps the current speed.
    final speed = effectDefaultSpeedOr(effectId, _speed);
    final intensity = effectDefaultIntensity(effectId) ?? _intensity;
    setState(() {
      _speed = speed;
      _intensity = intensity;
    });
    _notifyChanged();
    final ok = await _sendAdjustment({
      'fx': effectId,
      'sx': speed,
      'ix': intensity,
      'pal': WledEffectsCatalog.paletteForEffect(effectId),
      ..._liveLayout(),
    });
    if (!mounted) return;
    if (ok) {
      _acceptedSpeed = speed;
      _acceptedIntensity = intensity;
      _syncAcceptedPreview(effectId: effectId);
    }
  }

  Future<void> _flushLook() async {
    if (!mounted) return;
    // LOOK ONLY. `rev` used to ride along here, so every speed/intensity
    // DRAG re-asserted direction from this panel's local state — an
    // incidental geometry write on a control that had nothing to do with
    // direction. Direction has its own discrete path (`_applyDirection`)
    // through the provisioning door.
    final sent = (speed: _speed, intensity: _intensity);
    final ok = await _sendAdjustment({'sx': sent.speed, 'ix': sent.intensity});
    if (!mounted) return;
    if (ok) {
      _acceptedSpeed = sent.speed;
      _acceptedIntensity = sent.intensity;
      _syncAcceptedPreview();
    } else if (!_lookPacer.hasPending) {
      // Row 80: the control shows what the lights are doing, not what was
      // asked of them. The reason is already on screen. (Not while a newer
      // value is waiting to go: that one gets its own answer.)
      setState(() {
        _speed = _acceptedSpeed;
        _intensity = _acceptedIntensity;
      });
      _notifyChanged();
    }
  }

  /// User-initiated DIRECTION change → the provisioning door. Discrete, not
  /// debounced. See `channel_direction.dart` (incl. the #102 tension).
  ///
  /// Row 81: the toggle used to flip before the write and stay flipped when
  /// the write was refused. It now flips back and says so.
  Future<void> _applyDirection(bool reverse) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final notifier = container.read(wledStateProvider.notifier);
    final channels = await resolveEffectiveChannelIds(container.read);
    final WriteResult result;
    if (channels.isEmpty) {
      result = WriteResult.blocked(
          applyBlockedReason(container.read) ?? kApplyBlockedFallback);
    } else {
      final ok = await applyChannelDirection(
        repo: container.read(wledRepositoryProvider),
        channelIds: channels,
        reverse: reverse,
      );
      result = ok
          ? const WriteResult.success()
          : WriteResult.failed(
              WriteFailureKind.unsupported,
              message: container.read(isLanConnectedProvider)
                  ? "Direction couldn't be changed — your lights didn't take "
                      'it.'
                  : directionLanOnlyMessage(container.read(siteModeProvider)),
            );
    }
    final reported = await notifier.runAndReport(Future.value(result),
        onFailure: "Direction couldn't be changed.");
    if (!mounted || reported.ok) return;
    setState(() => _reverse = !reverse);
    _notifyChanged();
  }

  Future<void> _flushLayout() async {
    if (!mounted) return;
    final sent = (grp: _grouping, spc: _spacing);
    final ok = await _sendAdjustment({'grp': sent.grp, 'spc': sent.spc});
    if (!mounted) return;
    if (ok) {
      _acceptedGrouping = sent.grp;
      _acceptedSpacing = sent.spc;
      _syncAcceptedPreview();
    } else if (!_layoutPacer.hasPending) {
      setState(() {
        _grouping = _acceptedGrouping;
        _spacing = _acceptedSpacing;
      });
      _notifyChanged();
    }
  }

  /// "Turn on" in the lights-off notice: the explicit power action. An
  /// adjustment never changes power (the PRIORITY rule), so the sliders do not
  /// switch the house on themselves.
  Future<void> _turnOn() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final notifier = container.read(wledStateProvider.notifier);
    await notifier.runAndReport(
      notifier.togglePower(true),
      onFailure: kTurnOnFailedMessage,
    );
  }

  Future<void> _applyColorSequence(List<List<int>> seq) async {
    final ok = await _sendAdjustment({'col': seq, ..._liveLayout()});
    if (!mounted || !ok) return;
    _syncAcceptedPreview(colors: seq);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wledStateProvider);
    final isConnected = state.connected;
    // +110 E1 follow-up 2: with the house OFF an adjustment changes a look
    // nobody can see, so the sliders read as broken. They are disabled, with
    // the reason and the explicit way on. (Not "an adjustment turns the lights
    // on": the PRIORITY rule is that an adjustment never changes power.)
    final lightsOff = isConnected && !state.isOn;
    final enabled = isConnected && !lightsOff;
    // #91 — gates the LAN-only direction toggle below.
    final onLan = ref.watch(isLanConnectedProvider);
    final directionAwayMessage =
        directionLanOnlyMessage(ref.watch(siteModeProvider));

    // Get effect metadata for context-aware labeling
    final effectMetadata = getEffectMetadata(_effectId ?? state.effectId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lightsOff) LightsOffNotice(onTurnOn: _turnOn),
        IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Speed slider with per-effect profile (hide if effect doesn't use speed)
            if (effectMetadata.usesSpeed) ...[
              EffectSpeedSlider(
                rawSpeed: _speed,
                effectId: _effectId ?? state.effectId,
                initialExtended: getSpeedProfile(_effectId ?? state.effectId)
                    .mapRawToSlider(_speed)
                    .needsExtended,
                onChanged: (raw) {
                  setState(() => _speed = raw);
                  _notifyChanged();
                  _lookPacer.changed();
                },
                onChangeEnd: _lookPacer.settled,
              ),
              const SizedBox(height: 4),
            ],
            // Intensity slider (hide if effect doesn't use intensity or label is null)
            if (effectMetadata.usesIntensity && effectMetadata.intensityLabel != null) ...[
              _SliderRow(
                icon: Icons.tune,
                label: effectMetadata.intensityLabel!,
                value: _intensity.toDouble(),
                min: 0,
                max: 255,
                onChanged: (v) {
                  setState(() => _intensity = v.round().clamp(0, 255));
                  _notifyChanged();
                  _lookPacer.changed();
                },
                onChangeEnd: _lookPacer.settled,
                displayValue: '$_intensity',
              ),
              const SizedBox(height: 10),
            ],
            // Direction toggle. A Wrap, not a Row: on a 390-point phone the
            // label plus the toggle overflowed by 24 points even at default
            // text size (found by the +110 E1 Home tests); now the toggle
            // drops under the label when there is no room.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_horiz,
                        color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 8),
                    Text('Direction',
                        style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('L→R')),
                    ButtonSegment(value: true, label: Text('R→L')),
                  ],
                  // The filled segment already shows the choice; the check
                  // mark only cost width.
                  showSelectedIcon: false,
                  selected: {_reverse},
                  // #91 - LAN-ONLY, disabled not hidden. See the same gate in
                  // pattern_grid_widgets.dart.
                  onSelectionChanged: !onLan ? null : (s) {
                    final rev = s.isNotEmpty ? s.first : false;
                    setState(() => _reverse = rev);
                    _notifyChanged();
                    // Direction is GEOMETRY — provisioning door, not the
                    // debounced look apply (which no longer carries `rev` at
                    // all, and whose door strips it).
                    _applyDirection(rev);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            if (!onLan)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  directionAwayMessage,
                  key: const ValueKey('tune-direction-away'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
            // Effect selector (optional)
            if (widget.showEffectSelector) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: NexGenPalette.cyan, size: 20),
                  const SizedBox(width: 8),
                  Text('Effect', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _effectId != null && _commonEffects.any((e) => e.id == _effectId)
                            ? _effectId
                            : null,
                        // Show effect name from Lumina if available, otherwise show hint
                        hint: Text(
                          widget.effectName ?? 'Select effect',
                          style: TextStyle(color: widget.effectName != null ? Colors.white : Colors.white.withValues(alpha: 0.7)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        dropdownColor: const Color(0xFF1E1E2E),
                        icon: const Icon(Icons.arrow_drop_down, color: NexGenPalette.cyan),
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(12),
                        items: _commonEffects.map((effect) {
                          final wledEffect = WledEffectsCatalog.getById(effect.id);
                          final behavior = wledEffect?.colorBehavior;
                          final behaviorColor = behavior != null ? _colorForBehavior(behavior) : null;
                          return DropdownMenuItem<int>(
                            value: effect.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(effect.icon, size: 18, color: NexGenPalette.cyan),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    effect.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                // Color behavior indicator
                                if (behavior != null) ...[
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message: behavior.description,
                                    child: Icon(
                                      _iconForBehavior(behavior),
                                      size: 14,
                                      color: behaviorColor,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (effectId) {
                          if (effectId == null) return;
                          setState(() => _effectId = effectId);
                          _applyEffect(effectId);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Pixel Layout section (optional)
            if (widget.showPixelLayout) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.grid_view, color: NexGenPalette.cyan, size: 18),
                  const SizedBox(width: 8),
                  Text('Pixel Layout', style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              _SliderRow(
                icon: Icons.blur_on,
                label: 'Grouping',
                value: _grouping.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: (v) {
                  setState(() => _grouping = v.round().clamp(1, 10));
                  _notifyChanged();
                  _layoutPacer.changed();
                },
                onChangeEnd: _layoutPacer.settled,
                displayValue: '$_grouping',
              ),
              const SizedBox(height: 6),
              _SliderRow(
                icon: Icons.space_bar,
                label: 'Spacing',
                value: _spacing.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                onChanged: (v) {
                  setState(() => _spacing = v.round().clamp(0, 10));
                  _notifyChanged();
                  _layoutPacer.changed();
                },
                onChangeEnd: _layoutPacer.settled,
                displayValue: '$_spacing',
              ),
            ],
            // Color Sequence Builder (optional)
            if (widget.showColors && _colors != null && _colors!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.palette, color: NexGenPalette.cyan, size: 18),
                  const SizedBox(width: 8),
                  Text('Color Sequence', style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                // Deduplicate base colors
                final seen = <String>{};
                final baseColors = <List<int>>[];
                for (final rgb in _colors!) {
                  if (rgb.length < 3) continue;
                  final key = '${rgb[0]}-${rgb[1]}-${rgb[2]}';
                  if (seen.add(key)) baseColors.add([rgb[0], rgb[1], rgb[2]]);
                }
                return ColorSequenceBuilder(
                  baseColors: baseColors.isNotEmpty ? baseColors : _colors!,
                  initialSequence: _colors!,
                  onChanged: _applyColorSequence,
                  onCustomized: widget.onCustomized,
                );
              }),
            ],
          ],
        ),
      ),
        ),
      ],
    );
  }
}

/// What "Turn on" says when the lights did not come on.
const String kTurnOnFailedMessage =
    "Couldn't turn your lights on — check your connection.";

/// Shown over adjustment controls while the house is off (+110 E1 follow-up
/// 2): the controls are disabled, this says why, and "Turn on" is the one
/// explicit way on. Shared with the Explore adjustment sheet.
class LightsOffNotice extends StatelessWidget {
  const LightsOffNotice({super.key, required this.onTurnOn});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('tune-lights-off'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.power_settings_new,
              size: 18, color: NexGenPalette.textMedium),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Your lights are off. Turn them on to adjust them.',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('tune-turn-on'),
            onPressed: onTurnOn,
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
  }
}

/// Helper widget for consistent slider rows
class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeEnd;
  final String displayValue;

  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.onChangeEnd,
    required this.displayValue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: NexGenPalette.cyan, size: 20),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: SliderTheme(
            data: Theme.of(context).sliderTheme.copyWith(trackHeight: 4),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd == null ? null : (_) => onChangeEnd!(),
              activeColor: NexGenPalette.cyan,
              inactiveColor: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(displayValue, style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

// Helper functions for color behavior display
IconData _iconForBehavior(ColorBehavior behavior) {
  switch (behavior) {
    case ColorBehavior.usesSelectedColors:
      return Icons.palette_outlined;
    case ColorBehavior.blendsSelectedColors:
      return Icons.gradient;
    case ColorBehavior.generatesOwnColors:
      return Icons.auto_awesome;
    case ColorBehavior.usesPalette:
      return Icons.color_lens_outlined;
  }
}

Color _colorForBehavior(ColorBehavior behavior) {
  switch (behavior) {
    case ColorBehavior.usesSelectedColors:
      return NexGenPalette.cyan;
    case ColorBehavior.blendsSelectedColors:
      return const Color(0xFF64B5F6);
    case ColorBehavior.generatesOwnColors:
      return const Color(0xFFFFB74D);
    case ColorBehavior.usesPalette:
      return const Color(0xFFBA68C8);
  }
}

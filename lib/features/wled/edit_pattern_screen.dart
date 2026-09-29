import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_save_errors.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_design_payload.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/edit_pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/widgets/hsv_wheel_picker.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/widgets/favorite_heart_button.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';
import 'package:nexgen_command/widgets/effect_speed_slider.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/favorites/favorite_brightness.dart';
import 'package:nexgen_command/features/wled/channel_direction.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/wled/pattern_adjustment_pacer.dart';
import 'package:nexgen_command/features/wled/pattern_apply_gate.dart';
import 'package:nexgen_command/features/wled/pattern_flash_safety.dart';
import 'package:nexgen_command/features/wled/pattern_tweak_sender.dart'
    show directionLanOnlyMessage;
import 'package:nexgen_command/features/wled/pattern_editor_design.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:nexgen_command/shared/write_result.dart';

/// Full-screen Edit Pattern screen modeled after the native controller app.
///
/// Provides: pattern name, roofline preview, MODE/DIRECTION/BG COLOR controls,
/// action colors (up to 15 layers), color picker, brightness/speed sliders.
class EditPatternScreen extends ConsumerStatefulWidget {
  final EditablePattern? initialPattern;

  const EditPatternScreen({super.key, this.initialPattern});

  @override
  ConsumerState<EditPatternScreen> createState() => _EditPatternScreenState();
}

class _EditPatternScreenState extends ConsumerState<EditPatternScreen> {
  late TextEditingController _nameController;
  late EditablePattern _pattern;

  /// When a change goes to the lights: a short debounce at home, ONE write
  /// when a drag settles away from home, never two in flight
  /// (pattern_adjustment_pacer.dart — +110 E1 follow-up 4).
  late final AdjustmentPacer _pacer = AdjustmentPacer(
    flush: _sendToWled,
    isRemote: () => ref.read(isRemoteModeProvider),
  );
  int _selectedColorIndex = 0;
  bool _editingBgColor = false;
  int _colorPickerTab = 0; // 0=Common, 1=Picker, 2=Slider

  // RGB slider values for the Slider tab
  double _sliderR = 255;
  double _sliderG = 0;
  double _sliderB = 0;

  // The design this screen last saved, so a repeat Save updates it.
  String? _savedDesignId;
  String? _savedDesignName;
  DateTime? _savedCreatedAt;
  bool _saving = false;

  // Live-apply serialisation (see _sendToWled).
  bool _sending = false;
  bool _resend = false;

  /// Row 43 — the heart's document id, per NAME, minted fresh in this editor.
  ///
  /// The heart used to be keyed by the SOURCE palette's id (`_pattern.id` is
  /// the Explore node the editor was opened from). It showed filled whenever
  /// that palette had ever been favourited, and a tap then DELETED that
  /// favourite; a second heart after a rename refreshed the old document,
  /// whose name the rules keep immutable. Now each distinct name gets its own
  /// fresh id, so hearting "Chiefs Alt" after "Chiefs" is a second favourite
  /// under the new name, and the heart only ever toggles this editor's own.
  final Map<String, String> _favoriteIds = {};
  final String _sessionKey =
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  String _favoriteIdFor(String name) {
    final key = name.trim().toLowerCase();
    return _favoriteIds.putIfAbsent(
        key, () => 'pe_${_sessionKey}_${_favoriteIds.length}');
  }

  /// Item B — true once the customer moved the BRIGHTNESS slider, so a
  /// favourite saved from here states its level on purpose.
  bool _brightnessTouched = false;

  @override
  void initState() {
    super.initState();
    // Show the effect that will actually play: a stored Strobe Mega is
    // retired and plays Strobe, and a strobe never runs above the flash cap
    // (pattern_flash_safety.dart).
    final initial = widget.initialPattern ?? EditablePattern.blank();
    final fx = offeredEffectId(initial.effectId);
    _pattern = fx == initial.effectId &&
            capFlashSpeed(fx, initial.speed) == initial.speed
        ? initial
        : initial.copyWith(effectId: fx, speed: capFlashSpeed(fx, initial.speed));
    _nameController = TextEditingController(text: _pattern.name);

    // Sync slider to first action color
    if (_pattern.actionColors.isNotEmpty) {
      final c = _pattern.actionColors[0];
      _sliderR = c.red.toDouble();
      _sliderG = c.green.toDouble();
      _sliderB = c.blue.toDouble();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pacer.dispose();
    super.dispose();
  }

  /// [dragging]: the change is a step of a drag (a slider, the colour wheel)
  /// — away from home it waits for the drag to settle.
  void _updatePattern(EditablePattern newPattern, {bool dragging = false}) {
    setState(() => _pattern = newPattern);
    _pacer.changed(dragging: dragging);
  }

  void _sendToWledDebounced() => _pacer.changed(dragging: false);

  /// The channels the editor is lighting — what the user is looking at, and
  /// therefore what Save stores. The effective set, or every device channel
  /// when none is selected.
  List<PatternEditorChannel> _targetChannels() {
    final effective = ref.read(effectiveChannelIdsProvider).toSet();
    return [
      for (final c in ref.read(deviceChannelsProvider))
        if (effective.isEmpty || effective.contains(c.id))
          PatternEditorChannel(
            id: c.id,
            name: c.name,
            ledCount: (c.stop - c.start).clamp(0, 100000),
          ),
    ];
  }

  /// The pattern as ONE WLED payload. Right for an animated pattern (a few
  /// hundred bytes). For Static it is the per-LED `i` write, which is only a
  /// fallback — see [_sendToWled].
  Future<Map<String, dynamic>> _currentWledPayload() async {
    final repo = ref.read(wledRepositoryProvider);
    final totalPixels = await repo?.getTotalLedCount() ?? 150;
    return _pattern.toWledPayload(totalPixels);
  }

  /// What the heart stores. Animated: the one WLED payload, as ever. STATIC:
  /// the per-pixel favorite — the SAME design [_saveToMyDesigns] would store
  /// and [_sendStatic] is showing on the lights, so My Favorites re-applies it
  /// through the chunked spine instead of as one message `applyJson` refuses
  /// past 4 KB. (The heart used to decline in Static and point at SAVE.)
  Future<Map<String, dynamic>> _favoritePayload() async {
    // Item B: the level rides along as the customer's only when they set it.
    Map<String, dynamic> stated(Map<String, dynamic> p) =>
        _brightnessTouched ? markFavoriteBrightnessStated(p) : p;
    if (_pattern.effectId != 0) return stated(await _currentWledPayload());
    try {
      return stated(buildPerPixelFavoritePayload(customDesignFromEditablePattern(
        pattern: _pattern,
        name: _pattern.name,
        ownerId: '',
        channels: _targetChannels(),
      )));
    } on StateError {
      throw const FavoriteNotSavable(
          'Connect to your lights to favorite this pattern — it is stored LED '
          'by LED, so the app needs your channel lengths. Nothing was saved.');
    }
  }

  /// STATIC goes through the chunked per-pixel spine, built from the SAME
  /// design Save stores — so the lights show exactly what will be kept.
  ///
  /// It used to be one `applyJson` holding an `i` entry per LED, cloned onto
  /// every targeted channel: 5.4 KB for one 290-LED channel, ~11 KB for two.
  /// `applyJson` refuses anything over 4 KB (WLED itself rejects ~6 KB), and
  /// the refusal was swallowed below — so on any install past ~215 LEDs the
  /// Static preview silently never reached the lights. Bench-confirmed
  /// 2026-09-21. (The only thing that ever lit them was the old "SAVE TO
  /// DEVICE" POST, which had no size guard and no channel filter — segment 0
  /// only, which is why channel 2 stayed dark.)
  Future<bool> _sendStatic() async {
    final channels = [
      for (final c in _targetChannels())
        if (c.ledCount > 0) c,
    ];
    if (channels.isEmpty) return false; // no census → caller falls back
    final design = customDesignFromEditablePattern(
      pattern: _pattern,
      name: _pattern.name,
      ownerId: '',
      channels: channels,
    );
    final result = await applyBaseAndSpansDetailed(
      ref,
      baseRgbw: const [0, 0, 0, 0],
      spansByChannel: customDesignToSpans(design),
      brightness: _pattern.brightness,
    );
    if (!result.isOk) {
      debugPrint('EditPattern static apply: $result');
      return true; // handled (and failed) — do not retry down the legacy path
    }
    if (mounted) _syncPreview();
    return true;
  }

  void _syncPreview() {
    // Drive the dashboard hero preview and Explore hero from the as-sent
    // pattern so navigating home shows the new look immediately, without
    // waiting for the next poll. Also arms poll-overwrite suppression so
    // the just-applied colors don't snap to the device's lossy echo.
    ref.read(wledStateProvider.notifier).applyPreviewSync(
      colors: _pattern.actionColors,
      effectId: _pattern.effectId,
      effectName: _pattern.name,
      speed: _pattern.speed,
      intensity: _pattern.intensity,
      brightness: _pattern.brightness,
      colorGroupSize: _pattern.colorGroupSize,
    );
  }

  Future<void> _sendToWled() async {
    if (ref.read(demoModeProvider)) return;
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;

    // One send at a time: a Static apply is several requests, and a drag on
    // the colour wheel must not interleave two of them on the controller.
    if (_sending) {
      _resend = true;
      return;
    }
    _sending = true;
    try {
      await _sendOnce(repo);
    } finally {
      _sending = false;
    }
    if (_resend && mounted) {
      _resend = false;
      _sendToWledDebounced();
    }
  }

  Future<void> _sendOnce(WledRepository repo) async {
    // The container, not `ref`: the screen can be disposed mid-send, and a
    // dead `ref` throws.
    final container = ProviderScope.containerOf(context, listen: false);
    // Row 1: a closed gate is explained, not skipped in silence.
    final channels = await resolveChannelsForTap(container);
    if (channels == null || !mounted) return;
    final filterChannels = container.read(applyFilterChannelsProvider);
    if (_pattern.effectId == 0 && await _sendStatic()) return;
    if (!mounted) return;

    var payload = await _currentWledPayload();
    payload = applyChannelFilter(payload, channels, filterChannels);
    // A refused write is reported, like every other live control (row 80).
    final result = await container.read(wledStateProvider.notifier).runAndReport(
          repo.applyJson(payload).then(WriteResult.fromBool),
          onFailure: "Your lights didn't take that change — check your "
              'connection and try again.',
        );
    if (!result.ok || !mounted) return;
    _syncPreview();
  }

  /// SAVE — stores the pattern as a design in My Designs
  /// (`/users/{uid}/designs`), through the same [DesignService.saveDesign]
  /// every other design writer uses.
  ///
  /// This used to be "SAVE TO DEVICE": a WLED `psave` into a preset slot in
  /// 100–200 hashed from the SOURCE CARD's id. Nothing in the app could list,
  /// load or delete that range, so the pattern was unfindable the moment the
  /// toast faded; a second variation of the same card overwrote the first; and
  /// a Static pattern stored a black frozen shell, because a WLED preset cannot
  /// hold per-pixel data (explore-palette-save-to-device-audit-2026-09-20).
  /// No device-side preset is written any more — Firestore is the design
  /// source of truth, exactly as for the paint editor.
  ///
  /// Same name as the last save from this screen → UPDATE that design (pressing
  /// Save twice must not fork a copy). A different name → a NEW design, so
  /// renaming is how a second variation is kept. New designs always get a fresh
  /// auto-id and a name no other design is using.
  Future<void> _saveToMyDesigns() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    // Replace, don't queue: a second Save must not sit behind the first toast
    // for four seconds looking like it did nothing.
    void toast(SnackBar bar) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(bar);

    final uid = ref.read(effectiveUserUidProvider);
    if (uid == null) {
      toast(SnackBar(
        content: const Text('Sign in to save designs. Nothing was saved.'),
        backgroundColor: Colors.red.shade800,
      ));
      return;
    }

    final typed = _nameController.text.trim();
    final baseName = typed.isNotEmpty ? typed : 'Custom Pattern';
    final isUpdate = _savedDesignId != null && baseName == _savedDesignName;

    setState(() => _saving = true);
    // A one-shot fetch for the account being saved INTO. `designsStreamProvider`
    // is cold unless some other screen happens to be watching it (so a
    // `ref.read` of it sees nothing), and it follows the signed-in uid rather
    // than the effective one. A name is a nicety: it must never block a save.
    var taken = const <String>[];
    if (!isUpdate) {
      try {
        final existing = await ref.read(designServiceProvider).getDesigns(uid);
        taken = [for (final d in existing) d.name];
      } catch (e) {
        debugPrint('EditPattern save: could not list designs for naming: $e');
      }
    }
    if (!mounted) return;
    final name = isUpdate ? baseName : uniqueDesignName(baseName, taken);

    final channels = _targetChannels();

    final CustomDesign built;
    try {
      // Item C: a palette/effect design — the model the tuner edits and My
      // Designs renders as a pattern card — for everything but a Static
      // pattern with more than three colours (see pattern_editor_design.dart).
      built = designFromPatternEditor(
        pattern: _pattern.copyWith(name: name),
        name: name,
        ownerId: uid,
        channels: channels,
      );
    } on StateError {
      setState(() => _saving = false);
      toast(SnackBar(
        content: const Text(
            'Connect to your lights to save this pattern — it is stored LED '
            'by LED, so the app needs your channel lengths. Nothing was saved.'),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 6),
      ));
      return;
    }
    final design = isUpdate
        ? built.copyWith(id: _savedDesignId, createdAt: _savedCreatedAt)
        : built;

    try {
      final id = await ref.read(designServiceProvider).saveDesign(uid, design);
      _savedDesignId = id;
      _savedDesignName = name;
      _savedCreatedAt = design.createdAt;
      if (!mounted) return;
      if (_nameController.text.trim() != name) _nameController.text = name;
      toast(SnackBar(
        content: Text(isUpdate
            ? 'Updated "$name" in My Designs'
            : 'Saved "$name" to My Designs'),
        backgroundColor: NexGenPalette.gunmetal,
        action: SnackBarAction(
          label: 'VIEW',
          textColor: NexGenPalette.cyan,
          onPressed: () => router.push('/explore/library/my_designs',
              extra: const {'name': 'My Designs'}),
        ),
      ));
    } catch (e, st) {
      // DesignService rethrows. A denied or failed write must LOOK failed.
      debugPrint('EditPattern save failed: $e\n$st');
      if (mounted) {
        toast(SnackBar(
          content: Text(describeDesignSaveError(e, isEdit: isUpdate)),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 7),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Edit Pattern'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Tooltip(
            message: 'Save to My Designs',
            child: TextButton(
              onPressed: _saving ? null : _saveToMyDesigns,
              // No vertical padding: at Larger Text the default padding left
              // SAVE taller than the button inside the app bar.
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'SAVE',
                      style: TextStyle(
                        color: NexGenPalette.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Channel/Area selector for multi-segment devices
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ChannelSelectorBar(),
            ),
            // Pattern name
            _buildPatternNameField(),
            // Roofline preview
            _buildPreview(),
            const SizedBox(height: 16),
            // MODE / DIRECTION / BG COLOR
            _buildModeDirectionBgRow(),
            const SizedBox(height: 16),
            // Action Colors
            _buildActionColorsSection(),
            const SizedBox(height: 12),
            // Color Picker
            _buildColorPickerSection(),
            const SizedBox(height: 16),
            // Brightness & Speed sliders
            _buildBrightnessSlider(),
            _buildSpeedSlider(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pattern Name Field
  // ---------------------------------------------------------------------------
  Widget _buildPatternNameField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PATTERN NAME',
            style: TextStyle(
              color: NexGenPalette.textSecondary,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            // Keep the model's name in step with the field. It never was, so
            // the favorite heart saved the SOURCE CARD's name whatever had
            // been typed. Deliberately not `_updatePattern`: a rename is not
            // a look, and must not re-send the pattern to the lights.
            onChanged: (v) =>
                setState(() => _pattern = _pattern.copyWith(name: v.trim())),
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: NexGenPalette.gunmetal90,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: NexGenPalette.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: NexGenPalette.line),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Roofline Preview
  // ---------------------------------------------------------------------------
  Widget _buildPreview() {
    final houseImageUrl = ref.watch(currentUserProfileProvider).maybeWhen(
      data: (u) => u?.housePhotoUrl,
      orElse: () => null,
    );
    final hasCustomImage = houseImageUrl != null && houseImageUrl.isNotEmpty;

    return Container(
      height: 180,
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

            // Gradient overlay
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
                    previewColors: _pattern.actionColors,
                    previewEffectId: _pattern.effectId,
                    previewSpeed: _pattern.speed,
                    brightness: _pattern.brightness,
                    forceOn: true,
                    // Row 95: only where the lights show one.
                    backgroundColor: _pattern.backgroundApplies
                        ? _pattern.backgroundColor
                        : const Color(0xFF000000),
                    colorGroupSize: _pattern.colorGroupSize,
                    targetAspectRatio: constraints.maxWidth / constraints.maxHeight,
                    useBoxFitCover: true,
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
  // MODE / DIRECTION / BG COLOR Row
  // ---------------------------------------------------------------------------
  Widget _buildModeDirectionBgRow() {
    final effectName = WledEffectsCatalog.getName(_pattern.effectId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // MODE
          Expanded(
            child: _ControlCard(
              label: 'MODE',
              icon: Icons.auto_awesome,
              value: effectName,
              onTap: () => _showModeSelector(),
            ),
          ),
          const SizedBox(width: 10),
          // DIRECTION — row 94. It cycled a label (Left / Right / Center) and
          // nothing else: the payload never carried it and Save dropped it.
          // It is now Left ↔ Right, sent through the direction door the Home
          // Tune panel uses (home Wi-Fi only), and Save stores it.
          Expanded(
            child: _ControlCard(
              key: const ValueKey('edit-pattern-direction'),
              label: 'DIRECTION',
              icon: _pattern.direction == PatternDirection.centerOut
                  ? PatternDirection.right.icon
                  : _pattern.direction.icon,
              value: _pattern.direction == PatternDirection.centerOut
                  ? PatternDirection.right.displayName
                  : _pattern.direction.displayName,
              onTap: _toggleDirection,
            ),
          ),
          // BG COLOR — row 95. Shown only where a background reaches the
          // lights (EditablePattern.backgroundApplies); elsewhere the preview
          // painted a background the lights never showed and Save dropped.
          if (_pattern.backgroundApplies) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _ControlCard(
              key: const ValueKey('edit-pattern-bg-color'),
              label: 'BG COLOR',
              customIcon: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _pattern.backgroundColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: NexGenPalette.line, width: 1.5),
                ),
              ),
              value: _pattern.backgroundColor == const Color(0xFF000000)
                  ? 'Black'
                  : 'Custom',
              onTap: () {
                setState(() {
                  _editingBgColor = true;
                  _sliderR = _pattern.backgroundColor.red.toDouble();
                  _sliderG = _pattern.backgroundColor.green.toDouble();
                  _sliderB = _pattern.backgroundColor.blue.toDouble();
                });
              },
            ),
          ),
          ],
        ],
      ),
    );
  }

  /// Row 94 — Left ↔ Right, live through the direction door. A refusal (away
  /// from home, demo, a controller that did not take it) flips the card back
  /// and says why, like the Home Tune panel's toggle (row 81).
  Future<void> _toggleDirection() async {
    final from = _pattern.direction;
    final to = from.next;
    setState(() => _pattern = _pattern.copyWith(direction: to));
    final container = ProviderScope.containerOf(context, listen: false);
    final notifier = container.read(wledStateProvider.notifier);
    if (container.read(demoModeProvider)) return; // no device to turn
    final channels = await resolveEffectiveChannelIds(container.read);
    final WriteResult result;
    if (channels.isEmpty) {
      result = WriteResult.blocked(
          applyBlockedReason(container.read) ?? kApplyBlockedFallback);
    } else if (!container.read(isLanConnectedProvider)) {
      result = WriteResult.failed(WriteFailureKind.unsupported,
          message: directionLanOnlyMessage(container.read(siteModeProvider)));
    } else {
      final ok = await applyChannelDirection(
        repo: container.read(wledRepositoryProvider),
        channelIds: channels,
        reverse: to.reverse,
      );
      result = ok
          ? const WriteResult.success()
          : const WriteResult.failed(WriteFailureKind.unsupported,
              message: "Direction couldn't be changed — your lights didn't "
                  'take it.');
    }
    final reported = await notifier.runAndReport(Future.value(result),
        onFailure: "Direction couldn't be changed.");
    if (!mounted || reported.ok) return;
    setState(() => _pattern = _pattern.copyWith(direction: from));
  }

  void _showModeSelector() {
    final effectsByMood = WledEffectsCatalog.effectsBySelectorMood;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.matteBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: NexGenPalette.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Lighting Effects',
                    style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: SelectorMood.values.map((mood) {
                      final effects = effectsByMood[mood] ?? [];
                      if (effects.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 6),
                            child: Text(
                              '${mood.icon} ${mood.displayName}',
                              style: TextStyle(
                                color: NexGenPalette.textMedium,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          ...effects.map((effect) {
                            final isSelected = effect.id == _pattern.effectId;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: NexGenPalette.cyan.withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              leading: Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: isSelected ? NexGenPalette.cyan : NexGenPalette.textSecondary,
                                size: 20,
                              ),
                              title: Text(
                                effect.name,
                                style: TextStyle(
                                  color: isSelected ? NexGenPalette.cyan : NexGenPalette.textHigh,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                              onTap: () {
                                // Item D: a newly chosen MODE starts at its
                                // curated roofline speed; the slider stays
                                // free above and below it.
                                _updatePattern(_pattern.copyWith(
                                  effectId: effect.id,
                                  speed: effectDefaultSpeedOr(
                                      effect.id, _pattern.speed),
                                  intensity: effectDefaultIntensity(effect.id),
                                ));
                                // BG COLOR may stop applying (row 95).
                                if (!_pattern.backgroundApplies) {
                                  setState(() => _editingBgColor = false);
                                }
                                Navigator.of(context).pop();
                              },
                            );
                          }),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Action Colors Section
  // ---------------------------------------------------------------------------
  Widget _buildActionColorsSection() {
    final colors = _pattern.actionColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Action Colors',
                style: TextStyle(
                  color: NexGenPalette.textHigh,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Current selected color preview
              if (colors.isNotEmpty && _selectedColorIndex < colors.length)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _editingBgColor
                        ? _pattern.backgroundColor
                        : colors[_selectedColorIndex],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: NexGenPalette.cyan, width: 2),
                  ),
                ),
              const SizedBox(width: 8),
              // Add button
              if (colors.length < EditablePattern.maxActionColors)
                GestureDetector(
                  onTap: () {
                    final newColors = List<Color>.from(colors)..add(Colors.white);
                    _updatePattern(_pattern.copyWith(actionColors: newColors));
                    setState(() {
                      _selectedColorIndex = newColors.length - 1;
                      _editingBgColor = false;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: NexGenPalette.gunmetal,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: NexGenPalette.line),
                    ),
                    child: const Icon(Icons.add, size: 18, color: Colors.white70),
                  ),
                ),
              const SizedBox(width: 8),
              // Delete button
              if (colors.length > 1)
                GestureDetector(
                  onTap: () {
                    if (_selectedColorIndex >= colors.length) return;
                    final newColors = List<Color>.from(colors)
                      ..removeAt(_selectedColorIndex);
                    final newIndex = _selectedColorIndex.clamp(0, newColors.length - 1);
                    _updatePattern(_pattern.copyWith(actionColors: newColors));
                    setState(() {
                      _selectedColorIndex = newIndex;
                      _editingBgColor = false;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: NexGenPalette.gunmetal,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: NexGenPalette.line),
                    ),
                    child: const Icon(Icons.delete_outline, size: 18, color: Colors.white70),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${colors.length}/${EditablePattern.maxActionColors} Layers',
            style: TextStyle(
              color: NexGenPalette.textSecondary,
              fontSize: 12,
            ),
          ),
          // A WLED effect has three colour slots, so an animated MODE shows
          // — and saves as its look — only the first three layers. The screen
          // used to offer 15 and say nothing. Static lights every LED
          // individually and uses them all.
          if (_pattern.hasLayersBeyondEffectSlots)
            Padding(
              key: const ValueKey('edit-pattern-effect-slot-hint'),
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Animated modes use the first '
                '${EditablePattern.maxEffectColors} colors. Set MODE to '
                '${WledEffectsCatalog.getName(0)} to use all ${colors.length}.',
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          // Color chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(colors.length, (i) {
              final isSelected = i == _selectedColorIndex && !_editingBgColor;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedColorIndex = i;
                    _editingBgColor = false;
                    _sliderR = colors[i].red.toDouble();
                    _sliderG = colors[i].green.toDouble();
                    _sliderB = colors[i].blue.toDouble();
                  });
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
                      width: isSelected ? 2.5 : 1,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Color Picker Section (tabs: Common, Picker, Slider)
  // ---------------------------------------------------------------------------
  Widget _buildColorPickerSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: [
          // Tab bar + heart. The tabs wrap: in one Row they ran 137 points off
          // the card at Larger Text (+110 E1 accessibility).
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _ColorPickerTabButton(
                      label: 'Common Color',
                      isActive: _colorPickerTab == 0,
                      onTap: () => setState(() => _colorPickerTab = 0),
                    ),
                    _ColorPickerTabButton(
                      label: 'Color Picker',
                      isActive: _colorPickerTab == 1,
                      onTap: () => setState(() => _colorPickerTab = 1),
                    ),
                    _ColorPickerTabButton(
                      label: 'Slider',
                      isActive: _colorPickerTab == 2,
                      onTap: () => setState(() => _colorPickerTab = 2),
                    ),
                  ],
                ),
              ),
              // Heart button
              FavoriteHeartButton(
                patternId: _favoriteIdFor(_pattern.name),
                patternName: _pattern.name,
                patternDataBuilder: _favoritePayload,
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Tab content
          if (_colorPickerTab == 0) _buildCommonColorsGrid(),
          if (_colorPickerTab == 1) _buildHsvPicker(),
          if (_colorPickerTab == 2) _buildRgbSliders(),
        ],
      ),
    );
  }

  Widget _buildCommonColorsGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: PresetColors.all.map((preset) {
        return GestureDetector(
          onTap: () => _applyColor(preset.color),
          child: Container(
            width: 56,
            height: 40,
            decoration: BoxDecoration(
              color: preset.color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Center(
              child: Text(
                preset.label,
                style: TextStyle(
                  color: _textColorFor(preset.color),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _currentEditingColor() {
    if (_editingBgColor) return _pattern.backgroundColor;
    if (_selectedColorIndex < _pattern.actionColors.length) {
      return _pattern.actionColors[_selectedColorIndex];
    }
    return Colors.white;
  }

  /// "Color Picker" tab — the app's own colour WHEEL plus one brightness
  /// control ([HsvWheelPicker]). It used to be a hue bar + Sat + Val sliders
  /// under a tab labelled "Color Picker", which also lost the hue whenever
  /// saturation or value touched 0 (HSV re-derived from RGB every build).
  Widget _buildHsvPicker() {
    return HsvWheelPicker(
      key: const ValueKey('edit-pattern-color-wheel'),
      color: _currentEditingColor(),
      onChanged: (c) => _applyColor(c, dragging: true),
    );
  }

  Widget _buildRgbSliders() {
    return Column(
      children: [
        _buildColorSlider('R', _sliderR, Colors.red, (v) {
          setState(() => _sliderR = v);
          _applyColor(Color.fromARGB(255, v.round(), _sliderG.round(), _sliderB.round()), dragging: true);
        }),
        const SizedBox(height: 8),
        _buildColorSlider('G', _sliderG, Colors.green, (v) {
          setState(() => _sliderG = v);
          _applyColor(Color.fromARGB(255, _sliderR.round(), v.round(), _sliderB.round()), dragging: true);
        }),
        const SizedBox(height: 8),
        _buildColorSlider('B', _sliderB, Colors.blue, (v) {
          setState(() => _sliderB = v);
          _applyColor(Color.fromARGB(255, _sliderR.round(), _sliderG.round(), v.round()), dragging: true);
        }),
      ],
    );
  }

  Widget _buildColorSlider(String label, double value, Color trackColor, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label, style: TextStyle(color: trackColor, fontWeight: FontWeight.w600))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: trackColor,
              inactiveTrackColor: trackColor.withValues(alpha: 0.2),
              thumbColor: trackColor,
              trackHeight: 6,
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 255,
              onChanged: onChanged,
              onChangeEnd: (_) => _pacer.settled(),
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${value.round()}', textAlign: TextAlign.right, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
        ),
      ],
    );
  }


  void _applyColor(Color color, {bool dragging = false}) {
    if (_editingBgColor) {
      _updatePattern(_pattern.copyWith(backgroundColor: color),
          dragging: dragging);
    } else if (_selectedColorIndex < _pattern.actionColors.length) {
      final newColors = List<Color>.from(_pattern.actionColors);
      newColors[_selectedColorIndex] = color;
      _updatePattern(_pattern.copyWith(actionColors: newColors),
          dragging: dragging);
    }
    // Sync RGB sliders
    setState(() {
      _sliderR = color.red.toDouble();
      _sliderG = color.green.toDouble();
      _sliderB = color.blue.toDouble();
    });
  }

  // ---------------------------------------------------------------------------
  // Brightness & Speed Sliders
  // ---------------------------------------------------------------------------
  Widget _buildBrightnessSlider() {
    return _buildParameterSlider(
      icon: Icons.wb_sunny_outlined,
      label: 'BRIGHTNESS',
      value: _pattern.brightness.toDouble(),
      max: 255,
      displayValue: '${(_pattern.brightness / 255 * 100).round()}%',
      onChanged: (v) {
        _brightnessTouched = true;
        _updatePattern(_pattern.copyWith(brightness: v.round()),
            dragging: true);
      },
    );
  }

  Widget _buildSpeedSlider() {
    return EffectSpeedSlider(
      rawSpeed: _pattern.speed,
      effectId: _pattern.effectId,
      initialExtended: getSpeedProfile(_pattern.effectId)
          .mapRawToSlider(_pattern.speed)
          .needsExtended,
      onChanged: (raw) =>
          _updatePattern(_pattern.copyWith(speed: raw), dragging: true),
      onChangeEnd: _pacer.settled,
    );
  }

  Widget _buildParameterSlider({
    required IconData icon,
    required String label,
    required double value,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: NexGenPalette.cyan, size: 22),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
              const Spacer(),
              Text(displayValue, style: TextStyle(color: NexGenPalette.textHigh, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: NexGenPalette.cyan,
              inactiveTrackColor: NexGenPalette.trackDark,
              thumbColor: NexGenPalette.cyan,
              overlayColor: NexGenPalette.cyan.withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: 0,
              max: max,
              onChanged: onChanged,
              onChangeEnd: (_) => _pacer.settled(),
            ),
          ),
        ],
      ),
    );
  }

  /// Determine text color for legibility against a background color.
  Color _textColorFor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.4 ? Colors.black : Colors.white;
  }
}

// =============================================================================
// Helper Widgets
// =============================================================================

/// A tappable control card for MODE, DIRECTION, BG COLOR.
class _ControlCard extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Widget? customIcon;
  final String value;
  final VoidCallback onTap;

  const _ControlCard({
    super.key,
    required this.label,
    this.icon,
    this.customIcon,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: NexGenPalette.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            if (customIcon != null)
              customIcon!
            else
              Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab button for the color picker section.
class _ColorPickerTabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ColorPickerTabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? NexGenPalette.cyan : NexGenPalette.textSecondary,
          fontSize: 13,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
    );
  }
}

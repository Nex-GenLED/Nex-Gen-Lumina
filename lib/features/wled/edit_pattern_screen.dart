import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/edit_pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/widgets/favorite_heart_button.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';

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
  Timer? _debounceTimer;
  int _selectedColorIndex = 0;
  bool _editingBgColor = false;
  int _colorPickerTab = 0; // 0=Common, 1=Picker, 2=Slider

  // RGB slider values for the Slider tab
  double _sliderR = 255;
  double _sliderG = 0;
  double _sliderB = 0;

  @override
  void initState() {
    super.initState();
    _pattern = widget.initialPattern ?? EditablePattern.blank();
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
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _updatePattern(EditablePattern newPattern) {
    setState(() => _pattern = newPattern);
    _sendToWledDebounced();
  }

  void _sendToWledDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      _sendToWled();
    });
  }

  Future<void> _sendToWled() async {
    if (ref.read(demoModeProvider)) return;
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;

    final totalPixels = await repo.getTotalLedCount() ?? 150;
    final payload = _pattern.toWledPayload(totalPixels);
    await repo.applyJson(payload);
  }

  Future<void> _savePattern() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    final updatedPattern = _pattern.copyWith(name: _nameController.text.trim());

    try {
      await FirebaseFirestore.instance
          .doc('users/${user.uid}/patterns/${updatedPattern.id}')
          .set(updatedPattern.toJson(), SetOptions(merge: true));

      // Also save as WLED preset if possible
      final repo = ref.read(wledRepositoryProvider);
      if (repo != null) {
        final totalPixels = await repo.getTotalLedCount() ?? 150;
        await repo.savePreset(
          presetId: updatedPattern.id.hashCode.abs() % 250 + 1,
          state: updatedPattern.toWledPayload(totalPixels),
          presetName: updatedPattern.name,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: ${updatedPattern.name}'),
            backgroundColor: NexGenPalette.gunmetal,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
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
          TextButton(
            onPressed: _savePattern,
            child: Text(
              'SAVE',
              style: TextStyle(
                color: NexGenPalette.cyan,
                fontWeight: FontWeight.w700,
                fontSize: 15,
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
                    backgroundColor: _pattern.backgroundColor,
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
          // DIRECTION
          Expanded(
            child: _ControlCard(
              label: 'DIRECTION',
              icon: _pattern.direction.icon,
              value: _pattern.direction.displayName,
              onTap: () {
                _updatePattern(_pattern.copyWith(direction: _pattern.direction.next));
              },
            ),
          ),
          const SizedBox(width: 10),
          // BG COLOR
          Expanded(
            child: _ControlCard(
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
      ),
    );
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
                                _updatePattern(_pattern.copyWith(effectId: effect.id));
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
          // Tab bar + heart
          Row(
            children: [
              _ColorPickerTabButton(
                label: 'Common Color',
                isActive: _colorPickerTab == 0,
                onTap: () => setState(() => _colorPickerTab = 0),
              ),
              const SizedBox(width: 8),
              _ColorPickerTabButton(
                label: 'Color Picker',
                isActive: _colorPickerTab == 1,
                onTap: () => setState(() => _colorPickerTab = 1),
              ),
              const SizedBox(width: 8),
              _ColorPickerTabButton(
                label: 'Slider',
                isActive: _colorPickerTab == 2,
                onTap: () => setState(() => _colorPickerTab = 2),
              ),
              const Spacer(),
              // Heart button
              FavoriteHeartButton(
                patternId: _pattern.id,
                patternName: _pattern.name,
                patternData: _pattern.toJson(),
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

  Widget _buildHsvPicker() {
    // Get the current editing color
    Color currentColor;
    if (_editingBgColor) {
      currentColor = _pattern.backgroundColor;
    } else if (_selectedColorIndex < _pattern.actionColors.length) {
      currentColor = _pattern.actionColors[_selectedColorIndex];
    } else {
      currentColor = Colors.white;
    }

    final hsv = HSVColor.fromColor(currentColor);

    return Column(
      children: [
        // Hue bar
        SizedBox(
          height: 32,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              trackHeight: 28,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        colors: List.generate(
                          7,
                          (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
                        ),
                      ),
                    ),
                  ),
                ),
                Slider(
                  value: hsv.hue,
                  min: 0,
                  max: 360,
                  onChanged: (v) {
                    final newColor = HSVColor.fromAHSV(1, v, hsv.saturation, hsv.value).toColor();
                    _applyColor(newColor);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Saturation + Value in a row
        Row(
          children: [
            Expanded(
              child: _buildSmallSlider('Sat', hsv.saturation, (v) {
                final newColor = HSVColor.fromAHSV(1, hsv.hue, v, hsv.value).toColor();
                _applyColor(newColor);
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSmallSlider('Val', hsv.value, (v) {
                final newColor = HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, v).toColor();
                _applyColor(newColor);
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRgbSliders() {
    return Column(
      children: [
        _buildColorSlider('R', _sliderR, Colors.red, (v) {
          setState(() => _sliderR = v);
          _applyColor(Color.fromARGB(255, v.round(), _sliderG.round(), _sliderB.round()));
        }),
        const SizedBox(height: 8),
        _buildColorSlider('G', _sliderG, Colors.green, (v) {
          setState(() => _sliderG = v);
          _applyColor(Color.fromARGB(255, _sliderR.round(), v.round(), _sliderB.round()));
        }),
        const SizedBox(height: 8),
        _buildColorSlider('B', _sliderB, Colors.blue, (v) {
          setState(() => _sliderB = v);
          _applyColor(Color.fromARGB(255, _sliderR.round(), _sliderG.round(), v.round()));
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
            child: Slider(value: value, min: 0, max: 255, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${value.round()}', textAlign: TextAlign.right, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildSmallSlider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 11)),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: NexGenPalette.cyan,
            inactiveTrackColor: NexGenPalette.trackDark,
            thumbColor: NexGenPalette.cyan,
            trackHeight: 4,
          ),
          child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
        ),
      ],
    );
  }

  void _applyColor(Color color) {
    if (_editingBgColor) {
      _updatePattern(_pattern.copyWith(backgroundColor: color));
    } else if (_selectedColorIndex < _pattern.actionColors.length) {
      final newColors = List<Color>.from(_pattern.actionColors);
      newColors[_selectedColorIndex] = color;
      _updatePattern(_pattern.copyWith(actionColors: newColors));
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
      onChanged: (v) => _updatePattern(_pattern.copyWith(brightness: v.round())),
    );
  }

  Widget _buildSpeedSlider() {
    return _buildParameterSlider(
      icon: Icons.bolt,
      label: 'SPEED',
      value: _pattern.speed.toDouble(),
      max: 255,
      displayValue: '${(_pattern.speed / 255 * 10).round()}',
      onChanged: (v) => _updatePattern(_pattern.copyWith(speed: v.round())),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/whites/white_preset_models.dart';
import 'package:nexgen_command/features/whites/white_preference_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// Onboarding step: select preferred primary & complement white.
/// Also used from Settings → My Whites for editing preferences.
class PreferredWhiteSelectionPage extends ConsumerStatefulWidget {
  /// When true, shows "Skip" option and navigates forward on complete.
  /// When false, shows back button and pops on save (settings mode).
  final bool isOnboarding;

  /// Called when the user finishes selection (onboarding mode only).
  final VoidCallback? onComplete;

  const PreferredWhiteSelectionPage({
    super.key,
    this.isOnboarding = false,
    this.onComplete,
  });

  @override
  ConsumerState<PreferredWhiteSelectionPage> createState() => _PreferredWhiteSelectionPageState();
}

class _PreferredWhiteSelectionPageState extends ConsumerState<PreferredWhiteSelectionPage> {
  late WhitePreset _selectedPrimary;
  late WhitePreset _selectedComplement;
  bool _showComplementPicker = false;
  bool _saving = false;
  bool _customPrimaryMode = false;
  bool _customComplementMode = false;

  // Custom RGBW sliders
  late int _customR, _customG, _customB, _customW;
  late String _customName;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final primary = ref.read(preferredWhitePrimaryProvider);
    final complement = ref.read(preferredWhiteComplementProvider);
    _selectedPrimary = primary;
    _selectedComplement = complement;
    _customR = 200;
    _customG = 200;
    _customB = 180;
    _customW = 240;
    _customName = '';
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _selectPrimary(WhitePreset preset) {
    setState(() {
      _selectedPrimary = preset;
      _selectedComplement = suggestComplement(preset);
      _showComplementPicker = true;
      _customPrimaryMode = false;
    });
    _livePreview(preset);
  }

  void _selectComplement(WhitePreset preset) {
    setState(() {
      _selectedComplement = preset;
      _customComplementMode = false;
    });
    _livePreview(preset);
  }

  void _livePreview(WhitePreset preset) {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;
    try {
      repo.applyJson(preset.toWledPayload());
    } catch (e) {
      debugPrint('Error in white preset live preview: $e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await saveWhitePreferences(
        primary: _selectedPrimary,
        complement: _selectedComplement,
        ref: ref,
      );
      if (!mounted) return;
      if (widget.isOnboarding) {
        widget.onComplete?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('White preferences saved')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(widget.isOnboarding ? 'Your White' : 'My Whites'),
        actions: widget.isOnboarding
            ? [
                TextButton(
                  onPressed: () => widget.onComplete?.call(),
                  child: Text('Skip', style: TextStyle(color: NexGenPalette.textMedium)),
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              widget.isOnboarding ? "How do you like your whites?" : "Primary White",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isOnboarding
                  ? "Most homes run white lighting daily \u2014 let's make sure yours looks exactly right."
                  : "Tap a swatch to preview on your lights.",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: NexGenPalette.textMedium,
                  ),
            ),
            const SizedBox(height: 24),

            // Primary selection swatches
            _buildSwatchGrid(
              selected: _selectedPrimary,
              onSelect: _selectPrimary,
              isCustomMode: _customPrimaryMode,
              onCustomToggle: () {
                setState(() {
                  _customPrimaryMode = !_customPrimaryMode;
                  if (_customPrimaryMode) {
                    _customR = _selectedPrimary.r;
                    _customG = _selectedPrimary.g;
                    _customB = _selectedPrimary.b;
                    _customW = _selectedPrimary.w;
                    _customName = _selectedPrimary.name;
                    _nameController.text = _customName;
                  }
                });
              },
              onCustomApply: () {
                final custom = WhitePreset(
                  id: 'custom_primary',
                  name: _nameController.text.trim().isEmpty ? 'My White' : _nameController.text.trim(),
                  r: _customR,
                  g: _customG,
                  b: _customB,
                  w: _customW,
                );
                _selectPrimary(custom);
              },
            ),

            // Custom RGBW editor for primary
            if (_customPrimaryMode) ...[
              const SizedBox(height: 16),
              _buildCustomEditor(isPrimary: true),
            ],

            // Complement section
            if (_showComplementPicker || !widget.isOnboarding) ...[
              const SizedBox(height: 32),
              const Divider(color: NexGenPalette.line),
              const SizedBox(height: 16),
              Text(
                widget.isOnboarding
                    ? "Want a second white always available?"
                    : "Complement White",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: NexGenPalette.textHigh,
                    ),
              ),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.textMedium),
                  children: [
                    const TextSpan(text: 'Suggested: '),
                    TextSpan(
                      text: suggestComplement(_selectedPrimary).name,
                      style: TextStyle(color: NexGenPalette.cyan, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSwatchGrid(
                selected: _selectedComplement,
                onSelect: _selectComplement,
                isCustomMode: _customComplementMode,
                onCustomToggle: () {
                  setState(() {
                    _customComplementMode = !_customComplementMode;
                    if (_customComplementMode) {
                      _customR = _selectedComplement.r;
                      _customG = _selectedComplement.g;
                      _customB = _selectedComplement.b;
                      _customW = _selectedComplement.w;
                      _customName = _selectedComplement.name;
                      _nameController.text = _customName;
                    }
                  });
                },
                onCustomApply: () {
                  final custom = WhitePreset(
                    id: 'custom_complement',
                    name: _nameController.text.trim().isEmpty ? 'My Complement' : _nameController.text.trim(),
                    r: _customR,
                    g: _customG,
                    b: _customB,
                    w: _customW,
                  );
                  _selectComplement(custom);
                },
              ),
              if (_customComplementMode) ...[
                const SizedBox(height: 16),
                _buildCustomEditor(isPrimary: false),
              ],
            ],

            const SizedBox(height: 32),

            // Save / Continue button
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.isOnboarding ? 'Continue' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwatchGrid({
    required WhitePreset selected,
    required ValueChanged<WhitePreset> onSelect,
    required bool isCustomMode,
    required VoidCallback onCustomToggle,
    required VoidCallback onCustomApply,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final preset in kWhitePresets)
          _WhiteSwatchCard(
            preset: preset,
            isSelected: !isCustomMode && selected.id == preset.id,
            onTap: () => onSelect(preset),
          ),
        // Custom option
        _CustomSwatchCard(
          isActive: isCustomMode,
          onTap: onCustomToggle,
        ),
      ],
    );
  }

  Widget _buildCustomEditor({required bool isPrimary}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name field
          TextField(
            controller: _nameController,
            style: TextStyle(color: NexGenPalette.textHigh),
            decoration: InputDecoration(
              labelText: 'Name your white',
              hintText: isPrimary ? 'e.g., Porch White' : 'e.g., Sunday Evening',
              labelStyle: TextStyle(color: NexGenPalette.textMedium),
              hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: NexGenPalette.line),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: NexGenPalette.cyan),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Preview swatch
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Color.fromARGB(
                  255,
                  (_customR + (_customW * 255 / 255)).clamp(0, 255).toInt(),
                  (_customG + (_customW * 235 / 255)).clamp(0, 255).toInt(),
                  (_customB + (_customW * 200 / 255)).clamp(0, 255).toInt(),
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Color.fromARGB(60, _customR, _customG, _customB),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // RGBW sliders
          _buildSlider('R', _customR, Colors.red, (v) {
            setState(() => _customR = v.round());
            _previewCustom();
          }),
          _buildSlider('G', _customG, Colors.green, (v) {
            setState(() => _customG = v.round());
            _previewCustom();
          }),
          _buildSlider('B', _customB, Colors.blue, (v) {
            setState(() => _customB = v.round());
            _previewCustom();
          }),
          _buildSlider('W', _customW, Colors.white, (v) {
            setState(() => _customW = v.round());
            _previewCustom();
          }),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                final repo = ref.read(wledRepositoryProvider);
                if (repo != null) {
                  repo.applyJson(WhitePreset(
                    id: 'custom_preview',
                    name: 'Preview',
                    r: _customR,
                    g: _customG,
                    b: _customB,
                    w: _customW,
                  ).toWledPayload());
                }
                if (isPrimary) {
                  final custom = WhitePreset(
                    id: 'custom_primary',
                    name: _nameController.text.trim().isEmpty ? 'My White' : _nameController.text.trim(),
                    r: _customR,
                    g: _customG,
                    b: _customB,
                    w: _customW,
                  );
                  setState(() {
                    _selectedPrimary = custom;
                    _selectedComplement = suggestComplement(custom);
                    _showComplementPicker = true;
                    _customPrimaryMode = false;
                  });
                } else {
                  final custom = WhitePreset(
                    id: 'custom_complement',
                    name: _nameController.text.trim().isEmpty ? 'My Complement' : _nameController.text.trim(),
                    r: _customR,
                    g: _customG,
                    b: _customB,
                    w: _customW,
                  );
                  setState(() {
                    _selectedComplement = custom;
                    _customComplementMode = false;
                  });
                }
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: NexGenPalette.cyan),
              ),
              child: Text('Apply Custom White', style: TextStyle(color: NexGenPalette.cyan)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, int value, Color color, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: color.withValues(alpha: 0.7),
              inactiveTrackColor: color.withValues(alpha: 0.15),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.1),
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
          width: 36,
          child: Text('$value', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12), textAlign: TextAlign.right),
        ),
      ],
    );
  }

  void _previewCustom() {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;
    try {
      repo.applyJson(WhitePreset(
        id: 'custom_preview',
        name: 'Preview',
        r: _customR,
        g: _customG,
        b: _customB,
        w: _customW,
      ).toWledPayload());
    } catch (e) {
      debugPrint('Error in custom white preview: $e');
    }
  }
}

class _WhiteSwatchCard extends StatelessWidget {
  final WhitePreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  const _WhiteSwatchCard({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final previewColor = preset.previewColor;
    final textColor = previewColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: (MediaQuery.of(context).size.width - 40 - 24) / 3, // 3 per row with spacing
        height: 90,
        decoration: BoxDecoration(
          color: previewColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? NexGenPalette.cyan : Colors.white24,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: NexGenPalette.cyan.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : [
                  BoxShadow(
                    color: previewColor.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Stack(
          children: [
            // Check mark
            if (isSelected)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Colors.black),
                ),
              ),
            // Label
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Text(
                preset.name,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomSwatchCard extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _CustomSwatchCard({
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: (MediaQuery.of(context).size.width - 40 - 24) / 3,
        height: 90,
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? NexGenPalette.cyan : NexGenPalette.line,
            width: isActive ? 2.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.tune_rounded,
              color: isActive ? NexGenPalette.cyan : NexGenPalette.textMedium,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              'Custom',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isActive ? NexGenPalette.cyan : NexGenPalette.textMedium,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

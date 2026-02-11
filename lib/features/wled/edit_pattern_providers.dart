import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';

/// The pattern currently being edited in the Edit Pattern screen.
/// Set when entering the screen, cleared on exit.
final editPatternProvider = StateProvider<EditablePattern?>((ref) => null);

/// Index of the currently selected action color in the color picker.
/// This determines which color chip is highlighted and which color
/// gets updated when the user picks a new color.
final selectedActionColorIndexProvider = StateProvider<int>((ref) => 0);

/// Whether the background color picker is currently visible/active.
/// When true, the color picker edits the BG color instead of an action color.
final editingBgColorProvider = StateProvider<bool>((ref) => false);

/// Currently active color picker tab index (0 = Common, 1 = Picker, 2 = Slider).
final colorPickerTabProvider = StateProvider<int>((ref) => 0);

/// Common preset colors for the "Common Color" tab.
/// Matches the native app's quick-pick grid: PW, CW, WW, then numbered colors.
class PresetColors {
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color coolWhite = Color(0xFFE0E8FF);
  static const Color warmWhite = Color(0xFFFFE4B5);

  static const List<PresetColor> all = [
    PresetColor('PW', pureWhite),
    PresetColor('CW', coolWhite),
    PresetColor('WW', warmWhite),
    PresetColor('1', Color(0xFFFF0000)),   // Red
    PresetColor('2', Color(0xFF00FF00)),   // Green
    PresetColor('3', Color(0xFF0000FF)),   // Blue
    PresetColor('4', Color(0xFFFF8C00)),   // Orange
    PresetColor('5', Color(0xFF00E5FF)),   // Cyan
    PresetColor('6', Color(0xFFFF69B4)),   // Pink
    PresetColor('7', Color(0xFF8B00FF)),   // Purple
    PresetColor('8', Color(0xFFFFD700)),   // Gold/Yellow
    PresetColor('9', Color(0xFF000000)),   // Black (off)
  ];
}

/// A named preset color for the quick-pick grid.
class PresetColor {
  final String label;
  final Color color;
  const PresetColor(this.label, this.color);
}

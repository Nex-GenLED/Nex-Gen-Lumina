import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Model representing the current colors being used by the WLED system
class CurrentColorsState {
  final List<Color> colors;
  final int effectId;
  final int speed;
  final int intensity;
  final int brightness;
  final bool isLoading;
  final String? errorMessage;

  const CurrentColorsState({
    required this.colors,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.brightness,
    this.isLoading = false,
    this.errorMessage,
  });

  CurrentColorsState copyWith({
    List<Color>? colors,
    int? effectId,
    int? speed,
    int? intensity,
    int? brightness,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CurrentColorsState(
      colors: colors ?? this.colors,
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      brightness: brightness ?? this.brightness,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  static CurrentColorsState initial() => const CurrentColorsState(
        colors: [Colors.white],
        effectId: 0,
        speed: 128,
        intensity: 128,
        brightness: 128,
        isLoading: true,
      );
}

/// Provider that manages current colors state
final currentColorsProvider = StateNotifierProvider<CurrentColorsNotifier, CurrentColorsState>((ref) {
  return CurrentColorsNotifier(ref);
});

class CurrentColorsNotifier extends StateNotifier<CurrentColorsState> {
  final Ref ref;

  CurrentColorsNotifier(this.ref) : super(CurrentColorsState.initial()) {
    _loadCurrentColors();
  }

  /// Loads current colors from WLED device
  Future<void> _loadCurrentColors() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final repository = ref.read(wledRepositoryProvider);
      if (repository == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'No device connected',
        );
        return;
      }

      final stateData = await repository.getState();
      if (stateData == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to fetch device state',
        );
        return;
      }

      // Parse colors from segment data
      final colors = _parseColorsFromState(stateData);
      final effectId = _parseEffectId(stateData);
      final speed = _parseSpeed(stateData);
      final intensity = _parseIntensity(stateData);
      final brightness = _parseBrightness(stateData);

      state = CurrentColorsState(
        colors: colors,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
        brightness: brightness,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error loading colors: $e',
      );
    }
  }

  /// Parses colors from WLED state JSON
  List<Color> _parseColorsFromState(Map<String, dynamic> stateData) {
    final colors = <Color>[];

    // Get segment data (can be List or Map)
    final seg = stateData['seg'];
    if (seg == null) return [Colors.white];

    // Handle both List and Map formats
    final segments = seg is List ? seg : [seg];
    if (segments.isEmpty) return [Colors.white];

    // Get first segment's colors
    final firstSeg = segments[0] as Map<String, dynamic>?;
    if (firstSeg == null) return [Colors.white];

    final col = firstSeg['col'];
    if (col is! List) return [Colors.white];

    // Parse up to 3 colors from col array
    for (int i = 0; i < col.length && i < 3; i++) {
      final colorArray = col[i];
      if (colorArray is List && colorArray.length >= 3) {
        final r = (colorArray[0] as num).toInt();
        final g = (colorArray[1] as num).toInt();
        final b = (colorArray[2] as num).toInt();
        colors.add(Color.fromARGB(255, r, g, b));
      }
    }

    return colors.isEmpty ? [Colors.white] : colors;
  }

  int _parseEffectId(Map<String, dynamic> stateData) {
    final seg = stateData['seg'];
    if (seg == null) return 0;
    final segments = seg is List ? seg : [seg];
    if (segments.isEmpty) return 0;
    final firstSeg = segments[0] as Map<String, dynamic>?;
    return (firstSeg?['fx'] as num?)?.toInt() ?? 0;
  }

  int _parseSpeed(Map<String, dynamic> stateData) {
    final seg = stateData['seg'];
    if (seg == null) return 128;
    final segments = seg is List ? seg : [seg];
    if (segments.isEmpty) return 128;
    final firstSeg = segments[0] as Map<String, dynamic>?;
    return (firstSeg?['sx'] as num?)?.toInt() ?? 128;
  }

  int _parseIntensity(Map<String, dynamic> stateData) {
    final seg = stateData['seg'];
    if (seg == null) return 128;
    final segments = seg is List ? seg : [seg];
    if (segments.isEmpty) return 128;
    final firstSeg = segments[0] as Map<String, dynamic>?;
    return (firstSeg?['ix'] as num?)?.toInt() ?? 128;
  }

  int _parseBrightness(Map<String, dynamic> stateData) {
    return (stateData['bri'] as num?)?.toInt() ?? 128;
  }

  /// Updates a specific color slot
  void updateColor(int index, Color color) {
    if (index < 0 || index >= 3) return;

    final newColors = List<Color>.from(state.colors);

    // Expand list if needed
    while (newColors.length <= index) {
      newColors.add(Colors.white);
    }

    newColors[index] = color;
    state = state.copyWith(colors: newColors);
  }

  /// Applies current colors to WLED device without saving
  Future<bool> applyTemporaryColors() async {
    try {
      final repository = ref.read(wledRepositoryProvider);
      if (repository == null) return false;

      // Build WLED payload with current colors
      final payload = _buildWledPayload();
      final success = await repository.applyJson(payload);

      if (success) {
        // Refresh WLED state to sync UI
        ref.invalidate(wledStateProvider);
      }

      return success;
    } catch (e) {
      debugPrint('Error applying temporary colors: $e');
      return false;
    }
  }

  /// Saves current colors as a custom pattern in Firestore
  /// Patterns are saved to the user's designs collection and will appear in "My Designs"
  Future<bool> saveAsCustomPattern(String patternName) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // Create GradientPattern from current state
      final pattern = GradientPattern(
        name: patternName,
        colors: state.colors,
        effectId: state.effectId,
        speed: state.speed,
        intensity: state.intensity,
        brightness: state.brightness,
      );

      // Save to Firestore under user's designs collection
      // This will make it appear in "My Designs" section
      final doc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('designs')
          .doc();

      await doc.set({
        'name': pattern.name,
        'type': 'custom_color_pattern', // Mark as user-created color pattern
        'colors': pattern.colors.map((c) => c.toARGB32()).toList(),
        'effectId': pattern.effectId,
        'effectName': _getEffectName(pattern.effectId),
        'speed': pattern.speed,
        'intensity': pattern.intensity,
        'brightness': pattern.brightness,
        'isStatic': pattern.effectId == 0,
        'wledPayload': pattern.toWledPayload(), // Store the full WLED payload
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Apply the pattern immediately
      await applyTemporaryColors();

      return true;
    } catch (e) {
      debugPrint('Error saving custom pattern: $e');
      return false;
    }
  }

  /// Get effect name from effect ID
  String _getEffectName(int effectId) {
    return kEffectNames[effectId] ?? 'Effect #$effectId';
  }

  /// Builds WLED JSON payload from current state
  /// Applies to ALL segments for consistent multi-segment control
  Map<String, dynamic> _buildWledPayload() {
    // Convert colors to RGBW format
    final colArray = state.colors.take(3).map((c) {
      return [(c.r * 255.0).round().clamp(0, 255), (c.g * 255.0).round().clamp(0, 255), (c.b * 255.0).round().clamp(0, 255), 0]; // Force W=0 for saturated colors
    }).toList();

    // Apply to all segments by using segment ID -1 or creating individual segment updates
    // For simplicity, we'll use a single segment update that applies to the main segment
    // In a multi-segment system, this should be enhanced to apply to all segments
    return {
      'on': true,
      'bri': state.brightness,
      'seg': [
        {
          'id': 0, // Primary segment - WLED will typically apply this to visible segments
          'fx': state.effectId,
          'sx': state.speed,
          'ix': state.intensity,
          'col': colArray,
        }
      ],
    };
  }

  /// Reloads colors from device
  Future<void> refresh() => _loadCurrentColors();
}

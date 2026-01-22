import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/models/segment_aware_pattern.dart';

/// Service provider for design operations
final designServiceProvider = Provider<DesignService>((ref) {
  return DesignService();
});

/// Stream of user's saved designs
final designsStreamProvider = StreamProvider<List<CustomDesign>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value([]);

  final service = ref.read(designServiceProvider);
  return service.streamDesigns(user.uid);
});

/// Currently editing design in the Design Studio
final currentDesignProvider = StateNotifierProvider<CurrentDesignNotifier, CustomDesign?>((ref) {
  return CurrentDesignNotifier(ref);
});

class CurrentDesignNotifier extends StateNotifier<CustomDesign?> {
  final Ref _ref;

  CurrentDesignNotifier(this._ref) : super(null);

  /// Initialize a new empty design with channels from the connected device
  Future<void> createNew() async {
    final user = _ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    // Get channels from the connected WLED device
    final segmentsAsync = _ref.read(zoneSegmentsProvider);
    final segments = segmentsAsync.valueOrNull ?? [];

    // Convert WLED segments to ChannelDesign objects
    final channels = segments.map((seg) => ChannelDesign(
      channelId: seg.id,
      channelName: seg.name,
      included: true,
      colorGroups: [
        LedColorGroup(
          startLed: 0,
          endLed: seg.ledCount > 0 ? seg.ledCount - 1 : 0,
          color: [255, 255, 255, 0], // Default white
        ),
      ],
      effectId: 0, // Solid
      speed: 128,
      intensity: 128,
      reverse: false,
      ledCount: seg.ledCount,
    )).toList();

    state = CustomDesign.empty(user.uid).copyWith(
      channels: channels,
    );
  }

  /// Load an existing design for editing
  void loadDesign(CustomDesign design) {
    state = design;
  }

  /// Update design name
  void setName(String name) {
    if (state == null) return;
    state = state!.copyWith(name: name);
  }

  /// Update design description
  void setDescription(String? description) {
    if (state == null) return;
    state = state!.copyWith(description: description);
  }

  /// Update global brightness
  void setBrightness(int brightness) {
    if (state == null) return;
    state = state!.copyWith(brightness: brightness.clamp(0, 255));
  }

  /// Update tags
  void setTags(List<String> tags) {
    if (state == null) return;
    state = state!.copyWith(tags: tags);
  }

  /// Toggle whether a channel is included in the design
  void toggleChannelIncluded(int channelId) {
    if (state == null) return;
    final channels = state!.channels.map((ch) {
      if (ch.channelId == channelId) {
        return ch.copyWith(included: !ch.included);
      }
      return ch;
    }).toList();
    state = state!.copyWith(channels: channels);
  }

  /// Update a specific channel's configuration
  void updateChannel(int channelId, ChannelDesign updated) {
    if (state == null) return;
    final channels = state!.channels.map((ch) {
      if (ch.channelId == channelId) return updated;
      return ch;
    }).toList();
    state = state!.copyWith(channels: channels);
  }

  /// Set effect for a channel
  void setChannelEffect(int channelId, int effectId) {
    if (state == null) return;
    final channels = state!.channels.map((ch) {
      if (ch.channelId == channelId) {
        return ch.copyWith(effectId: effectId);
      }
      return ch;
    }).toList();
    state = state!.copyWith(channels: channels);
  }

  /// Set speed for a channel
  void setChannelSpeed(int channelId, int speed) {
    if (state == null) return;
    final channels = state!.channels.map((ch) {
      if (ch.channelId == channelId) {
        return ch.copyWith(speed: speed.clamp(0, 255));
      }
      return ch;
    }).toList();
    state = state!.copyWith(channels: channels);
  }

  /// Set intensity for a channel
  void setChannelIntensity(int channelId, int intensity) {
    if (state == null) return;
    final channels = state!.channels.map((ch) {
      if (ch.channelId == channelId) {
        return ch.copyWith(intensity: intensity.clamp(0, 255));
      }
      return ch;
    }).toList();
    state = state!.copyWith(channels: channels);
  }

  /// Toggle reverse direction for a channel
  void toggleChannelReverse(int channelId) {
    if (state == null) return;
    final channels = state!.channels.map((ch) {
      if (ch.channelId == channelId) {
        return ch.copyWith(reverse: !ch.reverse);
      }
      return ch;
    }).toList();
    state = state!.copyWith(channels: channels);
  }

  /// Update the LED count for a specific channel
  void setChannelLedCount(int channelId, int ledCount) {
    if (state == null) return;
    final channels = state!.channels.map((ch) {
      if (ch.channelId == channelId) {
        // Also update the color groups to fit the new LED count
        final updatedGroups = ch.colorGroups.map((group) {
          // Clamp color groups to fit within the new LED count
          final newEndLed = group.endLed.clamp(0, ledCount - 1);
          final newStartLed = group.startLed.clamp(0, newEndLed);
          return group.copyWith(startLed: newStartLed, endLed: newEndLed);
        }).where((g) => g.startLed <= g.endLed).toList();

        // If no valid groups remain, create a default one
        final finalGroups = updatedGroups.isEmpty
            ? [LedColorGroup(startLed: 0, endLed: ledCount - 1, color: [255, 255, 255, 0])]
            : updatedGroups;

        return ch.copyWith(ledCount: ledCount, colorGroups: finalGroups);
      }
      return ch;
    }).toList();
    state = state!.copyWith(channels: channels);
  }

  /// Paint a color to specific LEDs on a channel
  void paintLeds(int channelId, int startLed, int endLed, Color color, {int white = 0}) {
    if (state == null) return;

    final channels = state!.channels.map((ch) {
      if (ch.channelId != channelId) return ch;

      // Create new color group for the painted range
      final newGroup = LedColorGroup.fromColor(startLed, endLed, color, white: white);

      // Merge with existing groups (simplified: just add/replace)
      final updatedGroups = _mergeColorGroups(ch.colorGroups, newGroup, ch.ledCount);

      return ch.copyWith(colorGroups: updatedGroups);
    }).toList();

    state = state!.copyWith(channels: channels);
  }

  /// Fill entire channel with a single color
  void fillChannel(int channelId, Color color, {int white = 0}) {
    if (state == null) return;

    final channels = state!.channels.map((ch) {
      if (ch.channelId != channelId) return ch;

      final endLed = ch.ledCount > 0 ? ch.ledCount - 1 : 0;
      final newGroup = LedColorGroup.fromColor(0, endLed, color, white: white);

      return ch.copyWith(colorGroups: [newGroup]);
    }).toList();

    state = state!.copyWith(channels: channels);
  }

  /// Merge a new color group into existing groups
  List<LedColorGroup> _mergeColorGroups(List<LedColorGroup> existing, LedColorGroup newGroup, int totalLeds) {
    if (existing.isEmpty) return [newGroup];

    // Simple approach: replace any overlapping ranges
    final result = <LedColorGroup>[];

    for (final group in existing) {
      // Check if this group overlaps with the new group
      if (group.endLed < newGroup.startLed || group.startLed > newGroup.endLed) {
        // No overlap, keep as is
        result.add(group);
      } else {
        // Overlap - split the existing group around the new one
        if (group.startLed < newGroup.startLed) {
          // Keep the part before the new group
          result.add(group.copyWith(endLed: newGroup.startLed - 1));
        }
        if (group.endLed > newGroup.endLed) {
          // Keep the part after the new group
          result.add(group.copyWith(startLed: newGroup.endLed + 1));
        }
      }
    }

    // Add the new group
    result.add(newGroup);

    // Sort by start position
    result.sort((a, b) => a.startLed.compareTo(b.startLed));

    return result;
  }

  /// Update design with segment mode data
  void updateSegmentMode({
    required bool isSegmentAware,
    PatternTemplateType? templateType,
    List<LedColorGroup>? segmentColorGroups,
    Map<String, dynamic>? segmentPatternConfig,
    String? rooflineConfigId,
  }) {
    if (state == null) return;
    state = state!.copyWith(
      isSegmentAware: isSegmentAware,
      templateType: templateType,
      segmentColorGroups: segmentColorGroups,
      segmentPatternConfig: segmentPatternConfig,
      rooflineConfigId: rooflineConfigId,
    );
  }

  /// Clear the current design
  void clear() {
    state = null;
  }
}

/// Currently selected channel in the editor
final selectedChannelIdProvider = StateProvider<int?>((ref) => null);

/// Selected LED range for painting (start, end indices)
final selectedLedRangeProvider = StateProvider<({int start, int end})?>((ref) => null);

/// Currently selected color for painting
final selectedColorProvider = StateProvider<Color>((ref) => Colors.cyan);

/// Currently selected white value (for RGBW)
final selectedWhiteProvider = StateProvider<int>((ref) => 0);

/// Recent colors used in this session
final recentColorsProvider = StateNotifierProvider<RecentColorsNotifier, List<Color>>((ref) {
  return RecentColorsNotifier();
});

class RecentColorsNotifier extends StateNotifier<List<Color>> {
  static const int maxRecent = 8;

  RecentColorsNotifier() : super([
    Colors.cyan,
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.white,
  ]);

  void addColor(Color color) {
    final existing = state.where((c) => c.value != color.value).toList();
    state = [color, ...existing].take(maxRecent).toList();
  }
}

/// Preset color palettes for quick selection
final colorPalettesProvider = Provider<Map<String, List<Color>>>((ref) {
  return {
    'Sports Teams': [
      const Color(0xFF003087), // Patriots Blue
      const Color(0xFFC60C30), // Patriots Red
      const Color(0xFFFFB612), // Steelers Gold
      const Color(0xFF000000), // Steelers Black
      const Color(0xFF203731), // Packers Green
      const Color(0xFFFFB612), // Packers Gold
    ],
    'Holidays': [
      const Color(0xFFFF0000), // Christmas Red
      const Color(0xFF00FF00), // Christmas Green
      const Color(0xFFFF6600), // Halloween Orange
      const Color(0xFF800080), // Halloween Purple
      const Color(0xFFFF69B4), // Valentine Pink
      const Color(0xFFFFFFFF), // White
    ],
    'Nature': [
      const Color(0xFF87CEEB), // Sky Blue
      const Color(0xFF228B22), // Forest Green
      const Color(0xFFFFD700), // Sunset Gold
      const Color(0xFFFF4500), // Sunset Orange
      const Color(0xFF4169E1), // Ocean Blue
      const Color(0xFFF5DEB3), // Sand
    ],
    'Neon': [
      const Color(0xFF00FFFF), // Cyan
      const Color(0xFFFF00FF), // Magenta
      const Color(0xFF00FF00), // Lime
      const Color(0xFFFF0080), // Hot Pink
      const Color(0xFF0080FF), // Electric Blue
      const Color(0xFFFFFF00), // Yellow
    ],
  };
});

/// Save the current design to Firestore
final saveDesignProvider = Provider<Future<String?> Function()>((ref) {
  return () async {
    final design = ref.read(currentDesignProvider);
    if (design == null) return null;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return null;

    final service = ref.read(designServiceProvider);
    return service.saveDesign(user.uid, design);
  };
});

/// Apply the current design to the connected WLED device
final applyDesignProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    final design = ref.read(currentDesignProvider);
    if (design == null) return false;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return false;

    final payload = design.toWledPayload();
    final success = await repo.applyJson(payload);

    // Log usage for Lumina learning (if successful)
    if (success) {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user != null) {
        final userService = ref.read(userServiceProvider);

        // Extract color names from the design
        final colorNames = <String>[];
        for (final channel in design.channels.where((ch) => ch.included)) {
          for (final group in channel.colorGroups) {
            colorNames.add(_colorToName(group.color));
          }
        }

        // Get first effect ID from included channels
        final effectId = design.channels
            .where((ch) => ch.included)
            .map((ch) => ch.effectId)
            .firstOrNull;

        await userService.logPatternUsage(
          userId: user.uid,
          colorNames: colorNames.toSet().toList(), // unique colors
          effectId: effectId,
          wled: payload,
          source: 'design_studio',
        );
      }
    }

    return success;
  };
});

/// Convert RGB color array to a color name for logging
String _colorToName(List<int> color) {
  if (color.length < 3) return 'unknown';
  final r = color[0];
  final g = color[1];
  final b = color[2];

  if (r > 200 && g < 100 && b < 100) return 'red';
  if (r < 100 && g > 200 && b < 100) return 'green';
  if (r < 100 && g < 100 && b > 200) return 'blue';
  if (r > 200 && g > 200 && b > 200) return 'white';
  if (r > 200 && g > 200 && b < 100) return 'yellow';
  if (r > 200 && g > 100 && g < 200 && b < 100) return 'orange';
  if (r > 100 && g < 100 && b > 200) return 'purple';
  if (r < 100 && g > 200 && b > 200) return 'cyan';
  if (r > 200 && g < 150 && b > 150) return 'pink';

  return 'custom';
}

/// Delete a design from Firestore
final deleteDesignProvider = Provider<Future<bool> Function(String designId)>((ref) {
  return (designId) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return false;

    final service = ref.read(designServiceProvider);
    try {
      await service.deleteDesign(user.uid, designId);
      return true;
    } catch (_) {
      return false;
    }
  };
});

/// Duplicate an existing design
final duplicateDesignProvider = Provider<Future<String?> Function(CustomDesign design, String newName)>((ref) {
  return (design, newName) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return null;

    final service = ref.read(designServiceProvider);
    return service.duplicateDesign(user.uid, design, newName);
  };
});

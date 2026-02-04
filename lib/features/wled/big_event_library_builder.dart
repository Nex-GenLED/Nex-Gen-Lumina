import 'package:flutter/material.dart';
import 'package:nexgen_command/data/sports_teams.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/services/big_event_service.dart';

/// Folder IDs for Big Event Designs
class BigEventFolderIds {
  /// Root folder for current big events
  static const String bigEvents = 'big_events';

  /// Generate event-specific folder ID
  static String eventFolder(String eventId) => 'big_event_$eventId';

  /// Generate team folder ID within an event
  static String teamFolder(String eventId, String teamName) =>
      'big_event_${eventId}_team_${teamName.toLowerCase().replaceAll(' ', '_')}';

  /// Generate merged designs folder ID
  static String mergedFolder(String eventId) => 'big_event_${eventId}_merged';
}

/// Types of merged dual-team patterns
enum DualTeamPatternType {
  /// Half the house is one team, half is the other
  houseSplit,

  /// Teams alternate every N pixels
  alternatingStripe,

  /// Wave pattern that transitions between teams
  teamWave,

  /// One team's colors chase through the other's
  rivalryChase,

  /// Colors rotate between both teams in sequence
  colorRotation,

  /// Breathe effect alternating team colors
  teamBreathe,

  /// Both teams' colors blended in gradient
  harmonyBlend,
}

/// Builds the Big Event Designs folder structure for the pattern library.
///
/// Creates dynamic folders based on upcoming major sporting events with:
/// - Individual team palettes
/// - Merged dual-team designs for neutral party celebrations
/// - Creative movement patterns showcasing both teams
class BigEventLibraryBuilder {
  /// Build the complete Big Event hierarchy for given events.
  ///
  /// Returns an empty list if no events are provided.
  static List<LibraryNode> buildBigEventHierarchy(List<BigEvent> events) {
    if (events.isEmpty) return [];

    final nodes = <LibraryNode>[];

    // Create the root "Big Event Designs" folder
    // Name it based on the primary (largest audience) event
    final primaryEvent = events.first;
    nodes.add(LibraryNode(
      id: BigEventFolderIds.bigEvents,
      name: primaryEvent.folderName,
      description: _getEventDescription(primaryEvent),
      nodeType: LibraryNodeType.folder,
      parentId: LibraryCategoryIds.sports,
      sortOrder: -1, // Before leagues
      imageUrl: _getEventImageUrl(primaryEvent),
      metadata: {
        'eventType': primaryEvent.eventType.name,
        'eventCount': events.length,
        'primaryEventId': primaryEvent.id,
      },
    ));

    // Build nodes for each event
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      nodes.addAll(_buildEventNodes(event, i));
    }

    return nodes;
  }

  /// Build nodes for a single event
  static List<LibraryNode> _buildEventNodes(BigEvent event, int sortOrder) {
    final nodes = <LibraryNode>[];
    final eventFolderId = BigEventFolderIds.eventFolder(event.id);

    if (sortOrder > 0) {
      // Create event subfolder for secondary events
      nodes.add(LibraryNode(
        id: eventFolderId,
        name: event.name,
        description: '${event.team1.displayName} vs ${event.team2.displayName}',
        nodeType: LibraryNodeType.folder,
        parentId: BigEventFolderIds.bigEvents,
        sortOrder: sortOrder,
        metadata: {
          'eventId': event.id,
          'league': event.league,
        },
      ));
    }

    final childParentId = sortOrder > 0 ? eventFolderId : BigEventFolderIds.bigEvents;

    // Team 1 folder
    nodes.add(_buildTeamFolder(event.team1, event.id, childParentId, 0));
    nodes.addAll(_buildTeamPalettes(event.team1, event.id));

    // Team 2 folder
    nodes.add(_buildTeamFolder(event.team2, event.id, childParentId, 1));
    nodes.addAll(_buildTeamPalettes(event.team2, event.id));

    // Merged/Dual-Team designs folder
    nodes.add(_buildMergedFolder(event, childParentId, 2));
    nodes.addAll(_buildMergedPalettes(event));

    return nodes;
  }

  /// Build a team folder node
  static LibraryNode _buildTeamFolder(
    SportsTeam team,
    String eventId,
    String parentId,
    int sortOrder,
  ) {
    return LibraryNode(
      id: BigEventFolderIds.teamFolder(eventId, team.name),
      name: team.displayName,
      description: '${team.city} ${team.name} colors',
      nodeType: LibraryNodeType.folder,
      parentId: parentId,
      themeColors: team.colors,
      sortOrder: sortOrder,
      metadata: {
        'teamName': team.name,
        'city': team.city,
        'league': team.league,
      },
    );
  }

  /// Build team-specific palettes
  static List<LibraryNode> _buildTeamPalettes(SportsTeam team, String eventId) {
    final parentId = BigEventFolderIds.teamFolder(eventId, team.name);
    final nodes = <LibraryNode>[];

    // Solid team colors
    nodes.add(LibraryNode(
      id: '${parentId}_solid',
      name: 'Solid ${team.name}',
      description: 'Static team colors',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: team.colors,
      sortOrder: 0,
      metadata: {
        'suggestedEffects': [0], // Solid
        'defaultSpeed': 0,
        'defaultIntensity': 128,
      },
    ));

    // Team colors chase
    nodes.add(LibraryNode(
      id: '${parentId}_chase',
      name: '${team.name} Chase',
      description: 'Team colors in motion',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: team.colors,
      sortOrder: 1,
      metadata: {
        'suggestedEffects': [28, 12], // Chase 2, Theater Chase
        'defaultSpeed': 100,
        'defaultIntensity': 180,
      },
    ));

    // Team colors breathe
    nodes.add(LibraryNode(
      id: '${parentId}_breathe',
      name: '${team.name} Breathe',
      description: 'Pulsing team pride',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: team.colors,
      sortOrder: 2,
      metadata: {
        'suggestedEffects': [2], // Breathe
        'defaultSpeed': 80,
        'defaultIntensity': 128,
      },
    ));

    // Team running lights
    nodes.add(LibraryNode(
      id: '${parentId}_running',
      name: '${team.name} Running',
      description: 'Running team lights',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: team.colors,
      sortOrder: 3,
      metadata: {
        'suggestedEffects': [41, 42], // Running, Saw
        'defaultSpeed': 120,
        'defaultIntensity': 200,
      },
    ));

    // Team twinkle
    nodes.add(LibraryNode(
      id: '${parentId}_twinkle',
      name: '${team.name} Twinkle',
      description: 'Sparkling team spirit',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: team.colors,
      sortOrder: 4,
      metadata: {
        'suggestedEffects': [17, 49], // Twinkle, Fairy
        'defaultSpeed': 80,
        'defaultIntensity': 150,
      },
    ));

    return nodes;
  }

  /// Build the merged designs folder
  static LibraryNode _buildMergedFolder(
    BigEvent event,
    String parentId,
    int sortOrder,
  ) {
    final mergedColors = _deduplicateColors([
      event.team1.colors.first,
      event.team2.colors.first,
      if (event.team1.colors.length > 1) event.team1.colors[1],
      if (event.team2.colors.length > 1) event.team2.colors[1],
    ]);

    return LibraryNode(
      id: BigEventFolderIds.mergedFolder(event.id),
      name: 'Both Teams',
      description: 'Celebrate both teams at once',
      nodeType: LibraryNodeType.folder,
      parentId: parentId,
      themeColors: mergedColors,
      sortOrder: sortOrder,
      metadata: {
        'team1': event.team1.name,
        'team2': event.team2.name,
        'isMergedFolder': true,
      },
    );
  }

  /// Build merged dual-team pattern palettes
  static List<LibraryNode> _buildMergedPalettes(BigEvent event) {
    final parentId = BigEventFolderIds.mergedFolder(event.id);
    final nodes = <LibraryNode>[];

    final team1Primary = event.team1.colors.first;
    final team2Primary = event.team2.colors.first;
    final team1Secondary = event.team1.colors.length > 1
        ? event.team1.colors[1]
        : _lightenColor(team1Primary);
    final team2Secondary = event.team2.colors.length > 1
        ? event.team2.colors[1]
        : _lightenColor(team2Primary);

    final samePrimary = team1Primary.value == team2Primary.value;

    // When both teams share a primary color (e.g. Seahawks & Patriots both
    // use Navy 0xFF002244), we must reorder so each team's distinctive
    // secondary color appears within WLED's 3-color limit.
    //
    // distinctPair  – 2 visually different colors for pulse / comet effects
    // distinctTrio  – 3 unique colors for wave / gradient / harmony effects
    // allUnique     – all unique colors for chase / fireworks effects
    final distinctPair = samePrimary
        ? [team1Secondary, team2Secondary]
        : [team1Primary, team2Primary];
    final distinctTrio = samePrimary
        ? [team1Primary, team1Secondary, team2Secondary]
        : [team1Primary, team2Primary, team1Secondary];
    final allUnique = _deduplicateColors(
        [team1Primary, team1Secondary, team2Primary, team2Secondary]);

    // 50/50 House Split
    // (actual WLED payload uses segment split from metadata team colors)
    nodes.add(LibraryNode(
      id: '${parentId}_house_split',
      name: 'House Divided',
      description: 'Half ${event.team1.name}, half ${event.team2.name}',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: distinctTrio,
      sortOrder: 0,
      metadata: {
        'suggestedEffects': [0], // Solid with segment split
        'defaultSpeed': 0,
        'defaultIntensity': 128,
        'patternType': DualTeamPatternType.houseSplit.name,
        'segmentSplit': true,
        'team1Colors': event.team1.colors.map((c) => c.value).toList(),
        'team2Colors': event.team2.colors.map((c) => c.value).toList(),
      },
    ));

    // Alternating team stripes
    nodes.add(LibraryNode(
      id: '${parentId}_alternating',
      name: 'Team Stripes',
      description: 'Alternating ${event.team1.name} and ${event.team2.name}',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: allUnique,
      sortOrder: 1,
      metadata: {
        'suggestedEffects': [12, 6, 51, 0], // Fade, Sweep, Gradient, Solid — prefer 3-color effects
        'defaultSpeed': 80,
        'defaultIntensity': 128,
        'patternType': DualTeamPatternType.alternatingStripe.name,
        'grouping': 5, // 5 pixels per team
        'spacing': 5,
      },
    ));

    // Team wave - one team flows into the other
    nodes.add(LibraryNode(
      id: '${parentId}_team_wave',
      name: 'Rivalry Wave',
      description: '${event.team1.name} flows to ${event.team2.name} and back',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: distinctTrio,
      sortOrder: 2,
      metadata: {
        'suggestedEffects': [51, 12, 6, 18], // Gradient, Fade, Sweep, Dissolve — 3-color effects
        'defaultSpeed': 60,
        'defaultIntensity': 200,
        'patternType': DualTeamPatternType.teamWave.name,
      },
    ));

    // Rivalry chase - colors chase each other
    nodes.add(LibraryNode(
      id: '${parentId}_rivalry_chase',
      name: 'Rivalry Chase',
      description: 'Team colors chase each other',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: allUnique,
      sortOrder: 3,
      metadata: {
        'suggestedEffects': [12, 28, 6, 46], // Fade, Chase 2, Sweep, Twinklefox — 3-color effects
        'defaultSpeed': 100,
        'defaultIntensity': 200,
        'patternType': DualTeamPatternType.rivalryChase.name,
      },
    ));

    // Color rotation - all colors cycle
    nodes.add(LibraryNode(
      id: '${parentId}_color_rotation',
      name: 'Matchup Colors',
      description: 'Both teams\' colors in rotation',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: allUnique,
      sortOrder: 4,
      metadata: {
        'suggestedEffects': [12, 6, 51, 46], // Fade, Sweep, Gradient, Twinklefox — 3-color effects
        'defaultSpeed': 80,
        'defaultIntensity': 180,
        'patternType': DualTeamPatternType.colorRotation.name,
      },
    ));

    // Team breathe - alternating pulse
    nodes.add(LibraryNode(
      id: '${parentId}_team_breathe',
      name: 'Dueling Pulse',
      description: 'Breathe between both teams',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: distinctPair,
      sortOrder: 5,
      metadata: {
        'suggestedEffects': [2], // Breathe
        'defaultSpeed': 40,
        'defaultIntensity': 128,
        'patternType': DualTeamPatternType.teamBreathe.name,
      },
    ));

    // Harmony blend - gradient between teams
    nodes.add(LibraryNode(
      id: '${parentId}_harmony',
      name: 'Game Day Harmony',
      description: 'Smooth blend of both teams',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: distinctTrio,
      sortOrder: 6,
      metadata: {
        'suggestedEffects': [51, 12, 46, 6], // Gradient, Fade, Twinklefox, Sweep — 3-color effects
        'defaultSpeed': 50,
        'defaultIntensity': 200,
        'patternType': DualTeamPatternType.harmonyBlend.name,
      },
    ));

    // Fireworks celebration
    nodes.add(LibraryNode(
      id: '${parentId}_fireworks',
      name: 'Victory Fireworks',
      description: 'Celebratory fireworks in both colors',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: allUnique,
      sortOrder: 7,
      metadata: {
        'suggestedEffects': [66, 89], // Fireworks, Fireworks 1D
        'defaultSpeed': 128,
        'defaultIntensity': 200,
      },
    ));

    // Comet effect
    nodes.add(LibraryNode(
      id: '${parentId}_comet',
      name: 'Rivalry Comet',
      description: 'Comet trails in team colors',
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: distinctPair,
      sortOrder: 8,
      metadata: {
        'suggestedEffects': [65], // Comet
        'defaultSpeed': 140,
        'defaultIntensity': 180,
      },
    ));

    return nodes;
  }

  /// Get description for the primary event
  static String _getEventDescription(BigEvent event) {
    return '${event.team1.displayName} vs ${event.team2.displayName}';
  }

  /// Get an appropriate image URL for the event type
  static String _getEventImageUrl(BigEvent event) {
    switch (event.eventType) {
      case BigEventType.superBowl:
        return 'https://images.unsplash.com/photo-1504450758481-7338eba7524a'; // Football
      case BigEventType.worldSeries:
        return 'https://images.unsplash.com/photo-1566577739112-5180d4bf9390'; // Baseball
      case BigEventType.nbaFinals:
        return 'https://images.unsplash.com/photo-1546519638-68e109498ffc'; // Basketball
      case BigEventType.stanleyCup:
        return 'https://images.unsplash.com/photo-1580920461931-fcb03a940df5'; // Hockey
      default:
        return 'https://images.unsplash.com/photo-1518600506278-4e8ef466b810'; // Stadium
    }
  }

  /// Lighten a color for secondary accent
  static Color _lightenColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0)).toColor();
  }

  /// Remove duplicate colors (by ARGB value) while preserving order.
  static List<Color> _deduplicateColors(List<Color> colors) {
    final seen = <int>{};
    return [
      for (final c in colors)
        if (seen.add(c.value)) c,
    ];
  }
}

/// Extension for building WLED payloads from dual-team patterns
extension DualTeamPatternPayload on LibraryNode {
  /// Generate a WLED payload for a dual-team pattern.
  ///
  /// If this is a merged pattern with segment split, creates appropriate
  /// segments for each team's portion of the lights.
  Map<String, dynamic> toDualTeamPayload({
    int totalPixels = 150,
    int brightness = 210,
  }) {
    final patternType = metadata?['patternType'] as String?;
    final segmentSplit = metadata?['segmentSplit'] as bool? ?? false;

    if (patternType == DualTeamPatternType.houseSplit.name && segmentSplit) {
      // Create two segments, one for each team
      final team1Colors = (metadata?['team1Colors'] as List?)?.cast<int>() ?? [];
      final team2Colors = (metadata?['team2Colors'] as List?)?.cast<int>() ?? [];

      final halfPoint = totalPixels ~/ 2;

      return {
        'on': true,
        'bri': brightness,
        'seg': [
          {
            'id': 0,
            'start': 0,
            'stop': halfPoint,
            'fx': 0, // Solid
            'col': team1Colors.take(3).map((c) {
              final color = Color(c);
              return [color.red, color.green, color.blue, 0];
            }).toList(),
          },
          {
            'id': 1,
            'start': halfPoint,
            'stop': totalPixels,
            'fx': 0, // Solid
            'col': team2Colors.take(3).map((c) {
              final color = Color(c);
              return [color.red, color.green, color.blue, 0];
            }).toList(),
          },
        ],
      };
    }

    // Default single-segment payload
    final effects = suggestedEffects;
    final colors = themeColors ?? [];

    return {
      'on': true,
      'bri': brightness,
      'seg': [
        {
          'fx': effects.isNotEmpty ? effects.first : 0,
          'sx': defaultSpeed,
          'ix': defaultIntensity,
          'pal': 0,
          'col': colors.take(3).map((c) => [c.red, c.green, c.blue, 0]).toList(),
        },
      ],
    };
  }
}

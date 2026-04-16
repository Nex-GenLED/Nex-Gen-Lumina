// lib/features/autopilot/team_design_catalog.dart
//
// Generates a catalog of team-themed LED designs from a team's primary
// and secondary colors. Used by GameDayAutopilotService to provide
// variety across games when designVariety is rotating or random.
//
// Six designs cover a spectrum from subtle to dramatic:
//   1. Solid Primary     — classic, always-works baseline
//   2. Solid Secondary   — alternate team color as main
//   3. Chase Primary→Secondary — motion, team-branded
//   4. Breathe Primary   — subtle pulsing atmosphere
//   5. Twinkle (both)    — celebratory sparkle
//   6. Candy Cane Stripe — alternating primary/secondary bands
//
// Each design is returned as a fully-built WLED payload ready to
// hand to WledRepository.applyJson().

import 'dart:ui' show Color;

/// A single team-themed design in the rotation catalog.
class TeamDesign {
  final String name;
  final int effectId;
  final int speed;
  final int intensity;
  final int colorGroupSize; // WLED 'grp' — LEDs per color band
  final Map<String, dynamic> wledPayload;

  const TeamDesign({
    required this.name,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.colorGroupSize,
    required this.wledPayload,
  });
}

/// Builds the ordered design catalog for a team.
class TeamDesignCatalog {
  /// Generate the full 6-design catalog for a team.
  /// [brightness] is 0-255 and is baked into every payload.
  static List<TeamDesign> build({
    required String teamName,
    required Color primary,
    required Color secondary,
    int brightness = 200,
  }) {
    final p = _rgbw(primary);
    final s = _rgbw(secondary);

    return [
      // 1. Solid Primary
      TeamDesign(
        name: '$teamName Solid',
        effectId: 0,
        speed: 128,
        intensity: 128,
        colorGroupSize: 1,
        wledPayload: _buildPayload(
          effectId: 0,
          colors: [p, s],
          speed: 128,
          intensity: 128,
          brightness: brightness,
        ),
      ),
      // 2. Solid Secondary
      TeamDesign(
        name: '$teamName Alt',
        effectId: 0,
        speed: 128,
        intensity: 128,
        colorGroupSize: 1,
        wledPayload: _buildPayload(
          effectId: 0,
          colors: [s, p],
          speed: 128,
          intensity: 128,
          brightness: brightness,
        ),
      ),
      // 3. Chase Primary → Secondary (WLED fx 28 = Chase)
      TeamDesign(
        name: '$teamName Chase',
        effectId: 28,
        speed: 180,
        intensity: 180,
        colorGroupSize: 1,
        wledPayload: _buildPayload(
          effectId: 28,
          colors: [p, s],
          speed: 180,
          intensity: 180,
          brightness: brightness,
        ),
      ),
      // 4. Breathe Primary (WLED fx 2 = Breathe)
      TeamDesign(
        name: '$teamName Breathe',
        effectId: 2,
        speed: 120,
        intensity: 128,
        colorGroupSize: 1,
        wledPayload: _buildPayload(
          effectId: 2,
          colors: [p, s],
          speed: 120,
          intensity: 128,
          brightness: brightness,
        ),
      ),
      // 5. Twinkle (WLED fx 63 = Twinkle)
      TeamDesign(
        name: '$teamName Twinkle',
        effectId: 63,
        speed: 150,
        intensity: 200,
        colorGroupSize: 1,
        wledPayload: _buildPayload(
          effectId: 63,
          colors: [p, s],
          speed: 150,
          intensity: 200,
          brightness: brightness,
        ),
      ),
      // 6. Candy Cane Stripe — solid effect with colorGroupSize = 3 to
      // create alternating 3-LED bands of primary/secondary.
      TeamDesign(
        name: '$teamName Stripe',
        effectId: 0,
        speed: 128,
        intensity: 128,
        colorGroupSize: 3,
        wledPayload: _buildPayload(
          effectId: 0,
          colors: [p, s],
          speed: 128,
          intensity: 128,
          brightness: brightness,
          colorGroupSize: 3,
        ),
      ),
    ];
  }

  /// Select a design from the catalog based on rotation index.
  ///
  /// For [AutopilotVarietyMode.rotating]: pass the game number in the
  /// season as [index]. Returns catalog[index % catalog.length].
  static TeamDesign selectForRotation(
    List<TeamDesign> catalog,
    int index,
  ) {
    if (catalog.isEmpty) {
      throw StateError('TeamDesignCatalog: empty catalog');
    }
    return catalog[index.abs() % catalog.length];
  }

  /// Select a design using a deterministic seed (e.g. game date hash).
  ///
  /// For [AutopilotVarietyMode.random]: same seed always returns the
  /// same design so repeat views of the same game day match.
  static TeamDesign selectForRandom(
    List<TeamDesign> catalog,
    int seed,
  ) {
    if (catalog.isEmpty) {
      throw StateError('TeamDesignCatalog: empty catalog');
    }
    // Deterministic: same seed → same design. Use modular arithmetic
    // on the seed so the same game always shows the same design.
    final idx = (seed.abs()) % catalog.length;
    return catalog[idx];
  }

  // ── Internal helpers ────────────────────────────────────────────

  static List<int> _rgbw(Color c) => [
        (c.r * 255.0).round().clamp(0, 255),
        (c.g * 255.0).round().clamp(0, 255),
        (c.b * 255.0).round().clamp(0, 255),
        0, // W channel
      ];

  static Map<String, dynamic> _buildPayload({
    required int effectId,
    required List<List<int>> colors,
    required int speed,
    required int intensity,
    required int brightness,
    int colorGroupSize = 1,
  }) {
    return {
      'on': true,
      'bri': brightness.clamp(0, 255),
      'seg': [
        {
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
          'grp': colorGroupSize,
          'pal': 0,
          'col': colors,
        }
      ],
    };
  }
}

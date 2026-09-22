// lib/features/autopilot/team_design_catalog.dart
//
// Generates a catalog of team-themed LED designs from a team's primary
// and secondary colors. Used by GameDayAutopilotService to provide
// variety across games when designVariety is rotating or random.
//
// Six designs cover a spectrum from subtle to dramatic:
//   1. Team Colors       — Running Dual (fx 52) showing both colors
//   2. Solid Secondary   — alternate team color as main
//   3. Chase Primary→Secondary — motion, team-branded
//   4. Breathe Primary   — subtle pulsing atmosphere
//   5. Fade (both)       — slow full-strip crossfade primary ↔ secondary
//   6. Candy Cane Stripe — alternating primary/secondary bands
//
// Each design is returned as a fully-built WLED payload ready to
// hand to WledRepository.applyJson().
//
// EFFECT IDS ARE NOT LABELS. Design 5 shipped as fx 63 captioned "Twinkle";
// on WLED 0.15.1 fx 63 is Pride 2015, a hue-rotating rainbow that reads
// neither `col[]` nor the palette (bench 2026-09-21: 55 % of lit pixels in
// hues the team does not have, 162 colours per frame). Every id here must be
// checked against the firmware's own `/json/eff`, and
// base_design_team_colors_guard_test.dart pins that each design plays the
// team's own colours.

import 'dart:ui' show Color;

import 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart'
    show getSpeedProfile;
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart'
    show WledEffectsCatalog;

/// The Game Day base design's "dynamic" look: WLED fx 12, Fade — the whole
/// strip crossfades between the team's primary and secondary, reading
/// `col[]` directly. Verified against the bench controller's own `/json/eff`
/// (WLED 0.15.1) and by live observation on 2026-09-21. Shared by the
/// rotation catalog (design 5) and GameDayAutopilotService's style switch.
const int kBaseDesignFadeEffectId = 12;

/// Fade's speed for the base design: the catalog's own "Fade pace" default
/// (`getSpeedProfile(12).rawDefault`), which the profile labels 'Very Slow'.
/// Measured on the bench: a 4.4 s primary → secondary → primary round trip
/// (the effect's slowest, sx 5, is 6.6 s; the top of the 'Slow' band, 68,
/// is 3.6 s).
final int kBaseDesignFadeSpeed =
    getSpeedProfile(kBaseDesignFadeEffectId).rawDefault;

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
      // 1. Team Colors — Running Dual (fx 52) showing both team colors
      TeamDesign(
        name: '$teamName Colors',
        effectId: 52,
        speed: 160,
        intensity: 128,
        colorGroupSize: 1,
        wledPayload: _buildPayload(
          effectId: 52,
          colors: [p, s],
          speed: 160,
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
      // 5. Fade (WLED fx 12 = Fade): the whole strip crossfades primary ↔
      // secondary, reading `col[]` directly (bench 2026-09-21: uniform strip,
      // 0 % foreign hues, one colour per frame). Speed is the catalog's own
      // "Fade pace" default — its 'Very Slow' band — a 4.4 s round trip on
      // the bench; the effect's slowest setting (sx 5) is 6.6 s. Was fx 63
      // "Twinkle" = Pride 2015, a rainbow.
      TeamDesign(
        name: '$teamName Fade',
        effectId: kBaseDesignFadeEffectId,
        speed: kBaseDesignFadeSpeed,
        intensity: 128,
        colorGroupSize: 1,
        wledPayload: _buildPayload(
          effectId: kBaseDesignFadeEffectId,
          colors: [p, s],
          speed: kBaseDesignFadeSpeed,
          intensity: 128,
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
  /// Same seed always returns the same design so repeat views match.
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
          // #88 — `grp` RESTORED as DESIGN (decision of record 2026-08-17);
          // a team design's colour banding is the design, and `spc` is
          // asserted at its default so the look never inherits the previous
          // pattern's spacing.
          'grp': colorGroupSize,
          'spc': kDesignDefaultSpc,
          // The palette that makes THIS effect play `col[]`: 0 for a
          // colour-reading effect (every design here), "Colors Only" for a
          // palette-reading one. Never a bare literal — fx 63 sat under a
          // hard-coded 0 for six months looking like a Twinkle.
          'pal': WledEffectsCatalog.setColorsPaletteFor(effectId),
          'col': colors,
        }
      ],
    };
  }
}

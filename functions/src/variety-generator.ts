/**
 * Variety Generator for Multi-Day Scheduling
 *
 * Ensures multi-day schedule plans never repeat the same look on
 * consecutive nights. Provides effect rotation, color emphasis shifting,
 * and energy level variation across a week.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface VarietyEntry {
  dayIndex: number; // 0-based within the plan
  dayLabel: string; // "monday", "2025-12-25", etc.
  effectId: number;
  colors: number[][];
  speed: number;
  intensity: number;
  brightness: number;
}

export interface VarietyConfig {
  /** Base theme colors (e.g., team primary + secondary). 1-3 colors. */
  themeColors: number[][];
  /** Preferred effect IDs to rotate through. */
  preferredEffects?: number[];
  /** Whether this is a festive/holiday schedule (allows higher energy). */
  festive?: boolean;
  /** Override brightness for all entries (otherwise uses energy-based). */
  brightness?: number;
}

/** Day-of-week energy levels: 0 = calm, 1 = medium, 2 = high */
const DAY_ENERGY: Record<string, number> = {
  monday: 0,
  tuesday: 0,
  wednesday: 1,
  thursday: 1,
  friday: 2,
  saturday: 2,
  sunday: 0,
};

/** Effect pools mapped to energy levels. */
const ENERGY_EFFECTS: Record<number, number[]> = {
  0: [2, 46, 95, 96, 13, 89, 57, 110],       // Calm: Breathe, Gradient, Candle, Fade, Blends, Aurora, Lake
  1: [74, 117, 108, 50, 85, 38, 111],         // Medium: Twinkle, Twinklefox, Fairy, Twinkle Fade, Ripple, Dissolve, Meteor
  2: [28, 33, 14, 52, 65, 42, 9, 27],         // High: Chase, Running, Theater Chase, Sparkle, Sparkle+, Fireworks, Rainbow, Candy Cane
};

/** Brightness ranges per energy level [min, max]. */
const ENERGY_BRIGHTNESS: Record<number, [number, number]> = {
  0: [120, 170],
  1: [160, 210],
  2: [200, 255],
};

// ---------------------------------------------------------------------------
// Color Rotation
// ---------------------------------------------------------------------------

/**
 * Rotate color emphasis for a given day index.
 *
 * Given theme colors [A, B, C?], produces varied palettes:
 *   Day 0: [A, B, C]         — standard
 *   Day 1: [B, A, C]         — swap primary/secondary
 *   Day 2: [A, blend(A,B)]   — gradient-style
 *   Day 3: [A, B, white]     — accent with white
 *   Day 4: [B, C, A]         — full rotation
 *   Day 5: [blend(A,B), B]   — reverse gradient
 *   Day 6: [A, C, B]         — alternate order
 */
export function rotateColors(
  themeColors: number[][],
  dayIndex: number
): number[][] {
  if (themeColors.length === 0) {
    return [[255, 180, 100]]; // fallback warm white
  }

  const a = themeColors[0];
  const b = themeColors.length > 1 ? themeColors[1] : lighten(a, 0.3);
  const c = themeColors.length > 2 ? themeColors[2] : [255, 255, 255];

  const rotation = dayIndex % 7;

  switch (rotation) {
    case 0:
      return [a, b, c];
    case 1:
      return [b, a, c];
    case 2:
      return [a, blendColors(a, b, 0.5)];
    case 3:
      return [a, b, [255, 255, 255]];
    case 4:
      return [b, c, a];
    case 5:
      return [blendColors(a, b, 0.5), b];
    case 6:
      return [a, c, b];
    default:
      return [a, b, c];
  }
}

/**
 * Blend two RGB colors at a given ratio (0 = all colorA, 1 = all colorB).
 */
function blendColors(
  colorA: number[],
  colorB: number[],
  ratio: number
): number[] {
  return [
    Math.round(colorA[0] + (colorB[0] - colorA[0]) * ratio),
    Math.round(colorA[1] + (colorB[1] - colorA[1]) * ratio),
    Math.round(colorA[2] + (colorB[2] - colorA[2]) * ratio),
  ];
}

/**
 * Lighten a color by mixing toward white.
 */
function lighten(color: number[], amount: number): number[] {
  return blendColors(color, [255, 255, 255], amount);
}

// ---------------------------------------------------------------------------
// Effect Selection
// ---------------------------------------------------------------------------

/**
 * Pick an effect for a given day, ensuring it differs from the previous day.
 */
function pickEffect(
  dayLabel: string,
  dayIndex: number,
  previousEffectId: number | null,
  preferredEffects?: number[],
  festive?: boolean
): number {
  // Determine energy level
  const dayLower = dayLabel.toLowerCase();
  const energy = DAY_ENERGY[dayLower] ?? (festive ? 2 : 1);

  // Build candidate pool
  let pool: number[];
  if (preferredEffects && preferredEffects.length > 0) {
    pool = [...preferredEffects];
  } else {
    pool = [...ENERGY_EFFECTS[energy]];
    // For festive schedules, mix in some higher-energy effects
    if (festive && energy < 2) {
      pool.push(...ENERGY_EFFECTS[2].slice(0, 3));
    }
  }

  // Remove previous effect to avoid consecutive repeats
  if (previousEffectId !== null) {
    pool = pool.filter((e) => e !== previousEffectId);
  }

  // If pool is empty after filtering, use the full energy pool
  if (pool.length === 0) {
    pool = [...ENERGY_EFFECTS[energy]];
  }

  // Deterministic-ish selection based on day index for reproducibility
  return pool[dayIndex % pool.length];
}

/**
 * Pick speed and intensity values with variation.
 */
function pickParams(
  dayIndex: number,
  energy: number
): { speed: number; intensity: number } {
  // Base values per energy level
  const baseSpeed = energy === 0 ? 80 : energy === 1 ? 128 : 180;
  const baseIntensity = energy === 0 ? 100 : energy === 1 ? 128 : 170;

  // Add deterministic variation (±30 for speed, ±20 for intensity)
  const speedOffset = ((dayIndex * 37) % 61) - 30; // -30 to +30
  const intensityOffset = ((dayIndex * 23) % 41) - 20; // -20 to +20

  return {
    speed: Math.max(0, Math.min(255, baseSpeed + speedOffset)),
    intensity: Math.max(0, Math.min(255, baseIntensity + intensityOffset)),
  };
}

// ---------------------------------------------------------------------------
// Main Generator
// ---------------------------------------------------------------------------

/**
 * Generate a variety plan for multiple days of scheduling.
 *
 * @param days    - Array of day labels (e.g., ["monday","tuesday",...] or dates)
 * @param config  - Theme colors, preferred effects, and options
 * @returns Array of VarietyEntry, one per day
 */
export function generateVarietyPlan(
  days: string[],
  config: VarietyConfig
): VarietyEntry[] {
  const entries: VarietyEntry[] = [];
  let previousEffectId: number | null = null;

  for (let i = 0; i < days.length; i++) {
    const dayLabel = days[i];
    const dayLower = dayLabel.toLowerCase();

    // Determine energy for this day
    const energy = DAY_ENERGY[dayLower] ?? (config.festive ? 2 : 1);

    // Pick effect (avoiding consecutive repeats)
    const effectId = pickEffect(
      dayLabel,
      i,
      previousEffectId,
      config.preferredEffects,
      config.festive
    );

    // Rotate colors
    const colors = rotateColors(config.themeColors, i);

    // Pick speed/intensity
    const params = pickParams(i, energy);

    // Determine brightness
    let brightness: number;
    if (config.brightness !== undefined) {
      brightness = config.brightness;
    } else {
      const [minB, maxB] = ENERGY_BRIGHTNESS[energy];
      // Vary within the range based on day index
      brightness = minB + Math.round(((maxB - minB) * ((i * 41) % 100)) / 100);
    }

    entries.push({
      dayIndex: i,
      dayLabel,
      effectId,
      colors,
      speed: params.speed,
      intensity: params.intensity,
      brightness,
    });

    previousEffectId = effectId;
  }

  return entries;
}

/**
 * Validate that a variety plan has no consecutive duplicate looks.
 * Returns true if the plan passes validation.
 */
export function validateVarietyPlan(entries: VarietyEntry[]): boolean {
  for (let i = 1; i < entries.length; i++) {
    const prev = entries[i - 1];
    const curr = entries[i];

    // Check if effect AND primary color are identical
    if (
      prev.effectId === curr.effectId &&
      colorsEqual(prev.colors[0], curr.colors[0])
    ) {
      return false;
    }
  }
  return true;
}

/**
 * Compare two RGB color arrays for equality.
 */
function colorsEqual(a: number[], b: number[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((v, i) => v === b[i]);
}

/**
 * Variety Generator for Multi-Day Scheduling
 *
 * Ensures multi-day schedule plans never repeat the same look on
 * consecutive nights. Provides effect rotation, color emphasis shifting,
 * and energy level variation across a week.
 */
export interface VarietyEntry {
    dayIndex: number;
    dayLabel: string;
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
export declare function rotateColors(themeColors: number[][], dayIndex: number): number[][];
/**
 * Generate a variety plan for multiple days of scheduling.
 *
 * @param days    - Array of day labels (e.g., ["monday","tuesday",...] or dates)
 * @param config  - Theme colors, preferred effects, and options
 * @returns Array of VarietyEntry, one per day
 */
export declare function generateVarietyPlan(days: string[], config: VarietyConfig): VarietyEntry[];
/**
 * Validate that a variety plan has no consecutive duplicate looks.
 * Returns true if the plan passes validation.
 */
export declare function validateVarietyPlan(entries: VarietyEntry[]): boolean;

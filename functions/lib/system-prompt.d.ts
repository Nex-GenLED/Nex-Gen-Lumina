/**
 * Lumina AI System Prompt Template
 *
 * Constructs the full system prompt for Claude, injecting the user's
 * current lighting state, device configuration, and favorites.
 */
export interface ZoneState {
    id: string;
    color: number[];
    brightness: number;
    effect: string;
}
export interface ZoneConfig {
    id: string;
    startPixel: number;
    endPixel: number;
}
export interface DeviceConfig {
    totalPixels: number;
    zones: ZoneConfig[];
}
export interface LightingState {
    zones: ZoneState[];
}
/**
 * Build the full system prompt with user context injected.
 */
export declare function buildSystemPrompt(currentState: LightingState, deviceConfig: DeviceConfig, userFavorites: string[]): string;

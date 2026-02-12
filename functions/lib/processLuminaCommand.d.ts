/**
 * processLuminaCommand — Firebase Cloud Function
 *
 * Receives a voice-transcribed command from the Flutter app, sends it to
 * Claude with full lighting context, and returns structured WLED commands.
 *
 * Security: authenticated, rate-limited, input-validated, usage-logged.
 */
interface LuminaResponse {
    intent: string;
    responseText: string;
    commands: Array<{
        zone: string;
        effect: number;
        colors: number[][];
        brightness: number;
        speed?: number;
        intensity?: number;
    }> | null;
    previewColors: number[][] | null;
    clarificationOptions: string[] | null;
    navigationTarget: string | null;
    saveAsFavorite: string | null;
    confidence: number;
}
export declare const processLuminaCommand: import("firebase-functions/v2/https").CallableFunction<any, Promise<LuminaResponse>, unknown>;
export {};

/**
 * Scheduling System Prompt for Lumina AI
 *
 * Constructs the full system prompt for Claude when processing natural
 * language scheduling requests. Includes WLED effect knowledge, team
 * color databases, conflict resolution rules, and variety guidelines.
 */
export interface ScheduleEvent {
    id: string;
    name: string;
    zone: string;
    startTime: string;
    endTime: string;
    days: string[];
    effectId: number;
    colors: number[][];
    brightness: number;
    speed?: number;
    intensity?: number;
    recurring: boolean;
    priority?: number;
    triggerType?: "clock" | "sunrise" | "sunset";
    triggerOffset?: number;
}
export interface TeamInfo {
    name: string;
    league: string;
    abbreviation: string;
    primaryColor: number[];
    secondaryColor: number[];
    accentColor?: number[];
}
export interface AvailableEffect {
    id: number;
    name: string;
    category?: string;
}
export interface ScheduleContext {
    currentSchedule: ScheduleEvent[];
    userLocation: {
        timezone: string;
        latitude?: number;
        longitude?: number;
    };
    userTeams: TeamInfo[];
    availableZones: string[];
    availableEffects: AvailableEffect[];
    teamColorDatabase: Record<string, TeamInfo>;
    currentDateTime: string;
    sunriseTime?: string;
    sunsetTime?: string;
}
/**
 * Build the full scheduling system prompt with user context injected.
 */
export declare function buildSchedulingSystemPrompt(context: ScheduleContext): string;

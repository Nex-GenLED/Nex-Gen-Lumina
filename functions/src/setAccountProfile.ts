/**
 * setAccountProfile — Firebase Cloud Function (callable)
 *
 * THE single residential↔commercial activation path. Absorbs the two batches
 * that had already diverged (item #32):
 *   • lib/screens/commercial/onboarding/screens/review_go_live_screen.dart:113-124
 *     (CommercialOnboardingWizard "Go Live")
 *   • lib/features/installer/installer_setup_wizard.dart:1000-1052
 *     (installer commercial seed)
 * Both now call this function. Divergences the two had accumulated: the wizard
 * wrote profile_type + commercial_profile and hardcoded lat/lng 0.0; the
 * installer wrote real coords but neither of those fields; NEITHER wrote the
 * installations doc. All of that is reconciled here, once.
 *
 * WHY A CALLABLE (not a client batch): activation must write
 * /installations/{id} (site_mode + max_sub_users), a doc the customer does not
 * own and cannot write under any sane rule. A batch spanning /users and
 * /installations needs one atomic server-side authority. This is also what
 * lets firestore.rules drop the `|| request.auth != null` accommodation on
 * commercial_locations — the Admin SDK bypasses rules, so no client needs
 * cross-account write permission any more.
 *
 * Contract:
 *   request.data: {
 *     uid:                string,
 *     direction:          'commercial' | 'residential',
 *     businessHours?:     BusinessHours,           // commercial only
 *     commercialProfile?: object,                  // opaque passthrough
 *     location?: { locationName?, address?, lat?, lng?, channelConfigs? },
 *     teamNames?:         Record<slug, string>,    // see TEAM MAPPING below
 *   }
 *   response: SetAccountProfileResult {
 *     uid, direction, installationUpdated, locationWritten,
 *     businessHoursWritten, teamsMapped, alreadyInDirection,
 *   }
 *
 * IDEMPOTENT: every write is a merge:true set keyed by a fixed doc id, so a
 * rerun converges. Re-running in the same direction is a no-op that reports
 * alreadyInDirection: true (it still repairs any missing sub-doc — that is the
 * point, since the old non-atomic batches could half-fail).
 *
 * REVERSIBLE + NON-DESTRUCTIVE: direction:'residential' flips profile_type,
 * commercial_mode_enabled/override and max_sub_users back, and RETAINS
 * commercial_locations, brand_profile, commercial_hours and commercial_teams
 * as dormant data. commercialModeEnabledProvider gates on the flags, so
 * dormant docs are invisible to the app. A mis-fired revert therefore costs
 * nothing and re-converting restores the account instantly.
 *
 * Auth: the caller must be the account owner, OR hold a staff claim whose
 * dealerCode matches the target user's dealer_code, OR hold an admin/owner
 * claim. Mirrors firestore.rules hasStaffClaim()/hasAdminClaim(). There is
 * deliberately NO bare `request.auth != null` branch — that is the pattern
 * that caused the neighborhoods outage class and is banned.
 *
 * NOTE for the installer flow: installer_setup_wizard signs back in with its
 * cached staff custom token (not anonymously) before calling this, so the
 * staff claim is present. See installer_providers.dart staffToken.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:setAccountProfile
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

// admin.initializeApp() is called in index.js — do not call again here.

// ── Constants ───────────────────────────────────────────────────────────────

/** Sub-user allowance per site mode. Mirrors installer_setup_wizard.dart:831. */
export const MAX_SUB_USERS_COMMERCIAL = 20;
export const MAX_SUB_USERS_RESIDENTIAL = 5;

/** The single location doc id. Multi-location is Stage 5 — see the audit. */
export const PRIMARY_LOCATION_ID = "primary";

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
type DayKey = (typeof DAY_KEYS)[number];

/** HH:MM, 24-hour. */
const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;

// ── Business hours ──────────────────────────────────────────────────────────

/**
 * Deliberately dumb. Per-day open/close as 24h HH:MM strings plus a closed
 * flag; no timezone, no date math, no recurrence.
 *
 * CROSS-MIDNIGHT is the whole reason this exists: a bar closing at 02:00 is
 * `{ open: '16:00', close: '02:00' }`. close <= open means "closes the NEXT
 * day". Consumers must apply that rule; this function only validates and
 * stores. The residential autopilot window generator cannot express this at
 * all (every slot is built on a single calendar day) — that is a later slice.
 *
 * `closed: true` means closed all day; open/close are then ignored.
 *
 * Written to /users/{uid}/commercial_hours/primary — a NEW collection. It is
 * intentionally NOT `commercial_schedule`, the collection DayPartSchedulerService
 * reads: that scheduler has one caller in an orphaned screen and no data
 * writers, and Commit 1 removed the gate that deferred to it. Reusing its
 * collection would imply a handoff that does not exist.
 */
export interface DayHours {
  open?: string;
  close?: string;
  closed?: boolean;
}
export type BusinessHours = Partial<Record<DayKey, DayHours>>;

export function validateBusinessHours(input: unknown): BusinessHours {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    throw new HttpsError("invalid-argument", "businessHours must be an object");
  }
  const out: BusinessHours = {};
  for (const [day, raw] of Object.entries(input as Record<string, unknown>)) {
    if (!(DAY_KEYS as readonly string[]).includes(day)) {
      throw new HttpsError(
        "invalid-argument",
        `businessHours: unknown day '${day}' (expected ${DAY_KEYS.join(", ")})`
      );
    }
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
      throw new HttpsError(
        "invalid-argument",
        `businessHours.${day} must be an object`
      );
    }
    const d = raw as Record<string, unknown>;
    const closed = d.closed === true;
    const entry: DayHours = { closed };

    if (!closed) {
      for (const k of ["open", "close"] as const) {
        const v = d[k];
        if (typeof v !== "string" || !TIME_RE.test(v)) {
          throw new HttpsError(
            "invalid-argument",
            `businessHours.${day}.${k} must be 24-hour HH:MM (got ${JSON.stringify(v)})`
          );
        }
        entry[k] = v;
      }
    }
    out[day as DayKey] = entry;
  }
  return out;
}

// ── Team mapping ────────────────────────────────────────────────────────────

/**
 * Slug prefix → SportType.name (lib/features/sports_alerts/models/sport_type.dart).
 * Slugs look like `nfl_bills`, `ncaamb_jayhawks`. Longest prefix wins so
 * `ncaamb_` is not swallowed by `ncaa_`.
 */
const SPORT_PREFIXES: Array<[string, string]> = [
  ["ncaamb_", "ncaaMB"],
  ["ncaa_", "ncaaFB"],
  ["nwsl_", "nwsl"],
  ["fifa_", "fifa"],
  ["nfl_", "nfl"],
  ["nba_", "nba"],
  ["mlb_", "mlb"],
  ["nhl_", "nhl"],
  ["mls_", "mls"],
  ["cl_", "championsLeague"],
];

export function sportFromSlug(slug: string): string | null {
  for (const [prefix, sport] of SPORT_PREFIXES) {
    if (slug.startsWith(prefix)) return sport;
  }
  return null;
}

/** `nfl_bills` → `Bills`. A fallback only — see mapTeams. */
export function titleCaseSlugSuffix(slug: string): string {
  const idx = slug.indexOf("_");
  const suffix = idx >= 0 ? slug.slice(idx + 1) : slug;
  return suffix
    .split(/[-_]/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

/**
 * sports_team_priority (ordered slugs) → commercial_teams (CommercialTeam[]).
 * lib/models/commercial/commercial_team.dart — note fromJson HARD-CASTS
 * team_name and sport, so both MUST be present or every client read throws.
 *
 * team_name cannot be derived faithfully server-side: the real names live in
 * kTeamColors, a Dart compile-time const the server cannot see
 * (`nfl_bills` → 'Buffalo Bills', not 'Bills'). So the client passes
 * `teamNames` and we fall back to a title-cased slug suffix only to guarantee
 * the non-null contract. Slugs with an unrecognised prefix are SKIPPED rather
 * than written with a bogus sport — a wrong sport silently mis-drives game-day
 * automation, which is worse than an absent team.
 */
export function mapTeams(
  priority: string[],
  teamNames: Record<string, string> = {}
): Array<Record<string, unknown>> {
  const teams: Array<Record<string, unknown>> = [];
  let rank = 1;
  for (const slug of priority) {
    if (typeof slug !== "string" || !slug) continue;
    const sport = sportFromSlug(slug);
    if (sport === null) {
      logger.warn("setAccountProfile: skipping team slug with unknown sport", {
        slug,
      });
      continue;
    }
    teams.push({
      team_slug: slug,
      team_name: teamNames[slug] ?? titleCaseSlugSuffix(slug),
      sport,
      priority_rank: rank++,
      alert_intensity: "full",
      enable_game_day_mode: true,
    });
  }
  return teams;
}

// ── Auth ────────────────────────────────────────────────────────────────────

/**
 * Owner, dealer-scoped staff, or admin/owner claim. Mirrors the rule helpers
 * hasStaffClaim()/hasAdminClaim() in firestore.rules.
 *
 * `targetDealerCode` is the CUSTOMER's dealer_code; a staff session may only
 * act on their own dealer's customers. An owner-claim session carries no
 * dealerCode (mintStaffToken omits it deliberately) and is unscoped.
 */
export function assertCallerMayActOn(params: {
  callerUid: string | undefined;
  token: Record<string, unknown> | undefined;
  targetUid: string;
  targetDealerCode: string;
}): void {
  const { callerUid, token, targetUid, targetDealerCode } = params;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Sign-in required");
  }
  if (callerUid === targetUid) return; // owner

  const role = (token?.role as string) ?? "";
  if (role === "admin" || role === "owner") return;

  const dealerCode = (token?.dealerCode as string) ?? "";
  const isStaff = role === "installer" || role === "salesperson";
  if (isStaff && dealerCode !== "" && dealerCode === targetDealerCode) return;

  // Generic message: callers must not be able to probe dealer scoping.
  throw new HttpsError(
    "permission-denied",
    "Not authorized to change this account's profile type"
  );
}

// ── Request / response shapes ───────────────────────────────────────────────

export type Direction = "commercial" | "residential";

interface LocationInput {
  locationName?: string;
  address?: string;
  lat?: number;
  lng?: number;
  channelConfigs?: unknown[];
}

export interface SetAccountProfileResult {
  uid: string;
  direction: Direction;
  installationUpdated: boolean;
  locationWritten: boolean;
  businessHoursWritten: boolean;
  teamsMapped: number;
  alreadyInDirection: boolean;
}

// ── Core (exported for the emulator suite) ──────────────────────────────────

export async function runSetAccountProfile(
  req: CallableRequest
): Promise<SetAccountProfileResult> {
  const db = admin.firestore();
  const data = (req.data ?? {}) as Record<string, unknown>;

  const uid = data.uid;
  if (typeof uid !== "string" || !uid) {
    throw new HttpsError("invalid-argument", "uid is required");
  }
  const direction = data.direction;
  if (direction !== "commercial" && direction !== "residential") {
    throw new HttpsError(
      "invalid-argument",
      "direction must be 'commercial' or 'residential'"
    );
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", `user ${uid} not found`);
  }
  const user = userSnap.data() ?? {};

  assertCallerMayActOn({
    callerUid: req.auth?.uid,
    token: req.auth?.token as unknown as Record<string, unknown> | undefined,
    targetUid: uid,
    targetDealerCode: (user.dealer_code as string) ?? "",
  });

  const alreadyInDirection = (user.profile_type ?? "residential") === direction;
  const toCommercial = direction === "commercial";

  // Validate BEFORE opening the batch so a bad payload writes nothing.
  const hours =
    toCommercial && data.businessHours !== undefined
      ? validateBusinessHours(data.businessHours)
      : null;

  const location = (data.location ?? {}) as LocationInput;
  const teamNames = (data.teamNames ?? {}) as Record<string, string>;

  const batch = db.batch();

  // 1. User doc — flags always; commercial_profile / commercial_teams only on
  //    the way in. On revert we RETAIN both (see header: non-destructive).
  const userPatch: Record<string, unknown> = {
    profile_type: direction,
    commercial_mode_enabled: toCommercial,
    commercial_mode_override: toCommercial,
  };

  let teamsMapped = 0;
  if (toCommercial) {
    if (data.commercialProfile !== undefined) {
      if (
        data.commercialProfile === null ||
        typeof data.commercialProfile !== "object" ||
        Array.isArray(data.commercialProfile)
      ) {
        throw new HttpsError(
          "invalid-argument",
          "commercialProfile must be an object"
        );
      }
      // Stamp updated_at server-side: the callers cannot send a
      // FieldValue.serverTimestamp() sentinel through a callable payload
      // (it is not JSON-serializable), so the client map is plain data.
      userPatch.commercial_profile = {
        ...(data.commercialProfile as Record<string, unknown>),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      };
    }

    // Map the residential fan list into the commercial team model — the piece
    // a naive profile_type flip silently skips, leaving two unreconciled team
    // systems on the same account.
    const existingTeams = (user.commercial_teams as unknown[]) ?? [];
    if (existingTeams.length === 0) {
      const priority = (user.sports_team_priority as string[]) ?? [];
      const mapped = mapTeams(priority, teamNames);
      if (mapped.length > 0) {
        userPatch.commercial_teams = mapped;
        teamsMapped = mapped.length;
      }
    }
  }
  batch.set(userRef, userPatch, { merge: true });

  // 2. Installation doc — the reconciliation BOTH legacy batches skipped.
  //    invitation_service.dart:38-50 enforces max_sub_users live, so a
  //    converted account kept residential invite limits (5) forever.
  let installationUpdated = false;
  const installationId = user.installation_id;
  if (typeof installationId === "string" && installationId) {
    batch.set(
      db.collection("installations").doc(installationId),
      {
        site_mode: direction,
        max_sub_users: toCommercial
          ? MAX_SUB_USERS_COMMERCIAL
          : MAX_SUB_USERS_RESIDENTIAL,
      },
      { merge: true }
    );
    installationUpdated = true;
  } else {
    // Self-signup accounts have no installation yet. Not fatal — the flags
    // still apply — but the sub-user limit stays at its default until an
    // install links one, so surface it rather than failing silently.
    logger.warn("setAccountProfile: no installation_id; sub-user limit unchanged", {
      uid,
    });
  }

  // 3. Location stub — commercial only; retained (dormant) on revert.
  let locationWritten = false;
  if (toCommercial) {
    const locRef = userRef
      .collection("commercial_locations")
      .doc(PRIMARY_LOCATION_ID);
    const locSnap = await locRef.get();

    // Real coords where available — never the wizard's hardcoded 0.0. Fall
    // back to the user doc's own lat/lng before surrendering to null.
    const lat =
      typeof location.lat === "number"
        ? location.lat
        : typeof user.latitude === "number"
        ? user.latitude
        : null;
    const lng =
      typeof location.lng === "number"
        ? location.lng
        : typeof user.longitude === "number"
        ? user.longitude
        : null;

    const locPatch: Record<string, unknown> = {
      location_id: PRIMARY_LOCATION_ID,
      active: true,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (location.locationName) locPatch.location_name = location.locationName;
    if (location.address) locPatch.address = location.address;
    if (lat !== null) locPatch.lat = lat;
    if (lng !== null) locPatch.lng = lng;
    if (location.channelConfigs !== undefined) {
      locPatch.channel_configs = location.channelConfigs;
    }

    // First write only: seed the fields a rerun must not stomp.
    if (!locSnap.exists) {
      locPatch.org_id = "";
      locPatch.controller_id = "";
      locPatch.business_hours_id = "";
      locPatch.schedule_id = "";
      locPatch.teams_config_id = "";
      locPatch.is_using_org_template = false;
      locPatch.created_at = admin.firestore.FieldValue.serverTimestamp();
      locPatch.managers = [
        {
          user_id: uid,
          role: "corporateAdmin",
          assigned_at: new Date().toISOString(),
        },
      ];
      if (locPatch.location_name === undefined) {
        locPatch.location_name = "Primary Location";
      }
      if (locPatch.channel_configs === undefined) locPatch.channel_configs = [];
      if (locPatch.lat === undefined) locPatch.lat = null;
      if (locPatch.lng === undefined) locPatch.lng = null;
    }

    batch.set(locRef, locPatch, { merge: true });
    locationWritten = true;
  }

  // 4. Business hours — commercial only; retained (dormant) on revert.
  let businessHoursWritten = false;
  if (hours !== null) {
    batch.set(
      userRef.collection("commercial_hours").doc(PRIMARY_LOCATION_ID),
      {
        location_id: PRIMARY_LOCATION_ID,
        days: hours,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    businessHoursWritten = true;
  }

  await batch.commit();

  logger.info("setAccountProfile: committed", {
    uid,
    direction,
    callerUid: req.auth?.uid,
    callerRole: (req.auth?.token as Record<string, unknown> | undefined)?.role ?? "owner",
    alreadyInDirection,
    installationUpdated,
    locationWritten,
    businessHoursWritten,
    teamsMapped,
  });

  return {
    uid,
    direction,
    installationUpdated,
    locationWritten,
    businessHoursWritten,
    teamsMapped,
    alreadyInDirection,
  };
}

export const setAccountProfile = onCall(
  { region: "us-central1" },
  async (req): Promise<SetAccountProfileResult> => runSetAccountProfile(req)
);

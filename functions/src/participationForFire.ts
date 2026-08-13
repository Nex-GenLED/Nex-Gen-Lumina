/**
 * participationForFire — S3b server side. PURE.
 *
 * Decides whether a server-side fire may honour a controller's denormalized
 * participating-channel set, and refuses rather than guesses when it cannot.
 *
 * WHY REFUSING IS THE DEFAULT. The set says which of the customer's channels
 * take part in an event. Get it wrong in one direction and the patio they
 * deliberately excluded lights up; get it wrong in the other and half the house
 * stays dark. Neither is recoverable by the customer, who is away. A fire that
 * does not happen is a disappointment; a fire on the wrong channels is a
 * support call and a trust problem. So: **no data, no fire.**
 *
 * NOT WIRED YET. S5 owns the planner that consumes this. It is written and
 * tested now because S3b is the data half and shipping data with no defined
 * reader is how a field ends up serialized, copyWith-able, read by nobody and
 * always null — which is exactly the state `participatingChannelIndices` is in
 * today (docs/audits/CHANNEL_MAPPING_AUDIT_2026-05.md:459).
 */

/** Matches the Dart-side constant in participation_denormalizer.dart. */
export const PARTICIPATION_MAX_AGE_MS = 90 * 86_400_000;

export interface ParticipationFields {
  participating_channels?: unknown;
  participating_channels_at?: { toMillis(): number } | null;
  participating_channels_device_ids?: unknown;
  participating_channels_source?: unknown;
}

export type ParticipationVerdict =
  | {
      usable: true;
      channels: number[];
      /**
       * #67. The controller's FULL channel set as the healer published it, so a
       * fire can name every channel and darken the excluded ones. `null` when
       * the field is absent or malformed — the caller must then fall back to
       * naming only the participating channels and log `partition_unavailable`.
       * Never synthesised from `channels`: "the set we light" and "the set that
       * exists" are different facts, and conflating them would silently make
       * every fire look fully partitioned.
       */
      deviceChannelIds: number[] | null;
      ageMs: number;
      reason: "ok";
    }
  | { usable: false; channels: null; ageMs: number | null; reason: string };

const asIntArray = (v: unknown): number[] | null => {
  if (!Array.isArray(v)) return null;
  const out: number[] = [];
  for (const x of v) {
    if (typeof x !== "number" || !Number.isInteger(x) || x < 0) return null;
    out.push(x);
  }
  return out;
};

/**
 * Resolve the participating set for a fire.
 *
 * Refusals, each distinct so the dispatcher can report WHY rather than logging
 * an undifferentiated skip:
 *
 *   never_resolved        — the app has never published for this controller.
 *                           Expected for every controller until its owner next
 *                           opens the app on the LAN. There is no server-side
 *                           backfill possible: the input (the hardware bus list)
 *                           is only readable over /json/cfg, on-LAN.
 *   malformed             — present but not a clean integer array.
 *   no_timestamp          — present with no resolve time, so age is unknowable.
 *                           Treated as unusable rather than assumed fresh.
 *   stale:<days>d         — older than PARTICIPATION_MAX_AGE_MS.
 *
 * An EMPTY array is usable and means "the customer excluded every channel".
 * That is a real answer, and the caller should skip the fire because there is
 * nothing to light — not because the data is missing. The distinction matters
 * for what the operator is told.
 */
export function participationForFire(
  controller: ParticipationFields | null | undefined,
  nowMs: number,
  maxAgeMs: number = PARTICIPATION_MAX_AGE_MS
): ParticipationVerdict {
  if (!controller) {
    return { usable: false, channels: null, ageMs: null, reason: "never_resolved" };
  }

  const raw = controller.participating_channels;
  if (raw === undefined || raw === null) {
    return { usable: false, channels: null, ageMs: null, reason: "never_resolved" };
  }

  const channels = asIntArray(raw);
  if (channels === null) {
    return { usable: false, channels: null, ageMs: null, reason: "malformed" };
  }

  const at = controller.participating_channels_at;
  if (!at || typeof at.toMillis !== "function") {
    return { usable: false, channels: null, ageMs: null, reason: "no_timestamp" };
  }

  const ageMs = Math.max(0, nowMs - at.toMillis());
  if (ageMs > maxAgeMs) {
    return {
      usable: false,
      channels: null,
      ageMs,
      reason: `stale:${Math.round(ageMs / 86_400_000)}d`,
    };
  }

  return {
    usable: true,
    channels,
    deviceChannelIds: asIntArray(controller.participating_channels_device_ids),
    ageMs,
    reason: "ok",
  };
}

/**
 * True when a usable verdict means "there is nothing to light".
 *
 * Kept separate from [participationForFire] so the caller can distinguish
 * "we do not know" from "we know, and the answer is none" — they look the same
 * at the fire (no command) and are completely different to explain.
 */
export function isEmptyParticipation(v: ParticipationVerdict): boolean {
  return v.usable && v.channels.length === 0;
}

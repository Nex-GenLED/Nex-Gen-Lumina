/**
 * commandHygiene — the server's terminal transitions on a command document,
 * written so a concurrent bridge transition always wins.
 *
 * THE CLASS. Two server writers move a command the bridge may be touching at
 * the same moment:
 *   - the sweeper: pending → expired, and (A1) executing → failed/stuck_executing
 *   - the dispatcher (A3): executing → failed/stuck_executing for the
 *     controller it is about to fire into
 * Before A1 the sweeper "re-checked" the status it had just QUERIED, which is
 * not a guard at all: a bridge claim landing between the query and the batch
 * commit was overwritten. That was tolerable while nothing acted on `expired`
 * (the bridge's later `completed` PATCH rewrote status). It is not tolerable
 * once the dispatcher RETRIES on `expired` and `stuck_executing` (A2): the
 * intermediate wrong state would mint a duplicate fire.
 *
 * THE GUARD. Every transition is an update with a `lastUpdateTime`
 * precondition equal to the snapshot the decision was made on. If the bridge
 * (or anyone) wrote the doc after that read, Firestore refuses the write with
 * FAILED_PRECONDITION and the newer state stands — "completed wins". One
 * write, no extra read, and the semantics are Firestore's own rather than a
 * re-implementation in a transaction body.
 */

import * as admin from "firebase-admin";
import { STATUS_EXPIRED, STUCK_EXECUTING_ERROR } from "./commandSafety";

/** True when [err] is Firestore's FAILED_PRECONDITION (gRPC 9). */
export function isPreconditionFailure(err: unknown): boolean {
  const code = (err as { code?: unknown } | null)?.code;
  return code === 9 || code === "failed-precondition" || code === "FAILED_PRECONDITION";
}

export type GuardedWriteResult = "written" | "raced";

/**
 * Update [ref] only if it has not changed since [readUpdateTime].
 * Returns "raced" — and writes nothing — when it has. Any other error throws.
 */
export async function updateIfUnchanged(
  ref: admin.firestore.DocumentReference,
  readUpdateTime: admin.firestore.Timestamp | undefined,
  data: Record<string, unknown>
): Promise<GuardedWriteResult> {
  if (!readUpdateTime) {
    // No read time means we never saw the doc; refusing is the safe answer.
    return "raced";
  }
  try {
    await ref.update(data, { lastUpdateTime: readUpdateTime });
    return "written";
  } catch (err) {
    if (isPreconditionFailure(err)) return "raced";
    throw err;
  }
}

/** The fields a stuck-executing termination writes. */
export function stuckExecutingFields(): Record<string, unknown> {
  return {
    status: "failed",
    error: STUCK_EXECUTING_ERROR,
    stuckSweptAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * executing → failed / stuck_executing, unless the bridge reported first.
 *
 * `completedAt` is deliberately NOT written: it is the bridge's field, and the
 * reconcile latency (createdAt → completedAt) must stay null for a command the
 * bridge never finished rather than measure the sweeper's cadence.
 */
export async function markStuckExecuting(
  ref: admin.firestore.DocumentReference,
  readUpdateTime: admin.firestore.Timestamp | undefined
): Promise<GuardedWriteResult> {
  return updateIfUnchanged(ref, readUpdateTime, stuckExecutingFields());
}

/** pending → expired, unless the bridge claimed it first. */
export async function markExpired(
  ref: admin.firestore.DocumentReference,
  readUpdateTime: admin.firestore.Timestamp | undefined,
  errorText: string
): Promise<GuardedWriteResult> {
  return updateIfUnchanged(ref, readUpdateTime, {
    status: STATUS_EXPIRED,
    error: errorText,
    expiredAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Run [fn] over [items] with at most [limit] in flight. Results in input order.
 * Small and local on purpose: the sweeper replaced a 450-doc batch (where one
 * failed precondition would abort the whole batch) with per-doc guarded writes.
 */
export async function mapLimit<T, R>(
  items: T[],
  limit: number,
  fn: (item: T) => Promise<R>
): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

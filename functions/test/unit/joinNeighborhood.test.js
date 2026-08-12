// F-3 — coverage for the joinNeighborhood callable's pure decision layer.
//
// The callable is the ONLY join path after F-3: rules deny the client both the
// cross-tenant group read and self-insertion into memberUids. So every refusal
// below is a rule that used to be "enforced app-side" and now has to hold
// server-side. Runs against tsc-compiled lib/ (same convention as
// fanoutRateLimit / fanoutMutualMembership).
//
// The I/O half (Firestore resolve + batch write) is exercised by the emulator
// rules tests; these lock the branches that decide ALLOW vs REFUSE.

const {
  normalizeInviteCode,
  evaluateJoinRateLimit,
  decideJoin,
  MAX_CREW_SIZE,
  JOIN_COOLDOWN_MS,
  JOIN_CEILING_PER_WINDOW,
  JOIN_RATE_WINDOW_MS,
} = require("../../lib/joinNeighborhood");

const NOW = 1_000_000_000;
const UID = "caller-uid";
const OTHER = "someone-else";

describe("normalizeInviteCode", () => {
  test("uppercases and trims a valid code", () => {
    expect(normalizeInviteCode("  ab2c3d  ")).toBe("AB2C3D");
  });

  test("accepts a canonical generated code", () => {
    expect(normalizeInviteCode("XYZ789")).toBe("XYZ789");
  });

  test("rejects non-strings", () => {
    expect(normalizeInviteCode(undefined)).toBe("");
    expect(normalizeInviteCode(null)).toBe("");
    expect(normalizeInviteCode(123456)).toBe("");
    expect(normalizeInviteCode({})).toBe("");
  });

  test("rejects wrong length", () => {
    expect(normalizeInviteCode("ABC12")).toBe("");
    expect(normalizeInviteCode("ABC1234")).toBe("");
    expect(normalizeInviteCode("")).toBe("");
  });

  // The generator omits I, O, 0 and 1 as confusables. A code containing them
  // cannot exist, so rejecting the shape costs an attacker a Firestore query
  // and still burns a rate-limit slot.
  test("rejects characters outside the generator alphabet", () => {
    expect(normalizeInviteCode("ABCDI2")).toBe("");
    expect(normalizeInviteCode("ABCD02")).toBe("");
    expect(normalizeInviteCode("ABCD12")).toBe("");
    expect(normalizeInviteCode("ABC-12")).toBe("");
  });
});

describe("evaluateJoinRateLimit", () => {
  test("allows a first attempt and records it", () => {
    const d = evaluateJoinRateLimit(undefined, NOW);
    expect(d.allowed).toBe(true);
    expect(d.nextState.attempts).toEqual([NOW]);
    expect(d.nextState.lastAttemptMs).toBe(NOW);
  });

  test("rejects inside the cooldown", () => {
    const state = { attempts: [NOW], lastAttemptMs: NOW };
    const d = evaluateJoinRateLimit(state, NOW + JOIN_COOLDOWN_MS - 1);
    expect(d.allowed).toBe(false);
    expect(d.reason).toBe("cooldown");
    expect(d.retryAfterMs).toBe(1);
  });

  test("allows once the cooldown elapses", () => {
    const state = { attempts: [NOW], lastAttemptMs: NOW };
    const d = evaluateJoinRateLimit(state, NOW + JOIN_COOLDOWN_MS);
    expect(d.allowed).toBe(true);
  });

  // THE TWO LIMBS DO NOT OVERLAP, and that is by design.
  // Attempts spaced by the 18s cooldown span 4 x 18s = 72s to reach 5, which is
  // already outside the 60s window — so the trim drops the oldest and the
  // ceiling never engages. Sequential, cooldown-respecting callers are governed
  // ENTIRELY by the cooldown. The ceiling exists for the case the cooldown
  // cannot see: a concurrent burst, where several requests read the same state
  // before any writes. That is why the caller wraps this in a transaction.
  test("sequential cooldown-spaced attempts never reach the ceiling", () => {
    const attempts = [];
    for (let i = 0; i < JOIN_CEILING_PER_WINDOW; i++) {
      attempts.push(NOW + i * JOIN_COOLDOWN_MS);
    }
    const last = attempts[attempts.length - 1];
    const d = evaluateJoinRateLimit(
      { attempts, lastAttemptMs: last },
      last + JOIN_COOLDOWN_MS
    );
    expect(d.allowed).toBe(true);
  });

  test("rejects at the rolling ceiling after a concurrent burst", () => {
    // A burst that raced the transaction: 5 attempts inside one second.
    const attempts = [NOW, NOW + 1, NOW + 2, NOW + 3, NOW + 4];
    const state = { attempts, lastAttemptMs: NOW + 4 };
    // Evaluate past the cooldown so the cooldown limb cannot be what refuses.
    const d = evaluateJoinRateLimit(state, NOW + JOIN_COOLDOWN_MS + 5_000);
    expect(d.allowed).toBe(false);
    expect(d.reason).toBe("ceiling");
    expect(d.retryAfterMs).toBeGreaterThan(0);
  });

  test("trims attempts outside the window so state cannot grow unbounded", () => {
    const stale = [NOW - JOIN_RATE_WINDOW_MS - 5_000, NOW - JOIN_RATE_WINDOW_MS - 1];
    const d = evaluateJoinRateLimit(
      { attempts: stale, lastAttemptMs: stale[1] },
      NOW
    );
    expect(d.allowed).toBe(true);
    // Both stale entries dropped; only the fresh attempt survives.
    expect(d.nextState.attempts).toEqual([NOW]);
  });

  test("ignores malformed attempt entries", () => {
    const d = evaluateJoinRateLimit(
      { attempts: ["nope", null, undefined], lastAttemptMs: undefined },
      NOW
    );
    expect(d.allowed).toBe(true);
    expect(d.nextState.attempts).toEqual([NOW]);
  });
});

describe("decideJoin", () => {
  const privateGroup = {
    exists: true,
    inviteCode: "AB2C3D",
    isPublic: false,
    memberUids: [OTHER],
  };

  test("good code on a private crew succeeds", () => {
    const d = decideJoin({
      group: privateGroup,
      callerUid: UID,
      submittedCode: "AB2C3D",
      memberDocCount: 1,
    });
    expect(d.ok).toBe(true);
    expect(d.alreadyMember).toBeUndefined();
  });

  test("wrong code is refused", () => {
    const d = decideJoin({
      group: privateGroup,
      callerUid: UID,
      submittedCode: "ZZZZZZ",
      memberDocCount: 1,
    });
    expect(d.ok).toBe(false);
    expect(d.reason).toBe("invalid_code");
  });

  // THE F-3 REGRESSION GUARD. This is precisely what the removed rules clause
  // allowed: join a private crew with no credential at all.
  test("no code on a private crew is refused", () => {
    const d = decideJoin({
      group: privateGroup,
      callerUid: UID,
      submittedCode: "",
      memberDocCount: 1,
    });
    expect(d.ok).toBe(false);
    expect(d.reason).toBe("code_required");
  });

  test("no code on a PUBLIC crew succeeds (the discovery path)", () => {
    const d = decideJoin({
      group: { ...privateGroup, isPublic: true },
      callerUid: UID,
      submittedCode: "",
      memberDocCount: 1,
    });
    expect(d.ok).toBe(true);
  });

  test("missing group is refused", () => {
    const d = decideJoin({
      group: { exists: false },
      callerUid: UID,
      submittedCode: "AB2C3D",
      memberDocCount: 0,
    });
    expect(d.ok).toBe(false);
    expect(d.reason).toBe("group_not_found");
  });

  test("existing member is idempotent, not an error", () => {
    const d = decideJoin({
      group: { ...privateGroup, memberUids: [OTHER, UID] },
      callerUid: UID,
      submittedCode: "",
      memberDocCount: 2,
    });
    expect(d.ok).toBe(true);
    expect(d.alreadyMember).toBe(true);
  });

  test("full crew is refused", () => {
    const d = decideJoin({
      group: privateGroup,
      callerUid: UID,
      submittedCode: "AB2C3D",
      memberDocCount: MAX_CREW_SIZE,
    });
    expect(d.ok).toBe(false);
    expect(d.reason).toBe("crew_full");
  });

  // A group with no stored code must not be matchable by an empty submission —
  // otherwise "" === "" would let a malformed code into a private crew.
  test("empty stored code never matches", () => {
    const d = decideJoin({
      group: { exists: true, inviteCode: "", isPublic: false, memberUids: [] },
      callerUid: UID,
      submittedCode: "",
      memberDocCount: 0,
    });
    expect(d.ok).toBe(false);
    // Falls to code_required, not invalid_code: no code was submitted.
    expect(d.reason).toBe("code_required");
  });

  test("stored code is compared case-insensitively", () => {
    const d = decideJoin({
      group: { ...privateGroup, inviteCode: "ab2c3d" },
      callerUid: UID,
      submittedCode: "AB2C3D",
      memberDocCount: 1,
    });
    expect(d.ok).toBe(true);
  });

  test("malformed memberUids does not crash or grant membership", () => {
    const d = decideJoin({
      group: { exists: true, inviteCode: "AB2C3D", isPublic: false, memberUids: "nope" },
      callerUid: UID,
      submittedCode: "AB2C3D",
      memberDocCount: 0,
    });
    expect(d.ok).toBe(true);
    expect(d.alreadyMember).toBeUndefined();
  });
});

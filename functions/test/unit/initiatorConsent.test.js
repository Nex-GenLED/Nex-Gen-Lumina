// #71 — the initiator exemption covers PAUSE, never CONSENT.
//
// TYLER'S DECISION, 2026-08-13, quoted because the precedence is a product call:
//
//   "the initiator exemption extends to participationStatus (pause) in
//    initiateSyncSession, but NEVER overrides syncConsent. Pause is a mood;
//    consent is a contract. A paused initiator joins and can host their own
//    session; an explicitly opted-out initiator gets a LEGIBLE refusal telling
//    them their consent setting blocks it — never a silent re-opt-in, never a
//    silent drop."
//
// THE DEFECT, found while closing #69. `initiateSyncSession` skipped any member
// whose participationStatus was paused/optedOut with no exemption for the
// caller, though initiatorUid is known at :70 and token-verified at :79. The
// paused initiator dropped out of `participants`, so host selection could not
// choose them either — they started a session they neither joined nor hosted.

const {
  initiatorConsentVerdict,
  memberSkippedForSession,
  chooseHost,
} = require("../../lib/initiateSyncSession");

const CATEGORY = "gameDay";
const EVENT = "evt_1";

const consent = (over) =>
  Object.assign(
    {
      consentExists: true,
      categoryOptIns: { [CATEGORY]: true },
      skipNextEventIds: [],
      category: CATEGORY,
      eventId: EVENT,
    },
    over || {}
  );

describe("#71 (a) — a PAUSED initiator joins and can host", () => {
  test("pause never skips the initiator", () => {
    expect(memberSkippedForSession(true, "paused")).toBe(false);
  });

  test("nor does participationStatus optedOut — it is not consent", () => {
    // participationStatus:"optedOut" and syncConsent opt-out are DIFFERENT
    // fields. The decision draws its line at participationStatus vs
    // syncConsent, so the exemption covers this field whole, exactly as #69's
    // fix covers isMemberSkipped whole.
    expect(memberSkippedForSession(true, "optedOut")).toBe(false);
  });

  test("a paused initiator in participants is host-eligible", () => {
    // The bug was upstream of host selection: dropped from participants, the
    // initiator could not be chosen at all. In participants, the existing
    // preference order reaches them.
    expect(chooseHost(["uid_A"], undefined, "uid_A")).toBe("uid_A");
    expect(chooseHost(["uid_A", "uid_B"], "uid_missing", "uid_A")).toBe("uid_A");
  });

  test("the creator still outranks the initiator when both participate", () => {
    expect(chooseHost(["uid_C", "uid_A"], "uid_C", "uid_A")).toBe("uid_C");
  });

  test("neither present -> first participant, unchanged", () => {
    expect(chooseHost(["uid_B"], "uid_C", "uid_A")).toBe("uid_B");
  });
});

describe("#71 (b) — an OPTED-OUT initiator gets a legible refusal", () => {
  test("category opt-out -> consent_blocked, category named", () => {
    const v = initiatorConsentVerdict(
      consent({ categoryOptIns: { [CATEGORY]: false } })
    );
    expect(v.ok).toBe(false);
    expect(v.reason).toBe("consent_blocked");
    expect(v.message).toContain(CATEGORY);
    // Actionable, not merely negative.
    expect(v.message).toContain("Turn it on");
  });

  test("no consent doc -> consent_missing, a DIFFERENT reason", () => {
    // Absence is not an explicit "no". The remedy differs — never answered
    // versus answered no — so conflating them would misdirect the fix.
    const v = initiatorConsentVerdict(consent({ consentExists: false }));
    expect(v.ok).toBe(false);
    expect(v.reason).toBe("consent_missing");
  });

  test("skip-next on THIS event -> skip_next_active, narrower and named", () => {
    const v = initiatorConsentVerdict(consent({ skipNextEventIds: [EVENT] }));
    expect(v.ok).toBe(false);
    expect(v.reason).toBe("skip_next_active");
  });

  test("skip-next on a DIFFERENT event does not block", () => {
    expect(initiatorConsentVerdict(consent({ skipNextEventIds: ["other"] })).ok)
      .toBe(true);
  });

  test("every refusal carries a distinct reason — no undifferentiated 'blocked'", () => {
    const reasons = new Set(
      [
        consent({ consentExists: false }),
        consent({ categoryOptIns: {} }),
        consent({ skipNextEventIds: [EVENT] }),
      ].map((a) => initiatorConsentVerdict(a).reason)
    );
    expect(reasons.size).toBe(3);
  });
});

// THE PRECEDENCE TEST. This is the decision in one assertion.
describe("#71 (c) — paused AND opted-out: CONSENT WINS", () => {
  test("consent blocks even though pause would have been exempted", () => {
    // Pause is exempted...
    expect(memberSkippedForSession(true, "paused")).toBe(false);
    // ...and consent still refuses. The exemption cannot reach it, because
    // participationStatus is not an input to the consent verdict at all.
    const v = initiatorConsentVerdict(
      consent({ categoryOptIns: { [CATEGORY]: false } })
    );
    expect(v.ok).toBe(false);
    expect(v.reason).toBe("consent_blocked");
  });

  test("the consent verdict takes no participationStatus input, by design", () => {
    // Structural, not behavioural: if a future edit threads pause into this
    // function, the exemption could start overriding a contract. Passing it is
    // inert today and this pins that.
    const withPause = initiatorConsentVerdict(
      Object.assign(consent({ categoryOptIns: { [CATEGORY]: false } }), {
        participationStatus: "paused",
      })
    );
    expect(withPause.reason).toBe("consent_blocked");
  });
});

describe("#71 (d,e) — NON-initiators are unchanged", () => {
  test("paused non-initiator is still skipped", () => {
    expect(memberSkippedForSession(false, "paused")).toBe(true);
  });

  test("optedOut non-initiator is still skipped", () => {
    expect(memberSkippedForSession(false, "optedOut")).toBe(true);
  });

  test("active non-initiator participates", () => {
    expect(memberSkippedForSession(false, "active")).toBe(false);
    expect(memberSkippedForSession(false, undefined)).toBe(false);
  });
});

describe("#71 (f) — an ACTIVE initiator is unchanged", () => {
  test("passes consent and is not skipped", () => {
    expect(initiatorConsentVerdict(consent()).ok).toBe(true);
    expect(memberSkippedForSession(true, "active")).toBe(false);
  });
});

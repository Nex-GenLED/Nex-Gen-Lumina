/**
 * Unit tests for claimCustomerByEmail (residential path audit §9.1 item 4).
 *
 * Runs against the tsc-compiled output in lib/ — `npm run build` first.
 * No emulator, no firebase-admin IO: runClaimCustomerByEmail is
 * dependency-injected so the auth lookup, the profile read and the merge can
 * be exercised against fakes.
 *
 * What this unblocks: when the installer wizard hits `email-already-in-use`, it
 * recovers the customer's uid with a client query scoped
 * `where('dealer_code', == myDealerCode)` — the only shape the staff read rule
 * allows. An account with no dealer_code, or no /users document at all (32 in
 * production), is invisible to that query and the install hard-stopped with
 * "contact support".
 */

const {
  assertStaffMayClaim,
  planProfileRepair,
  runClaimCustomerByEmail,
} = require("../../lib/claimCustomerByEmail");

const UID = "existing_customer_uid";
const EMAIL = "customer@example.test";

/** Fake Firestore holding a single users/{uid} document. */
function makeDb(initial) {
  const state = { doc: initial ? { ...initial } : undefined, writes: [] };
  return {
    state,
    collection(path) {
      if (path !== "users") throw new Error(`unexpected collection ${path}`);
      return {
        doc(id) {
          return {
            async get() {
              return {
                exists: state.doc !== undefined,
                data: () => state.doc,
              };
            },
            async set(data, options) {
              state.writes.push({ id, data, options });
              state.doc = { ...(state.doc ?? {}), ...data };
            },
          };
        },
      };
    },
  };
}

function makeAuth(user) {
  return {
    async getUserByEmail(email) {
      if (!user || user.email !== email) {
        const err = new Error("auth/user-not-found");
        err.code = "auth/user-not-found";
        throw err;
      }
      return user;
    },
  };
}

function deps({ dbDoc, authUser }) {
  return {
    db: makeDb(dbDoc),
    auth: makeAuth(authUser),
    serverTimestamp: () => "SERVER_TIMESTAMP",
  };
}

const installerToken = { role: "installer", dealerCode: "07" };
const authUser = {
  uid: UID,
  email: EMAIL,
  displayName: "Real Customer",
  metadata: { creationTime: "2026-05-01T12:00:00.000Z" },
};

describe("assertStaffMayClaim", () => {
  it("rejects an unauthenticated caller", () => {
    expect(() =>
      assertStaffMayClaim({ callerUid: undefined, token: installerToken }),
    ).toThrow(/Sign-in required/);
  });

  it("rejects an ordinary signed-in customer", () => {
    // The banned `request.auth != null` arm: this function can stamp a
    // dealer_code onto an account the caller does not own.
    expect(() =>
      assertStaffMayClaim({ callerUid: "some_customer", token: {} }),
    ).toThrow(/Not authorized/);
  });

  it("rejects a staff claim with no dealerCode", () => {
    expect(() =>
      assertStaffMayClaim({
        callerUid: "staff",
        token: { role: "installer" },
      }),
    ).toThrow(/Not authorized/);
  });

  it("accepts an installer and returns their dealer code", () => {
    expect(
      assertStaffMayClaim({ callerUid: "staff", token: installerToken }),
    ).toBe("07");
  });

  it("accepts a salesperson", () => {
    expect(
      assertStaffMayClaim({
        callerUid: "staff",
        token: { role: "salesperson", dealerCode: "07" },
      }),
    ).toBe("07");
  });

  it("accepts an unscoped admin", () => {
    expect(
      assertStaffMayClaim({ callerUid: "adm", token: { role: "admin" } }),
    ).toBe("");
  });
});

describe("planProfileRepair", () => {
  it("treats an absent document as needing a skeleton", () => {
    const plan = planProfileRepair({ existing: undefined, callerDealerCode: "07" });
    expect(plan.needsSkeleton).toBe(true);
    expect(plan.stampDealerCode).toBe(true);
  });

  it("treats a STUB as needing a skeleton — exists is not enough", () => {
    // The 25 production stubs are exactly this shape.
    const plan = planProfileRepair({
      existing: { fcmToken: "tok", referralCode: "ABC" },
      callerDealerCode: "07",
    });
    expect(plan.needsSkeleton).toBe(true);
  });

  it("leaves a real profile alone", () => {
    const plan = planProfileRepair({
      existing: { owner_id: UID, dealer_code: "07" },
      callerDealerCode: "07",
    });
    expect(plan.needsSkeleton).toBe(false);
    expect(plan.stampDealerCode).toBe(false);
  });

  it("stamps dealer_code only when it is absent", () => {
    expect(
      planProfileRepair({
        existing: { owner_id: UID },
        callerDealerCode: "07",
      }).stampDealerCode,
    ).toBe(true);
  });

  it("flags another dealer's customer as a conflict", () => {
    const plan = planProfileRepair({
      existing: { owner_id: UID, dealer_code: "99" },
      callerDealerCode: "07",
    });
    expect(plan.conflictingDealerCode).toBe(true);
    expect(plan.stampDealerCode).toBe(false);
  });

  it("an unscoped admin neither stamps nor conflicts", () => {
    const plan = planProfileRepair({
      existing: { owner_id: UID, dealer_code: "99" },
      callerDealerCode: "",
    });
    expect(plan.conflictingDealerCode).toBe(false);
    expect(plan.stampDealerCode).toBe(false);
  });
});

describe("runClaimCustomerByEmail", () => {
  const call = (d, email = EMAIL, token = installerToken) =>
    runClaimCustomerByEmail({
      deps: d,
      callerUid: "staff_installer_0107",
      token,
      email,
    });

  it("THE FIX: an Auth account with NO profile document gets the skeleton", async () => {
    const d = deps({ dbDoc: undefined, authUser });
    const result = await call(d);

    expect(result.uid).toBe(UID);
    expect(result.profileCreated).toBe(true);
    expect(result.dealerCodeStamped).toBe(true);
    expect(result.dealerCode).toBe("07");

    const written = d.db.state.writes[0];
    expect(written.options).toEqual({ merge: true });
    // The exact key set UserModel.fromJson casts non-null.
    expect(written.data.id).toBe(UID);
    expect(written.data.owner_id).toBe(UID);
    expect(written.data.email).toBe(EMAIL);
    expect(written.data.display_name).toBe("Real Customer");
    expect(written.data.created_at).toBeInstanceOf(Date);
    expect(written.data.updated_at).toBe("SERVER_TIMESTAMP");
    expect(written.data.installation_role).toBe("unlinked");
    expect(written.data.dealer_code).toBe("07");
  });

  it("repairs a STUB without dropping what the stub carried", async () => {
    const d = deps({
      dbDoc: { fcmToken: "tok", referralCode: "ABC" },
      authUser,
    });
    const result = await call(d);

    expect(result.profileCreated).toBe(true);
    // merge:true and the patch never mentions the stub's own fields.
    expect(d.db.state.writes[0].data.fcmToken).toBeUndefined();
    expect(d.db.state.doc.fcmToken).toBe("tok");
    expect(d.db.state.doc.owner_id).toBe(UID);
  });

  it("stamps dealer_code on a self-registered customer without touching "
     + "their profile", async () => {
    const d = deps({
      dbDoc: {
        owner_id: UID,
        id: UID,
        email: EMAIL,
        display_name: "Self Registered",
        installation_role: "unlinked",
      },
      authUser,
    });
    const result = await call(d);

    expect(result.profileCreated).toBe(false);
    expect(result.dealerCodeStamped).toBe(true);
    expect(d.db.state.writes[0].data).toEqual({
      updated_at: "SERVER_TIMESTAMP",
      dealer_code: "07",
    });
    expect(d.db.state.doc.display_name).toBe("Self Registered");
  });

  it("REFUSES to take another dealer's customer", async () => {
    const d = deps({
      dbDoc: { owner_id: UID, dealer_code: "99" },
      authUser,
    });
    await expect(call(d)).rejects.toThrow(/another dealer/);
    expect(d.db.state.writes).toHaveLength(0);
  });

  it("never downgrades a linked customer's installation_role", async () => {
    const d = deps({
      dbDoc: { installation_role: "primary", dealer_code: "07" },
      authUser,
    });
    const result = await call(d);
    expect(result.profileCreated).toBe(true);
    expect(d.db.state.writes[0].data.installation_role).toBeUndefined();
    expect(result.installationRole).toBe("primary");
  });

  it("keeps an existing created_at", async () => {
    const d = deps({
      dbDoc: { created_at: "ORIGINAL", fcmToken: "tok" },
      authUser,
    });
    await call(d);
    expect(d.db.state.writes[0].data.created_at).toBeUndefined();
    expect(d.db.state.doc.created_at).toBe("ORIGINAL");
  });

  it("falls back to the email local part when Auth has no display name", async () => {
    const d = deps({
      dbDoc: undefined,
      authUser: { uid: UID, email: EMAIL, metadata: {} },
    });
    await call(d);
    expect(d.db.state.writes[0].data.display_name).toBe("customer");
    // No Auth creationTime → the server stamp, not an Invalid Date.
    expect(d.db.state.writes[0].data.created_at).toBe("SERVER_TIMESTAMP");
  });

  it("is idempotent — a second call writes only updated_at", async () => {
    const d = deps({ dbDoc: undefined, authUser });
    await call(d);
    const second = await call(d);
    expect(second.profileCreated).toBe(false);
    expect(second.dealerCodeStamped).toBe(false);
    expect(d.db.state.writes[1].data).toEqual({
      updated_at: "SERVER_TIMESTAMP",
    });
  });

  it("normalizes the email before looking it up", async () => {
    const d = deps({ dbDoc: undefined, authUser });
    const result = await call(d, "  CUSTOMER@Example.TEST  ");
    expect(result.email).toBe(EMAIL);
  });

  it("rejects a malformed email without touching Firestore", async () => {
    const d = deps({ dbDoc: undefined, authUser });
    await expect(call(d, "not-an-email")).rejects.toThrow(/valid email/);
    expect(d.db.state.writes).toHaveLength(0);
  });

  it("reports not-found for an email with no Auth account", async () => {
    const d = deps({ dbDoc: undefined, authUser: null });
    await expect(call(d)).rejects.toThrow(/No Nex-Gen account/);
    expect(d.db.state.writes).toHaveLength(0);
  });

  it("checks authorization BEFORE any lookup", async () => {
    const d = deps({ dbDoc: undefined, authUser });
    await expect(
      runClaimCustomerByEmail({
        deps: d,
        callerUid: "a_customer",
        token: {},
        email: EMAIL,
      }),
    ).rejects.toThrow(/Not authorized/);
    expect(d.db.state.writes).toHaveLength(0);
  });
});

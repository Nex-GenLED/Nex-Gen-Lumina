/**
 * Unit tests for the account-deletion purge (audit/OVERNIGHT_DATA_LIFECYCLE_AUDIT.md F-1).
 *
 * Runs against the tsc-compiled output in lib/ — `npm run build` first.
 * No emulator, no firebase-admin IO: purgeUserData() is dependency-injected
 * precisely so the orchestration and the VERIFY pass can be exercised with a
 * fake Firestore. (The emulator suite is blocked in this environment by the
 * JDK 17-vs-21 mismatch, so the coverage that matters lives here.)
 */

const {
  USER_SUBCOLLECTIONS,
  PENDING_PHASE_2,
  storagePrefixForUid,
  purgeUserData,
  isPurgeComplete,
} = require("../../lib/purgeUserAccount");

const UID = "test_uid_123";

/**
 * Fake Firestore.
 *
 * `data` maps a full collection path to a doc count. recursiveDelete() clears
 * every path under the deleted doc — which is what the real one does, and the
 * whole point of using it instead of a single .delete().
 */
function makeFake(options = {}) {
  const {
    seeded = {},
    userDocExists = true,
    recursiveDeleteImpl = null,
    storageImpl = null,
  } = options;

  const state = {
    collections: { ...seeded },
    userDocExists,
    recursiveDeleteCalls: [],
    storagePrefixes: [],
  };

  const db = {
    doc(path) {
      return {
        _path: path,
        async get() {
          if (path === `users/${UID}`) return { exists: state.userDocExists };
          return { exists: false };
        },
      };
    },
    collection(path) {
      return {
        limit() {
          return {
            async get() {
              return { empty: (state.collections[path] || 0) === 0 };
            },
          };
        },
      };
    },
    async recursiveDelete(ref) {
      state.recursiveDeleteCalls.push(ref._path);
      if (recursiveDeleteImpl) return recursiveDeleteImpl(state, ref);
      const prefix = ref._path + "/";
      for (const key of Object.keys(state.collections)) {
        if (key.startsWith(prefix)) delete state.collections[key];
      }
      if (ref._path === `users/${UID}`) state.userDocExists = false;
    },
  };

  const deps = {
    db,
    async deleteStoragePrefix(prefix) {
      state.storagePrefixes.push(prefix);
      if (storageImpl) return storageImpl(prefix);
      return 1;
    },
  };

  return { deps, state };
}

/** Seeds one doc into every subcollection the audit's §2.1 table enumerates. */
function seedEverySubcollection() {
  const seeded = {};
  for (const name of USER_SUBCOLLECTIONS) {
    seeded[`users/${UID}/${name}`] = 1;
  }
  return seeded;
}

describe("USER_SUBCOLLECTIONS inventory", () => {
  test("covers all 34 rows of audit §2.1", () => {
    // The audit table numbers 1..34 (plus 11a, which lives under `controllers`
    // and is reached by recursion rather than by name).
    expect(USER_SUBCOLLECTIONS.length).toBe(34);
  });

  test("has no duplicates", () => {
    expect(new Set(USER_SUBCOLLECTIONS).size).toBe(USER_SUBCOLLECTIONS.length);
  });

  test("includes every rule-less collection named in audit §3.3", () => {
    // These are the ones with no firestore.rules match block. A client-credential
    // probe on 2026-08-26 showed writes to them are denied today, so they should
    // be empty — but the purge must still sweep them, because that is a fact
    // about the ruleset, not about the data.
    for (const name of [
      "scenes",
      "autopilot_events",
      "user_events",
      "commercial_schedule",
      "simple_mode",
      "integrations",
      "handoff",
      "learned_preferences",
      "autopilot_feedback",
    ]) {
      expect(USER_SUBCOLLECTIONS).toContain(name);
    }
  });

  test("includes the PII-heavy and undeclared-diagnostics collections", () => {
    // Called out by name in the audit: addresses/geo, hardware identifiers, and
    // the crash sink that audit/DIAGNOSTICS_DECLARATION.md flags as having no
    // declared retention.
    for (const name of [
      "properties",
      "geofences",
      "controllers",
      "debug_errors",
    ]) {
      expect(USER_SUBCOLLECTIONS).toContain(name);
    }
  });
});

describe("PENDING_PHASE_2", () => {
  test("still records the §2.4 teardowns this phase does not do", () => {
    // Guards against someone emptying the list to make a coverage claim true.
    expect(PENDING_PHASE_2).toEqual(
      expect.arrayContaining([
        "neighborhoods.memberUids",
        "oauth_refresh_tokens",
        "google_oauth_refresh_tokens",
        "bridge_registry.pairedUid",
      ])
    );
  });
});

describe("storagePrefixForUid", () => {
  test("targets the folder image_upload_service.dart writes into", () => {
    expect(storagePrefixForUid(UID)).toBe(`users/${UID}/`);
  });
});

describe("purgeUserData — happy path", () => {
  test("recursively deletes users/{uid} and every subcollection", async () => {
    const { deps, state } = makeFake({ seeded: seedEverySubcollection() });

    const result = await purgeUserData(deps, UID);

    expect(state.recursiveDeleteCalls).toEqual([`users/${UID}`]);
    expect(result.userDocDeleted).toBe(true);
    expect(result.residualCollections).toEqual([]);
    expect(result.warnings).toEqual([]);
    expect(isPurgeComplete(result)).toBe(true);
  });

  test("deletes the user's Cloud Storage prefix", async () => {
    const { deps, state } = makeFake({
      seeded: seedEverySubcollection(),
      storageImpl: () => 3,
    });

    const result = await purgeUserData(deps, UID);

    expect(state.storagePrefixes).toEqual([`users/${UID}/`]);
    expect(result.storageObjectsDeleted).toBe(3);
  });

  test("verifies every enumerated subcollection, not a sample", async () => {
    const probed = [];
    const { deps } = makeFake({ seeded: seedEverySubcollection() });
    const inner = deps.db.collection.bind(deps.db);
    deps.db.collection = (path) => {
      probed.push(path);
      return inner(path);
    };

    await purgeUserData(deps, UID);

    expect(probed).toEqual(
      USER_SUBCOLLECTIONS.map((n) => `users/${UID}/${n}`)
    );
  });
});

describe("purgeUserData — partial failure is reported, never swallowed", () => {
  test("a subcollection that survives the sweep shows up as residual", async () => {
    // The exact F-1 failure mode: the parent doc goes, the children do not.
    const { deps } = makeFake({
      seeded: seedEverySubcollection(),
      recursiveDeleteImpl: (state) => {
        state.userDocExists = false; // only the parent doc is removed
      },
    });

    const result = await purgeUserData(deps, UID);

    expect(result.userDocDeleted).toBe(true);
    expect(result.residualCollections.length).toBe(USER_SUBCOLLECTIONS.length);
    expect(isPurgeComplete(result)).toBe(false);
  });

  test("a surviving user doc is a warning and blocks completion", async () => {
    const { deps } = makeFake({
      recursiveDeleteImpl: () => {
        /* no-op: nothing is deleted at all */
      },
    });

    const result = await purgeUserData(deps, UID);

    expect(result.userDocDeleted).toBe(false);
    expect(result.warnings.join(" ")).toContain("still exists");
    expect(isPurgeComplete(result)).toBe(false);
  });

  test("a Storage failure does not abort the Firestore purge but blocks completion", async () => {
    const { deps } = makeFake({
      seeded: seedEverySubcollection(),
      storageImpl: () => {
        throw new Error("bucket unreachable");
      },
    });

    const result = await purgeUserData(deps, UID);

    // Firestore side still completed…
    expect(result.userDocDeleted).toBe(true);
    expect(result.residualCollections).toEqual([]);
    // …but the caller must not go on to delete the Auth account.
    expect(result.warnings.join(" ")).toContain("bucket unreachable");
    expect(isPurgeComplete(result)).toBe(false);
  });

  test("a verification probe that throws is surfaced, not treated as empty", async () => {
    const { deps } = makeFake({ seeded: seedEverySubcollection() });
    const inner = deps.db.collection.bind(deps.db);
    deps.db.collection = (path) => {
      if (path.endsWith("/scenes")) {
        return {
          limit() {
            return {
              async get() {
                throw new Error("permission denied");
              },
            };
          },
        };
      }
      return inner(path);
    };

    const result = await purgeUserData(deps, UID);

    expect(result.warnings.join(" ")).toContain("permission denied");
    expect(isPurgeComplete(result)).toBe(false);
  });

  test("recursiveDelete throwing propagates — the caller must not see success", async () => {
    const { deps } = makeFake({
      recursiveDeleteImpl: () => {
        throw new Error("firestore unavailable");
      },
    });

    await expect(purgeUserData(deps, UID)).rejects.toThrow(
      "firestore unavailable"
    );
  });
});

describe("purgeUserData — input guards", () => {
  test.each([["", "empty"], ["   ", "whitespace"], [null, "null"], [undefined, "undefined"]])(
    "rejects a %s uid (%s) rather than sweeping users/",
    async (uid) => {
      const { deps, state } = makeFake();
      await expect(purgeUserData(deps, uid)).rejects.toThrow(
        "non-empty string"
      );
      expect(state.recursiveDeleteCalls).toEqual([]);
    }
  );
});

describe("isPurgeComplete", () => {
  const clean = {
    uid: UID,
    residualCollections: [],
    userDocDeleted: true,
    storageObjectsDeleted: 1,
    warnings: [],
  };

  test("true only when the doc is gone, nothing is residual, and no warnings", () => {
    expect(isPurgeComplete(clean)).toBe(true);
    expect(isPurgeComplete({ ...clean, userDocDeleted: false })).toBe(false);
    expect(isPurgeComplete({ ...clean, residualCollections: ["x"] })).toBe(false);
    expect(isPurgeComplete({ ...clean, warnings: ["x"] })).toBe(false);
  });

  test("zero storage objects is fine — not every user uploaded a house photo", () => {
    expect(isPurgeComplete({ ...clean, storageObjectsDeleted: 0 })).toBe(true);
  });
});

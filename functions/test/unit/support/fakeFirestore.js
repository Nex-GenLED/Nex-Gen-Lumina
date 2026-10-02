// In-memory Firestore for tick-driven unit tests (dispatcher, sweeper,
// planner pre-flight). NOT a test file — jest only matches *.test.js.
//
// WHY A SHARED FAKE. The planner, dispatcher and sweeper are exercised through
// their REAL tick functions; each test seeds documents, runs a tick, and then
// reads the outcome back with a plain `.get()` on the same paths production
// uses. The older per-suite fakes stored FieldValue sentinels as-is and had no
// transactions, preconditions, collection-group queries or update times, which
// is exactly the surface the A/B changes depend on. Where a property can only
// be proven against real Firestore (index requirements, true transaction
// contention) the emulator suite owns it; this fake only has to be faithful to
// the documented semantics it implements:
//
//   - set / set(merge) (deep map merge) / update (dotted paths) / create / delete
//   - update/delete preconditions ({ lastUpdateTime }) → code 9 on mismatch
//   - create on an existing doc → code 6; update on a missing doc → code 5
//   - FieldValue.serverTimestamp / increment / arrayUnion / delete resolved at
//     write time against the fake clock
//   - where (== != < <= > >= in), orderBy, limit, collectionGroup
//   - runTransaction (writes applied after the callback resolves) and batch()
//   - snapshot.updateTime / createTime, advanced on every write
//
// `beforeNextWrite(fn)` runs `fn` once, immediately before the next write is
// applied. It is how a test models "the bridge PATCHed this doc between the
// server's read and its write" without threads.

const admin = require("firebase-admin");

const Timestamp = admin.firestore.Timestamp;

function isTimestampLike(v) {
  return v !== null && typeof v === "object" && typeof v.toMillis === "function";
}

function cmpValues(a, b) {
  const av = isTimestampLike(a) ? a.toMillis() : a;
  const bv = isTimestampLike(b) ? b.toMillis() : b;
  if (av === bv) return 0;
  if (av === undefined || av === null) return -1;
  if (bv === undefined || bv === null) return 1;
  return av < bv ? -1 : 1;
}

function eq(a, b) {
  if (isTimestampLike(a) && isTimestampLike(b)) return a.toMillis() === b.toMillis();
  if (Array.isArray(a) && Array.isArray(b)) return JSON.stringify(a) === JSON.stringify(b);
  return a === b;
}

function getPath(obj, fieldPath) {
  let cur = obj;
  for (const part of fieldPath.split(".")) {
    if (cur === null || cur === undefined || typeof cur !== "object") return undefined;
    cur = cur[part];
  }
  return cur;
}

function isPlainMap(v) {
  return (
    v !== null &&
    typeof v === "object" &&
    !Array.isArray(v) &&
    !isTimestampLike(v) &&
    !isSentinel(v)
  );
}

function isSentinel(v) {
  return v !== null && typeof v === "object" && typeof v.methodName === "string" &&
    v.methodName.startsWith("FieldValue.");
}

function makeFakeFirestore({ seed = {}, now = Date.now() } = {}) {
  const store = new Map(); // path -> { data, createTime, updateTime }
  const writes = [];
  const reads = [];
  let clockMs = now;
  let nanoCounter = 0;
  let hook = null;

  const stamp = () => {
    nanoCounter = (nanoCounter + 1) % 1000;
    const ms = clockMs;
    const seconds = Math.floor(ms / 1000);
    const nanos = (ms % 1000) * 1_000_000 + nanoCounter;
    return new Timestamp(seconds, nanos);
  };

  const parentOf = (p) => p.split("/").slice(0, -1).join("/");
  const idOf = (p) => p.split("/").pop();

  function resolveValue(prev, v) {
    if (!isSentinel(v)) {
      if (isPlainMap(v)) {
        const out = {};
        for (const [k, x] of Object.entries(v)) {
          const r = resolveValue(undefined, x);
          if (r !== DELETE) out[k] = r;
        }
        return out;
      }
      return v;
    }
    switch (v.methodName) {
      case "FieldValue.serverTimestamp":
        return Timestamp.fromMillis(clockMs);
      case "FieldValue.increment":
        return (typeof prev === "number" ? prev : 0) + v.operand;
      case "FieldValue.arrayUnion": {
        const base = Array.isArray(prev) ? [...prev] : [];
        for (const el of v.elements) {
          if (!base.some((b) => JSON.stringify(b) === JSON.stringify(el))) base.push(el);
        }
        return base;
      }
      case "FieldValue.delete":
        return DELETE;
      default:
        throw new Error(`fakeFirestore: unsupported sentinel ${v.methodName}`);
    }
  }
  const DELETE = Symbol("delete");

  function deepMerge(prev, data) {
    const out = { ...(prev || {}) };
    for (const [k, v] of Object.entries(data)) {
      if (isPlainMap(v) && isPlainMap(out[k])) {
        out[k] = deepMerge(out[k], v);
        continue;
      }
      const r = resolveValue(out[k], v);
      if (r === DELETE) delete out[k];
      else out[k] = r;
    }
    return out;
  }

  function setDotted(target, fieldPath, value) {
    const parts = fieldPath.split(".");
    let cur = target;
    for (let i = 0; i < parts.length - 1; i++) {
      if (!isPlainMap(cur[parts[i]])) cur[parts[i]] = {};
      else cur[parts[i]] = { ...cur[parts[i]] };
      cur = cur[parts[i]];
    }
    const last = parts[parts.length - 1];
    const r = resolveValue(cur[last], value);
    if (r === DELETE) delete cur[last];
    else cur[last] = r;
  }

  function err(code, msg) {
    const e = new Error(msg);
    e.code = code;
    return e;
  }

  function checkPrecondition(path, precondition) {
    if (!precondition || !precondition.lastUpdateTime) return;
    const rec = store.get(path);
    if (!rec || !rec.updateTime.isEqual(precondition.lastUpdateTime)) {
      throw err(9, `FAILED_PRECONDITION: ${path} changed since it was read`);
    }
  }

  function runHook() {
    if (hook) {
      const h = hook;
      hook = null;
      h();
    }
  }

  // ── raw write primitives (used by refs, transactions and batches) ─────────
  const ops = {
    set(path, data, opts) {
      runHook();
      const prev = store.get(path);
      const t = stamp();
      const next = opts && opts.merge ? deepMerge(prev ? prev.data : {}, data) : deepMerge({}, data);
      store.set(path, { data: next, createTime: prev ? prev.createTime : t, updateTime: t });
      writes.push({ op: opts && opts.merge ? "set_merge" : "set", path, data });
    },
    update(path, data, precondition) {
      runHook();
      const prev = store.get(path);
      if (!prev) throw err(5, `NOT_FOUND: update on missing ${path}`);
      checkPrecondition(path, precondition);
      const next = JSON.parse(JSON.stringify({}));
      Object.assign(next, prev.data);
      for (const [k, v] of Object.entries(data)) {
        if (k.includes(".")) setDotted(next, k, v);
        else {
          const r = resolveValue(next[k], v);
          if (r === DELETE) delete next[k];
          else next[k] = r;
        }
      }
      store.set(path, { data: next, createTime: prev.createTime, updateTime: stamp() });
      writes.push({ op: "update", path, data });
    },
    create(path, data) {
      runHook();
      if (store.has(path)) throw err(6, `ALREADY_EXISTS: ${path}`);
      const t = stamp();
      store.set(path, { data: deepMerge({}, data), createTime: t, updateTime: t });
      writes.push({ op: "create", path, data });
    },
    delete(path, precondition) {
      runHook();
      checkPrecondition(path, precondition);
      store.delete(path);
      writes.push({ op: "delete", path });
    },
  };

  const snap = (path) => {
    const rec = store.get(path);
    const data = rec ? rec.data : undefined;
    return {
      id: idOf(path),
      exists: rec !== undefined,
      data: () => (data === undefined ? undefined : { ...data }),
      get: (f) => (data === undefined ? undefined : getPath(data, f)),
      ref: docRef(path),
      updateTime: rec ? rec.updateTime : undefined,
      createTime: rec ? rec.createTime : undefined,
    };
  };

  function docRef(path) {
    return {
      id: idOf(path),
      path,
      get parent() {
        return collRef(parentOf(path));
      },
      collection: (name) => collRef(`${path}/${name}`),
      get: async () => {
        reads.push(path);
        return snap(path);
      },
      set: async (data, opts) => ops.set(path, data, opts),
      update: async (data, precondition) => ops.update(path, data, precondition),
      create: async (data) => ops.create(path, data),
      delete: async (precondition) => ops.delete(path, precondition),
    };
  }

  function makeQuery({ match, filters = [], order = [], lim = null, label }) {
    return {
      where: (f, op, v) => makeQuery({ match, filters: [...filters, [f, op, v]], order, lim, label }),
      orderBy: (f, dir = "asc") => makeQuery({ match, filters, order: [...order, [f, dir]], lim, label }),
      limit: (n) => makeQuery({ match, filters, order, lim: n, label }),
      get: async () => {
        reads.push(`query:${label}`);
        let docs = [...store.keys()].filter(match).sort().map(snap);
        docs = docs.filter((s) =>
          filters.every(([f, op, v]) => {
            const x = s.get(f);
            switch (op) {
              case "==": return eq(x, v);
              case "!=": return x !== undefined && !eq(x, v);
              case "<": return x !== undefined && cmpValues(x, v) < 0;
              case "<=": return x !== undefined && cmpValues(x, v) <= 0;
              case ">": return x !== undefined && cmpValues(x, v) > 0;
              case ">=": return x !== undefined && cmpValues(x, v) >= 0;
              case "in": return v.some((y) => eq(x, y));
              default: throw new Error(`fakeFirestore: unsupported op ${op}`);
            }
          })
        );
        for (const [f] of order) docs = docs.filter((s) => s.get(f) !== undefined);
        if (order.length > 0) {
          docs.sort((a, b) => {
            for (const [f, dir] of order) {
              const c = cmpValues(a.get(f), b.get(f));
              if (c !== 0) return dir === "desc" ? -c : c;
            }
            return 0;
          });
        }
        if (lim !== null) docs = docs.slice(0, lim);
        return { docs, empty: docs.length === 0, size: docs.length };
      },
    };
  }

  function collRef(path) {
    const q = makeQuery({ match: (p) => parentOf(p) === path, label: path });
    return {
      ...q,
      id: idOf(path),
      path,
      get parent() {
        const pp = parentOf(path);
        return pp ? docRef(pp) : null;
      },
      doc: (id) => docRef(`${path}/${id}`),
    };
  }

  function collectionGroup(name) {
    return makeQuery({ match: (p) => idOf(parentOf(p)) === name, label: `group:${name}` });
  }

  async function runTransaction(fn) {
    const pending = [];
    const tx = {
      get: async (refOrQuery) => {
        if (typeof refOrQuery.path === "string" && refOrQuery.collection) {
          reads.push(refOrQuery.path);
          return snap(refOrQuery.path);
        }
        return refOrQuery.get();
      },
      set: (ref, data, opts) => { pending.push(() => ops.set(ref.path, data, opts)); return tx; },
      update: (ref, data, precondition) => { pending.push(() => ops.update(ref.path, data, precondition)); return tx; },
      create: (ref, data) => { pending.push(() => ops.create(ref.path, data)); return tx; },
      delete: (ref) => { pending.push(() => ops.delete(ref.path)); return tx; },
    };
    const result = await fn(tx);
    for (const w of pending) w();
    return result;
  }

  function batch() {
    const pending = [];
    const b = {
      set: (ref, data, opts) => { pending.push(() => ops.set(ref.path, data, opts)); return b; },
      update: (ref, data, precondition) => { pending.push(() => ops.update(ref.path, data, precondition)); return b; },
      create: (ref, data) => { pending.push(() => ops.create(ref.path, data)); return b; },
      delete: (ref) => { pending.push(() => ops.delete(ref.path)); return b; },
      commit: async () => { for (const w of pending) w(); },
    };
    return b;
  }

  for (const [path, data] of Object.entries(seed)) {
    const t = stamp();
    store.set(path, { data: { ...data }, createTime: t, updateTime: t });
  }

  return {
    db: {
      collection: (name) => collRef(name),
      collectionGroup,
      doc: (path) => docRef(path),
      runTransaction,
      batch,
    },
    store,
    writes,
    reads,
    /** Current data at a path, or undefined. */
    get: (path) => (store.has(path) ? store.get(path).data : undefined),
    /** Seed or overwrite a doc outside any tick (advances its updateTime). */
    put: (path, data) => ops.set(path, data),
    /** Patch fields outside any tick — models another writer (the bridge, the app). */
    patch: (path, data) => ops.update(path, data),
    setNow: (ms) => { clockMs = ms; },
    now: () => clockMs,
    beforeNextWrite: (fn) => { hook = fn; },
    Timestamp,
    ts: (ms) => Timestamp.fromMillis(ms),
  };
}

module.exports = { makeFakeFirestore };

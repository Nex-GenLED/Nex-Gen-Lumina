// In-memory Firestore fake covering exactly what the v1 fanoutToCrew touches.
//
//   neighborhoods/{g}.get()                      -> { memberUids }
//   neighborhoods/{g}/members.get()              -> forEach(doc{id,data()})
//   neighborhoods/{g}/fires.doc()                -> a fire ref (batch-created)
//   users/{uid}.get()                            -> { webhookUrl? }
//   users/{uid}/controllers.doc(id) + db.getAll  -> { ip }
//   users/{uid}/bridge_status/current.get()      -> { exists, updateTime }
//   users/{uid}/commands.where(...).where(...)   -> in-flight sync docs
//   users/{uid}/commands.doc(id)                 -> a command ref (batch-created)
//   db.batch().create/update/commit              -> recorded per uid
//
// Options:
//   memberUids, members          the roster (members: { uid: memberDocData })
//   defaultIp                    ip every named controller resolves to
//   ipByController               per-controller override ({ id: ip | "" })
//   heartbeatAgeMs               ms since the bridge heartbeat; null = never
//   heartbeatAgeByUid            per-uid override
//   webhookByUid                 { uid: url }
//   inFlightByUid                { uid: [{ id, status, createdAtMs }] }
//   nowMs                        the clock the heartbeat age is relative to; MUST match
//                                the nowMs passed to fanoutToCrew (default: Date.now())

function makeCrewDb(opts) {
  const {
    memberUids,
    members,
    defaultIp = null,
    ipByController = {},
    heartbeatAgeMs = 0,
    heartbeatAgeByUid = {},
    webhookByUid = {},
    inFlightByUid = {},
    nowMs = Date.now(),
    fireId = "fire1",
  } = opts;

  const commands = {}; // uid -> [created command docs]
  const updates = {}; // uid -> [{ id, data }]
  const fires = []; // [{ id, data }]
  let batchCommits = 0;

  const ipFor = (id) => {
    if (Object.prototype.hasOwnProperty.call(ipByController, id)) {
      return ipByController[id];
    }
    if (defaultIp !== null) return defaultIp;
    return "10.0.0." + (id.length % 200);
  };

  const heartbeatFor = (uid) =>
    Object.prototype.hasOwnProperty.call(heartbeatAgeByUid, uid)
      ? heartbeatAgeByUid[uid]
      : heartbeatAgeMs;

  const usersDoc = (uid) => ({
    get: async () => ({
      data: () => (webhookByUid[uid] ? { webhookUrl: webhookByUid[uid] } : {}),
    }),
    collection: (sub) => {
      if (sub === "controllers") {
        return {
          get: async () => ({ forEach: () => {} }),
          doc: (id) => ({ _uid: uid, _id: id }),
        };
      }
      if (sub === "bridge_status") {
        return {
          doc: () => ({
            get: async () => {
              const age = heartbeatFor(uid);
              if (age === null) return { exists: false };
              return { exists: true, updateTime: { toMillis: () => nowMs - age } };
            },
          }),
        };
      }
      if (sub === "commands") {
        commands[uid] = commands[uid] || [];
        const whereChain = (filters) => ({
          where: (f, op, v) => whereChain([...filters, { f, v }]),
          get: async () => {
            const status = (filters.find((x) => x.f === "status") || {}).v;
            const rows = (inFlightByUid[uid] || []).filter((d) => d.status === status);
            return {
              forEach: (cb) =>
                rows.forEach((d) =>
                  cb({
                    id: d.id,
                    data: () => ({
                      status: d.status,
                      source: "sync_fanout",
                      createdAt:
                        d.createdAtMs === null || d.createdAtMs === undefined
                          ? undefined
                          : { toMillis: () => d.createdAtMs },
                    }),
                  })
                ),
            };
          },
        });
        return {
          doc: (id) => ({ _uid: uid, _id: id, path: `users/${uid}/commands/${id}` }),
          where: (f, op, v) => whereChain([{ f, v }]),
          add: async (doc) => {
            commands[uid].push(doc);
            return { id: "cmd" + commands[uid].length };
          },
        };
      }
      throw new Error("unexpected users subcollection: " + sub);
    },
  });

  const db = {
    getAll: async (...refs) =>
      refs.map((r) => ({
        id: r._id,
        exists: true,
        data: () => ({ ip: ipFor(r._id) }),
      })),
    batch: () => {
      const ops = [];
      return {
        create: (ref, data) => ops.push({ kind: "create", ref, data }),
        set: (ref, data) => ops.push({ kind: "set", ref, data }),
        update: (ref, data) => ops.push({ kind: "update", ref, data }),
        commit: async () => {
          batchCommits++;
          for (const op of ops) {
            if (op.ref._fire) {
              fires.push({ id: op.ref._id, data: op.data });
            } else if (op.kind === "update") {
              updates[op.ref._uid] = updates[op.ref._uid] || [];
              updates[op.ref._uid].push({ id: op.ref._id, data: op.data });
            } else {
              commands[op.ref._uid] = commands[op.ref._uid] || [];
              commands[op.ref._uid].push({ ...op.data, _id: op.ref._id });
            }
          }
        },
      };
    },
    collection: (name) => {
      if (name === "neighborhoods") {
        return {
          doc: () => ({
            get: async () => ({ data: () => ({ memberUids }) }),
            collection: (sub) => {
              if (sub === "members") {
                return {
                  get: async () => ({
                    forEach: (cb) =>
                      Object.entries(members).forEach(([id, data]) =>
                        cb({ id, data: () => data })
                      ),
                  }),
                };
              }
              if (sub === "fires") {
                return { doc: () => ({ _fire: true, _id: fireId, id: fireId }) };
              }
              throw new Error("unexpected neighborhoods subcollection: " + sub);
            },
          }),
        };
      }
      if (name === "users") return { doc: usersDoc };
      throw new Error("unexpected collection: " + name);
    },
  };
  return { db, commands, updates, fires, batchCommits: () => batchCommits };
}

module.exports = { makeCrewDb };

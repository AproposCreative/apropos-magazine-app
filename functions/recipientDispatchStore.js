// SDK-free discovery/checkpoints. This module does not export a Cloud trigger or initialize a service.
const {randomUUID} = require("node:crypto");
const {COLLECTION: DELIVERIES} = require("./recipientFanout");
const CHECKPOINTS = "article_push_dispatch_checkpoints", MAX_PAGE_SIZE = 100;
const LANES = Object.freeze({deliver: Object.freeze(["pending", "retry"]), recover: Object.freeze(["sending"])});
const safeTime = (value) => Number.isSafeInteger(value) && value >= 0;
const validOpaque = (value) => typeof value === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
const validRawID = (value) => typeof value === "string" && value.length > 0 && value !== "." && value !== ".." && !value.includes("/") &&
  Buffer.byteLength(value) <= 1500 && Buffer.from(value, "utf8").toString("utf8") === value;
const validCursor = (value) => value && Object.keys(value).length === 2 && safeTime(value.availableAtMs) && validRawID(value.id);
const sameCursor = (left, right) => left === null && right === null || !!left && !!right && left.availableAtMs === right.availableAtMs && left.id === right.id;
const compareCursor = (left, right) => left.availableAtMs - right.availableAtMs || Buffer.compare(Buffer.from(left.id), Buffer.from(right.id));
const keys = ["schemaVersion", "lane", "phase", "passId", "cutoffMs", "cursor", "revision", "token", "expiresAtMs", "updatedAtMs"];
function validRecord(value, lane) {
  return value && Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key)) && value.schemaVersion === 1 &&
    value.lane === lane && Object.hasOwn(LANES, lane) && ["active", "complete"].includes(value.phase) && validOpaque(value.passId) && safeTime(value.cutoffMs) &&
    (value.cursor === null || validCursor(value.cursor) && value.cursor.availableAtMs <= value.cutoffMs) &&
    Number.isSafeInteger(value.revision) && value.revision > 0 && safeTime(value.updatedAtMs) && value.updatedAtMs >= value.cutoffMs && safeTime(value.expiresAtMs) &&
    (value.token === null ? value.expiresAtMs === 0 : value.phase === "active" && validOpaque(value.token) && value.expiresAtMs > value.updatedAtMs) &&
    (value.phase !== "complete" || value.token === null);
}
function ticket(record) {
  const {lane, passId, cutoffMs, cursor, revision, token, expiresAtMs} = record;
  return {lane, passId, cutoffMs, cursor: cursor && {...cursor}, revision, token, expiresAtMs};
}
function matches(record, lease, time) {
  return validRecord(record, lease?.lane) && record.phase === "active" && record.token !== null && record.expiresAtMs > time && record.updatedAtMs <= time &&
    lease.passId === record.passId && lease.cutoffMs === record.cutoffMs && lease.revision === record.revision && lease.token === record.token &&
    lease.expiresAtMs === record.expiresAtMs && sameCursor(lease.cursor, record.cursor);
}
function candidate(data, id, lane) {
  if (!data || data.schemaVersion !== 1 || data.id !== id || !/^device-[a-f\d]{64}$/.test(id) ||
      !/^article-[a-f\d]{64}$/.test(data.parentId || "") || !Number.isSafeInteger(data.generation) || data.generation < 1 || !LANES[lane].includes(data.state)) return null;
  return {parentId: data.parentId, generation: data.generation, deliveryId: id};
}
function unavailable(code) {const error = new Error("Recipient dispatch store unavailable");error.code = `dispatch/${code}`;return error;}
function createRecipientDispatchStore({db, documentIDField, now = Date.now, leaseMs = 120000, makeID = randomUUID}) {
  // Pass the actual injected SDK FieldPath.documentId() object. A guessed string is not a document-ID sentinel.
  if (!db || typeof db.collection !== "function" || typeof db.runTransaction !== "function" || !documentIDField ||
      !["object", "function"].includes(typeof documentIDField) || typeof now !== "function" || typeof makeID !== "function" ||
      !Number.isSafeInteger(leaseMs) || leaseMs <= 0 || leaseMs > 3600000) throw new Error("Invalid recipient dispatch configuration");
  const children = db.collection(DELIVERIES), checkpoints = db.collection(CHECKPOINTS), issued = new Map();
  const clock = () => {const value = now();if (!safeTime(value) || !safeTime(value + leaseMs)) throw unavailable("invalid_clock");return value;};
  const identity = () => {const value = makeID();if (!validOpaque(value)) throw unavailable("invalid_identity");return value;};
  const transaction = async (callback) => {try {return await db.runTransaction(callback);} catch (error) {
    if (["dispatch/invalid_clock", "dispatch/invalid_identity"].includes(error?.code)) throw unavailable(error.code.slice(9));
    throw unavailable("checkpoint_unavailable");
  }};
  const reference = (lane) => checkpoints.doc(`${lane}-v1`);
  const assertCurrent = async ({lease}) => {
    if (!lease || !Object.hasOwn(LANES, lease.lane)) return false;
    return transaction(async (tx) => matches((await tx.get(reference(lease.lane))).data(), lease, clock()));
  };
  return {
    assertCurrent,
    async claim({lane}) {
      if (!Object.hasOwn(LANES, lane)) return {status: "blocked", reason: "invalid_lane"};
      return transaction(async (tx) => {
        const ref = reference(lane), snapshot = await tx.get(ref), old = snapshot.data(), time = clock();
        if (snapshot.exists !== true && snapshot.exists !== false || snapshot.exists === false && old !== undefined ||
            snapshot.exists === true && !validRecord(old, lane)) return {status: "blocked", reason: "corrupt_checkpoint"};
        if (old && old.updatedAtMs > time) return {status: "blocked", reason: "clock_regressed"};
        if (old?.token && old.expiresAtMs > time) return {status: "busy"};
        if (old?.revision === Number.MAX_SAFE_INTEGER) return {status: "blocked", reason: "revision_exhausted"};
        const fresh = !old || old.phase === "complete", token = identity(), passId = fresh ? identity() : old.passId;
        if (token === old?.token || fresh && passId === old?.passId || token === passId) return {status: "blocked", reason: "identity_collision"};
        const record = {schemaVersion: 1, lane, phase: "active", passId, cutoffMs: fresh ? time : old.cutoffMs,
          cursor: fresh ? null : old.cursor, revision: (old?.revision || 0) + 1, token, expiresAtMs: time + leaseMs, updatedAtMs: time};
        tx.set(ref, record);issued.delete(lane);return {status: "claimed", lease: ticket(record)};
      });
    },
    async discover({lease, limit = MAX_PAGE_SIZE}) {
      if (!Number.isInteger(limit) || limit < 1 || limit > MAX_PAGE_SIZE) return {status: "blocked", reason: "invalid_page_limit"};
      if (!await assertCurrent({lease})) return {status: "stale"};
      issued.delete(lease.lane);
      let snapshots;
      try {
        let query = lease.lane === "deliver" ? children.where("state", "in", [...LANES.deliver]) : children.where("state", "==", "sending");
        query = query.where("availableAtMs", "<=", lease.cutoffMs).orderBy("availableAtMs", "asc").orderBy(documentIDField, "asc");
        if (lease.cursor !== null) query = query.startAfter(lease.cursor.availableAtMs, lease.cursor.id);
        snapshots = (await query.limit(limit).get())?.docs;
      } catch {throw unavailable("discovery_unavailable");}
      if (!await assertCurrent({lease})) return {status: "stale"};
      if (!Array.isArray(snapshots) || snapshots.length > limit) return {status: "blocked", reason: "invalid_query_page"};
      let previous = lease.cursor;
      const rows = [], grants = new Map();
      try {
        for (let index = 0; index < snapshots.length; index++) {
          const snapshot = snapshots[index], data = snapshot.data(), cursor = {availableAtMs: data?.availableAtMs, id: snapshot.id};
          if (!validCursor(cursor) || cursor.availableAtMs > lease.cutoffMs || previous && compareCursor(cursor, previous) <= 0) {
            return {status: "blocked", reason: "invalid_query_page"};
          }
          const checkpoint = identity();
          if (grants.has(checkpoint)) return {status: "blocked", reason: "identity_collision"};
          Object.freeze(cursor);
          const value = candidate(data, snapshot.id, lease.lane);
          const row = Object.freeze({cursor, candidate: value && Object.freeze(value), checkpoint});
          grants.set(checkpoint, {row, before: previous, revision: lease.revision + index});rows.push(row);previous = cursor;
        }
      } catch {return {status: "blocked", reason: "invalid_query_page"};}
      if (!Number.isSafeInteger(lease.revision + rows.length)) return {status: "blocked", reason: "revision_exhausted"};
      const exhausted = rows.length < limit;
      issued.set(lease.lane, {token: lease.token, passId: lease.passId, cutoffMs: lease.cutoffMs, grants,
        completion: exhausted ? {cursor: previous, revision: lease.revision + rows.length} : null});
      return {status: "page", rows, exhausted};
    },
    async advance({lease, row}) {
      const page = issued.get(lease?.lane), grant = page?.grants.get(row?.checkpoint);
      if (!grant || grant.row !== row || page.token !== lease.token || page.passId !== lease.passId || page.cutoffMs !== lease.cutoffMs ||
          grant.revision !== lease.revision || !sameCursor(grant.before, lease.cursor)) return {status: "stale"};
      return transaction(async (tx) => {
        const ref = reference(lease.lane), record = (await tx.get(ref)).data(), time = clock();
        if (!matches(record, lease, time)) return {status: "stale"};
        if (record.revision === Number.MAX_SAFE_INTEGER) return {status: "blocked", reason: "revision_exhausted"};
        const next = {...record, cursor: {...row.cursor}, revision: record.revision + 1, expiresAtMs: time + leaseMs, updatedAtMs: time};
        tx.set(ref, next);return {status: "advanced", lease: ticket(next)};
      });
    },
    async complete({lease}) {
      const page = issued.get(lease?.lane), proof = page?.completion;
      if (!proof || page.token !== lease.token || page.passId !== lease.passId || page.cutoffMs !== lease.cutoffMs ||
          proof.revision !== lease.revision || !sameCursor(proof.cursor, lease.cursor)) return {status: "stale"};
      return transaction(async (tx) => {
        const ref = reference(lease.lane), record = (await tx.get(ref)).data(), time = clock();
        if (!matches(record, lease, time)) return {status: "stale"};
        if (record.revision === Number.MAX_SAFE_INTEGER) return {status: "blocked", reason: "revision_exhausted"};
        tx.set(ref, {...record, phase: "complete", token: null, expiresAtMs: 0, revision: record.revision + 1, updatedAtMs: time});
        issued.delete(lease.lane);return {status: "completed"};
      });
    },
    async release({lease}) {
      if (!lease || !Object.hasOwn(LANES, lease.lane)) return false;
      return transaction(async (tx) => {
        const ref = reference(lease.lane), record = (await tx.get(ref)).data(), time = clock();
        if (!matches(record, lease, time) || record.revision === Number.MAX_SAFE_INTEGER) return false;
        tx.set(ref, {...record, token: null, expiresAtMs: 0, revision: record.revision + 1, updatedAtMs: time});
        issued.delete(lease.lane);return true;
      });
    },
  };
}
module.exports = {CHECKPOINTS, MAX_PAGE_SIZE, createRecipientDispatchStore};

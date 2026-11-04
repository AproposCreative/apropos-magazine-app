// SDK-free frozen planning input. Orphan inputs confer no parent/send authority.
const {hash, installationID, deliveryID, eventDescriptor} = require("./recipientRouting");
const INPUT_ROOTS = "article_push_recipient_inputs", INPUT_PAGES = "article_push_recipient_input_pages";
const ROOT_SCHEMA = 2, PAGE_SIZE = 100, MAX_PAGES = 1000, MANIFEST_BYTES = 192000, PAGE_BYTES = 128000, SNAPSHOT_AGE_MS = 300000;
// Firestore may reorder every map, including maps nested in arrays. Sort maps
// recursively while retaining array order and standard JSON value semantics.
const canonicalJSON = (value) => JSON.stringify(value, (_key, item) => item && typeof item === "object" && !Array.isArray(item) ?
  Object.fromEntries(Object.keys(item).sort().map((key) => [key, item[key]])) : item);
const digest = (value) => hash(canonicalJSON(value));
const plain = (v) => !!v && typeof v === "object" && !Array.isArray(v) && [Object.prototype, null].includes(Object.getPrototypeOf(v));
const exact = (v, fields) => plain(v) && Object.keys(v).length === fields.length && fields.every((key) => Object.hasOwn(v, key));
const timestamp = (v) => Number.isSafeInteger(v) && v > 0;
const hex = (v) => typeof v === "string" && /^[a-f\d]{64}$/.test(v);
const parentID = (v) => typeof v === "string" && /^article-[a-f\d]{64}$/.test(v);
const inputID = (v) => typeof v === "string" && /^input-[a-f\d]{64}$/.test(v);
const inputPageID = (id, index) => `${id}-${index}`;
function compact(row) {
  return {id: row.id, installationId: row.installationId, ownerUID: row.ownerUID, ownerEpoch: row.ownerEpoch,
    registrationRevision: row.registrationRevision, tokenHash: row.tokenHash};
}
const pageDigest = (rows) => digest(rows.map(compact));
function validDescriptor(row, parentId) {
  return exact(row, ["id", "installationId", "ownerUID", "ownerEpoch", "registrationRevision", "tokenHash"]) && installationID(row.installationId) &&
    row.id === deliveryID(parentId, row.installationId) && (row.ownerUID === null || (typeof row.ownerUID === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(row.ownerUID))) &&
    Number.isSafeInteger(row.ownerEpoch) && row.ownerEpoch > 0 && Number.isSafeInteger(row.registrationRevision) && row.registrationRevision > 0 && hex(row.tokenHash);
}
function validExpected(expected, total) {
  return Array.isArray(expected) && expected.length <= MAX_PAGES && Number.isSafeInteger(total) && total >= 0 && total <= PAGE_SIZE * MAX_PAGES &&
    Buffer.byteLength(JSON.stringify(expected)) <= MANIFEST_BYTES && expected.every((item, i) => exact(item, ["hash", "count"]) && hex(item.hash) &&
      Number.isSafeInteger(item.count) && item.count > 0 && item.count <= PAGE_SIZE && (i === expected.length - 1 || item.count === PAGE_SIZE)) &&
    expected.reduce((count, item) => count + item.count, 0) === total && (total !== 0 || expected.length === 0);
}
function validEvent(event, parentId, revision) {
  try {return exact(event, ["id", "family", "articleId", "sourceRevision", "categoryIds"]) && event.id === parentId && event.family === "article" &&
    event.sourceRevision === revision && digest(eventDescriptor(event)) === digest(event);} catch {return false;}
}
const core = (root) => ({schemaVersion: ROOT_SCHEMA, parentId: root.parentId, sourceRevision: root.sourceRevision, envelopeHash: root.envelopeHash,
  event: root.event, boundaries: root.boundaries, snapshotHash: root.snapshotHash, snapshotAtMs: root.snapshotAtMs, expected: root.expected, total: root.total, expiresAtMs: root.expiresAtMs});
const rootID = (root) => "input-" + digest(core(root));
function validRoot(id, root) {
  return inputID(id) && exact(root, ["schemaVersion", "parentId", "sourceRevision", "envelopeHash", "event", "snapshotHash", "snapshotAtMs", "expected", "total", "expiresAtMs",
    "boundaries", "phase", "storedPages", "storedRecipients", "createdAtMs", "sealedAtMs"]) && root.schemaVersion === ROOT_SCHEMA && parentID(root.parentId) &&
    /^cms-sha256-v1:[a-f\d]{64}$/.test(root.sourceRevision || "") && hex(root.envelopeHash) && validEvent(root.event, root.parentId, root.sourceRevision) &&
    hex(root.snapshotHash) && timestamp(root.snapshotAtMs) && timestamp(root.expiresAtMs) && root.expiresAtMs > root.snapshotAtMs &&
    validExpected(root.expected, root.total) && Array.isArray(root.boundaries) && root.boundaries.length === root.expected.length &&
    root.boundaries.every((id, i) => installationID(id) && (i === 0 || root.boundaries[i - 1] < id)) && Buffer.byteLength(JSON.stringify(core(root))) <= MANIFEST_BYTES && rootID(root) === id && timestamp(root.createdAtMs) && root.createdAtMs >= root.snapshotAtMs &&
    Number.isSafeInteger(root.storedPages) && root.storedPages >= 0 && root.storedPages <= root.expected.length &&
    root.storedRecipients === root.expected.slice(0, root.storedPages).reduce((count, row) => count + row.count, 0) &&
    ((root.phase === "staging" && root.sealedAtMs === null) || (root.phase === "sealed" && timestamp(root.sealedAtMs) && root.sealedAtMs >= root.createdAtMs &&
      root.storedPages === root.expected.length && root.storedRecipients === root.total));
}
function validPage(id, root, page, index) {
  const proof = root?.expected?.[index];
  return proof && exact(page, ["schemaVersion", "rootId", "pageIndex", "hash", "deliveries"]) && page.schemaVersion === 1 && page.rootId === id &&
    page.pageIndex === index && page.hash === proof.hash && Array.isArray(page.deliveries) && page.deliveries.length === proof.count &&
    page.deliveries.every((row, i) => validDescriptor(row, root.parentId) && (i === 0 || page.deliveries[i - 1].installationId < row.installationId)) &&
    page.deliveries[0].installationId === root.boundaries[index] && (index === root.expected.length - 1 || page.deliveries.at(-1).installationId < root.boundaries[index + 1]) &&
    pageDigest(page.deliveries) === proof.hash && Buffer.byteLength(JSON.stringify(page)) <= PAGE_BYTES;
}
function acceptedInput(rootId, root, parentId, parent, plan, now) {
  return timestamp(now) && validRoot(rootId, root) && root.phase === "sealed" && root.parentId === parentId && root.sourceRevision === parent.sourceRevision &&
    root.envelopeHash === parent.fanout?.envelopeHash && digest(root.event) === digest(parent.fanout?.event) &&
    plan?.schemaVersion === 2 && plan.frozenRootId === rootId && parent.fanout?.frozenRootId === rootId &&
    plan.planHash === digest([root.event, root.envelopeHash, root.snapshotHash, root.expected]) &&
    plan.snapshotHash === root.snapshotHash && plan.snapshotAtMs === root.snapshotAtMs && digest(plan.expected) === digest(root.expected) && plan.total === root.total &&
    timestamp(plan.acceptedAtMs) && plan.acceptedAtMs >= root.sealedAtMs && plan.acceptedAtMs >= root.snapshotAtMs &&
    plan.acceptedAtMs - root.snapshotAtMs <= SNAPSHOT_AGE_MS && plan.createdAtMs === plan.acceptedAtMs &&
    plan.expiresAtMs === root.expiresAtMs && parent.expiresAtMs === root.expiresAtMs && now >= plan.acceptedAtMs && now < root.expiresAtMs;
}
function createFrozenInputStore({db, now = Date.now}) {
  const roots = db.collection(INPUT_ROOTS), pages = db.collection(INPUT_PAGES);
  return {
    async persist({parentId, sourceRevision, envelopeHash, event, snapshotHash, snapshotAtMs, expected, total, expiresAtMs, batches}) {
      // Caller-owned objects may change while a transaction is awaiting. Own exactly the values validated here.
      ({event, expected, batches} = structuredClone({event, expected, batches}));
      if (!Array.isArray(batches) || batches.some((rows) => !Array.isArray(rows) || !rows.length)) throw new Error("Invalid frozen batches");
      const root = {...core({parentId, sourceRevision, envelopeHash, event, snapshotHash, snapshotAtMs, expected, total, expiresAtMs, boundaries: batches.map((rows) => rows[0].installationId)}),
        phase: "staging", storedPages: 0, storedRecipients: 0, createdAtMs: now(), sealedAtMs: null};
      const id = rootID(root);
      if (!validRoot(id, root) || !Array.isArray(batches) || batches.length !== expected.length) throw new Error("Invalid frozen input");
      let previous = "";
      for (let index = 0; index < batches.length; index++) {
        const page = {schemaVersion: 1, rootId: id, pageIndex: index, hash: expected[index].hash, deliveries: batches[index]};
        if (!validPage(id, root, page, index) || page.deliveries[0].installationId <= previous) throw new Error("Invalid frozen descriptor page");
        previous = page.deliveries.at(-1).installationId;
      }
      await db.runTransaction(async (tx) => {
        const ref = roots.doc(id), snapshot = await tx.get(ref);
        if (snapshot.exists) {if (!validRoot(id, snapshot.data())) throw new Error("Corrupt frozen input root");return;}
        tx.set(ref, root);
      });
      // Each page and its progress receipt commit together. Interrupted pre-input is an inert orphan.
      for (let index = 0; index < batches.length; index++) await db.runTransaction(async (tx) => {
        const ref = roots.doc(id), pageRef = pages.doc(inputPageID(id, index)), [rootSnap, pageSnap] = await Promise.all([tx.get(ref), tx.get(pageRef)]), current = rootSnap.data();
        if (!validRoot(id, current)) throw new Error("Corrupt frozen input root");
        if (pageSnap.exists) {
          if (!validPage(id, current, pageSnap.data(), index) || current.storedPages <= index) throw new Error("Corrupt frozen input page");return;
        }
        if (current.phase !== "staging" || current.storedPages !== index) throw new Error("Incomplete frozen input ordering");
        const page = {schemaVersion: 1, rootId: id, pageIndex: index, hash: expected[index].hash, deliveries: batches[index]};
        tx.set(pageRef, page);tx.set(ref, {...current, storedPages: index + 1, storedRecipients: current.storedRecipients + batches[index].length});
      });
      await db.runTransaction(async (tx) => {
        const ref = roots.doc(id), current = (await tx.get(ref)).data();
        if (!validRoot(id, current)) throw new Error("Corrupt frozen input root");
        if (current.phase === "sealed") return;
        const sealedAtMs = now();
        if (current.storedPages !== current.expected.length || current.storedRecipients !== current.total || !timestamp(sealedAtMs) || sealedAtMs < current.createdAtMs) throw new Error("Incomplete frozen input");
        tx.set(ref, {...current, phase: "sealed", sealedAtMs});
      });
      return id;
    },
  };
}
module.exports = {INPUT_ROOTS, INPUT_PAGES, ROOT_SCHEMA, PAGE_SIZE, MAX_PAGES, MANIFEST_BYTES, PAGE_BYTES, SNAPSHOT_AGE_MS, digest, compact, pageDigest, validDescriptor,
  validExpected, validRoot, validPage, validEvent, rootID, inputID, inputPageID, acceptedInput, createFrozenInputStore};

"use strict";
const {test, before} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {SCOPE, MEMBERSHIPS, RECEIPTS, REVISIONS, MAX_RECEIPT_BYTES, ReaderMutationError,
  createReaderMutationStore, readerMutationRequestID, validateReaderMutationLedgerRecord} = require("./readerMutation");
const wire = require("./fixtures/reader-mutation-wire-v1.json");
const NOW = Date.parse("2026-10-25T12:00:00Z"), UID = "reader_a";
const clone = (value) => structuredClone(value);
const hash = (value) => createHash("sha256").update(value, "utf8").digest("hex");
const invalid = (value, message) => assert.throws(() => validateReaderMutationLedgerRecord(value),
  (error) => error instanceof ReaderMutationError && error.code === "invalid_ledger_record" && error.message === "invalid_ledger_record", message);

// The real mutation store creates every accepted ledger shape. This adapter is
// local storage only; it performs no Firebase/SDK initialization or network I/O.
async function generatedLedgers() {
  const documents = new Map([[`${MEMBERSHIPS}/${UID}`, {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "active"}]]);
  const db = {
    collection: (path) => ({doc: (id) => ({path: `${path}/${id}`})}),
    async runTransaction(callback) {
      const operations = [];
      const result = await callback({
        async get(reference) {
          assert.equal(operations.length, 0, "All transaction reads precede writes");
          return {data: () => clone(documents.get(reference.path))};
        },
        set: (reference, value) => operations.push({path: reference.path, value: clone(value)}),
        delete: (reference) => operations.push({path: reference.path, remove: true}),
      });
      for (const operation of operations) {
        if (operation.remove) documents.delete(operation.path);else documents.set(operation.path, operation.value);
      }
      return result;
    },
  };
  const store = createReaderMutationStore({db, now: () => NOW, verifyBoundary: async ({ownerUID, membershipEpoch}) => ({
    schemaVersion: 1, scope: SCOPE, ownerUID, membershipEpoch, readerSchemaVersion: 1,
    writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), validUntilMs: NOW + 60000,
    allowedPaths: [`users/${ownerUID}/favorites`, `users/${ownerUID}/preferences/reader`],
  })});
  const commit = (request) => store.commit({request, authorizationValidUntilMs: NOW + 60000});
  const entry = (collection, matches) => {
    const found = [...documents].find(([key, value]) => key.startsWith(collection + "/") && matches(value));
    assert.ok(found, `A real mutation must create ${collection}`);
    return {collection, documentID: found[0].slice(collection.length + 1), ownerUID: UID, membershipEpoch: 1, record: clone(found[1])};
  };
  const favorite = clone(wire.vectors.find((value) => value.name === "favorite-unicode-metadata").request);
  await commit(favorite);
  const favoriteReceipt = entry(RECEIPTS, (row) => row.requestID === readerMutationRequestID(favorite));
  const favoriteRevision = entry(REVISIONS, (row) => row.target.kind === "favorite");
  const removal = {...favorite, mutationID: "62345678-1234-1234-1234-123456789abc", expectedRevision: 1,
    kind: "favorite_remove", payload: {articleID: favorite.payload.id}};
  await commit(removal);
  const removalReceipt = entry(RECEIPTS, (row) => row.requestID === readerMutationRequestID(removal));
  const removalRevision = entry(REVISIONS, (row) => row.target.kind === "favorite");
  const preference = clone(wire.vectors.find((value) => value.name === "preferences-ordered-unicode").request);
  await commit(preference);
  const preferenceReceipt = entry(RECEIPTS, (row) => row.requestID === readerMutationRequestID(preference));
  const preferenceRevision = entry(REVISIONS, (row) => row.target.kind === "preferences");
  // The validator cannot consult any live target, receipt, membership or DB.
  documents.clear();
  return {favoriteReceipt, favoriteRevision, removalReceipt, removalRevision, preferenceReceipt, preferenceRevision};
}
let rows;
before(async () => {rows = await generatedLedgers();});

test("actual favorite, historical removal and preferences ledger rows validate after all source documents are gone", () => {
  for (const input of Object.values(rows)) assert.deepEqual(validateReaderMutationLedgerRecord(input), input.record);
  assert.equal(rows.removalRevision.record.exists, false);
  assert.equal(rows.removalRevision.record.revision, 2);
  assert.equal(rows.favoriteReceipt.record.receipt.committedRevision, 1, "Historical receipt validation does not require the latest revision");
});

test("validated ledger rows are independent immutable snapshots including nested requests, targets and topic arrays", () => {
  for (const name of ["preferenceReceipt", "preferenceRevision"]) {
    const input = clone(rows[name]), expected = clone(input.record), result = validateReaderMutationLedgerRecord(input);
    const checkFrozen = (value) => {
      if (value && typeof value === "object") {assert.equal(Object.isFrozen(value), true);Object.values(value).forEach(checkFrozen);}
    };
    checkFrozen(result);
    input.record.ownerUID = "reader_b";
    if (input.record.receipt) input.record.receipt.request.payload.interestTopicIDs.push("new-topic");
    else input.record.target.id = "other";
    assert.deepEqual(result, expected);
    assert.throws(() => {result.ownerUID = "reader_b";}, TypeError);
    if (result.receipt) assert.throws(() => result.receipt.request.payload.interestTopicIDs.push("new-topic"), TypeError);
  }
});

test("only the two exact ledger collections and bare deterministic hash document IDs are admitted", () => {
  for (const collection of [MEMBERSHIPS, "users", `${RECEIPTS}/nested`, "", null, 1]) {
    invalid({...clone(rows.favoriteReceipt), collection}, `collection ${collection}`);
  }
  for (const documentID of ["f".repeat(64), rows.favoriteReceipt.documentID.toUpperCase(), "", "../" + rows.favoriteReceipt.documentID,
    `${RECEIPTS}/${rows.favoriteReceipt.documentID}`, "a".repeat(63), "a".repeat(65), null, 1]) {
    invalid({...clone(rows.favoriteReceipt), documentID}, `document ID ${documentID}`);
  }
  invalid({...clone(rows.favoriteReceipt), collection: REVISIONS}, "A receipt cannot be interpreted as a revision");
  invalid({...clone(rows.favoriteRevision), collection: RECEIPTS}, "A revision cannot be interpreted as a receipt");
  invalid({...clone(rows.favoriteRevision), documentID: rows.preferenceRevision.documentID}, "A valid hash for another target is still rejected");
});

test("cleanup binding cannot select another owner or epoch even with an otherwise intact ledger", () => {
  for (const source of [rows.favoriteReceipt, rows.favoriteRevision]) {
    for (const ownerUID of ["reader_b", "reader_a/child", "", null, 42]) invalid({...clone(source), ownerUID}, `owner ${ownerUID}`);
    for (const membershipEpoch of [2, 0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1, "1", null]) {
      invalid({...clone(source), membershipEpoch}, `epoch ${membershipEpoch}`);
    }
  }
});

test("receipt validation rejects forged original identity, request, digest and nested acknowledgement", () => {
  const mutations = [
    ["record owner", (row) => {row.ownerUID = "reader_b";}],
    ["record epoch", (row) => {row.membershipEpoch = 2;}],
    ["original owner", (row) => {row.receipt.request.expectedUID = "reader_b";}],
    ["original epoch", (row) => {row.receipt.request.membershipEpoch = 2;}],
    ["original mutation ID", (row) => {row.receipt.request.mutationID = "72345678-1234-1234-1234-123456789abc";}],
    ["payload changed after receipt", (row) => {row.receipt.request.payload.name = "Different saved title";}],
    ["request fingerprint", (row) => {row.requestFingerprint = "f".repeat(64);}],
    ["record request ID", (row) => {row.requestID = "f".repeat(64);}],
    ["receipt request ID", (row) => {row.receipt.requestID = "f".repeat(64);}],
    ["receipt committed revision", (row) => {row.receipt.committedRevision += 1;}],
    ["receipt status", (row) => {row.receipt.status = "pending";}],
    ["boundary digest", (row) => {row.boundaryFingerprint = "not-a-hash";}],
    ["missing nested receipt", (row) => {delete row.receipt;}],
  ];
  for (const [name, change] of mutations) {const input = clone(rows.favoriteReceipt);change(input.record);invalid(input, name);}
});

test("ledger schemas require exact versions, scopes and fields at both outer and nested levels", () => {
  for (const source of Object.values(rows)) {
    for (const field of ["schemaVersion", "scope", "ownerUID", "membershipEpoch", "boundaryFingerprint"]) {
      const input = clone(source);delete input.record[field];invalid(input, `missing ${field}`);
    }
    for (const change of [
      (row) => {row.schemaVersion = 2;}, (row) => {row.scope = "reader-cloud-slice-v1";},
      (row) => {row.unrecognized = true;}, (row) => {row.membershipEpoch = "1";},
    ]) {const input = clone(source);change(input.record);invalid(input);}
  }
  for (const change of [
    (row) => {row.receipt.extra = true;}, (row) => {row.receipt.request.extra = true;},
    (row) => {row.receipt.request.payload.extra = true;}, (row) => {row.receipt.schemaVersion = 2;},
  ]) {const input = clone(rows.favoriteReceipt);change(input.record);invalid(input);}
});

test("revision target validation rejects forged shapes and paths even when the document hash is recomputed", () => {
  const targets = [
    null, [], {}, {kind: "unknown", id: "article"}, {kind: "preferences", id: "research"},
    {kind: "preferences", id: "reader", extra: true}, {kind: "favorite", id: "article", extra: true},
    ...["", ".", "..", "a/b", "__reserved__", " article", "article ", "a\u0000b", "a\u200bb", "a".repeat(513), null, 1]
      .map((id) => ({kind: "favorite", id})),
  ];
  for (const resource of targets) {
    const input = clone(rows.favoriteRevision);input.record.target = resource;
    input.documentID = hash(JSON.stringify([SCOPE, input.ownerUID, input.membershipEpoch, resource?.kind, resource?.id]));
    invalid(input, `target ${JSON.stringify(resource)}`);
  }
});

test("revision records reject mismatched binding, counters, operation and malformed digests", () => {
  const changes = [
    ["owner", (row) => {row.ownerUID = "reader_b";}], ["epoch", (row) => {row.membershipEpoch = 2;}],
    ...[0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1, "1", null].map((value) => [`revision ${value}`, (row) => {row.revision = value;}]),
    ["request ID", (row) => {row.lastRequestID = "not-a-hash";}],
    ["payload hash", (row) => {row.payloadFingerprint = "not-a-hash";}],
    ["boundary hash", (row) => {row.boundaryFingerprint = "not-a-hash";}],
    ["exists type", (row) => {row.exists = 1;}], ["last kind", (row) => {row.lastKind = "preferences_set";}],
    ["operation/existence mismatch", (row) => {row.lastKind = "favorite_remove";}],
  ];
  for (const [name, change] of changes) {const input = clone(rows.favoriteRevision);change(input.record);invalid(input, name);}
  for (const change of [(row) => {row.exists = false;}, (row) => {row.lastKind = "favorite_set";}]) {
    const input = clone(rows.preferenceRevision);change(input.record);invalid(input);
  }
});

test("a removed favorite keeps its exact article-bound payload digest and removal semantics", () => {
  for (const change of [
    (row) => {row.payloadFingerprint = "f".repeat(64);},
    (row) => {row.lastKind = "favorite_set";},
    (row) => {row.exists = true;},
  ]) {const input = clone(rows.removalRevision);change(input.record);invalid(input);}
  const retargeted = clone(rows.removalRevision);
  retargeted.record.target.id = "another-article";
  retargeted.documentID = hash(JSON.stringify([SCOPE, UID, 1, "favorite", "another-article"]));
  invalid(retargeted, "A correctly keyed target cannot reuse another target's removal digest");
});

test("independent revision validation does not claim to reconstruct a missing mutation UUID or target payload", () => {
  const input = clone(rows.favoriteRevision);
  input.record.lastRequestID = "c".repeat(64);
  input.record.payloadFingerprint = "d".repeat(64);
  assert.deepEqual(validateReaderMutationLedgerRecord(input), input.record,
    "Only digest format is knowable without the historical receipt or deleted target; cleanup authority is separate");
});

test("malformed JS, cycles, accessors and oversize records fail with one fixed error without executing accessors", () => {
  let accessorCalls = 0;
  const changes = [
    (row) => {row.extra = undefined;}, (row) => {row.extra = NaN;}, (row) => {row.extra = Infinity;},
    (row) => {row.extra = 1n;}, (row) => {row.extra = new Date();}, (row) => {row.extra = new Map();},
    (row) => {row.extra = () => {};}, (row) => {row.extra = row;},
    (row) => {row.extra = new Array(2);}, (row) => {row[Symbol("hidden")] = true;},
    (row) => {Object.defineProperty(row, "hidden", {value: true});},
    (row) => {Object.defineProperty(row, "scope", {enumerable: true, get() {accessorCalls += 1;throw new Error("PRIVATE");}});},
    (row) => {row.extra = "a".repeat(MAX_RECEIPT_BYTES + 5000);},
  ];
  for (const change of changes) {const input = clone(rows.favoriteReceipt);change(input.record);invalid(input);}
  assert.equal(accessorCalls, 0);
});

test("malformed envelopes and record roots never leak raw type errors or adapter exceptions", () => {
  for (const input of [undefined, null, false, 1, "record", [], {}, {...clone(rows.favoriteReceipt), extra: true}]) invalid(input);
  for (const record of [undefined, null, false, 1, "record", [], Object.create(null)]) invalid({...clone(rows.favoriteReceipt), record});
  const accessor = clone(rows.favoriteReceipt);
  Object.defineProperty(accessor, "collection", {enumerable: true, get() {throw new Error("PRIVATE ADAPTER ERROR");}});
  invalid(accessor);
  const broken = Proxy.revocable({}, {});broken.revoke();invalid(broken.proxy);
});

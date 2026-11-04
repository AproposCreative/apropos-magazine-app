// Deterministic wire fixtures from the actual SDK-free stores. No Firebase,
// provider, endpoint, credentials or network is initialized by this helper.
const assert = require("node:assert/strict");
const {SCOPE, LEDGER_SCOPE, UNRESOLVED, LEDGER_UNRESOLVED, MEMBERSHIPS, REQUESTS,
  createReaderAccountDeletionStore, beginReaderAccountDeletion, runReaderAccountDeletion} = require("../readerAccountDeletion");
const {SCOPE: MUTATION_SCOPE, RECEIPTS, REVISIONS, createReaderMutationStore} = require("../readerMutation");
const NOW = Date.parse("2026-10-25T12:00:00Z"), APP = "fixture-ios-app";
const copy = (value) => structuredClone(value);

async function fixture(uid, epoch, populate = false) {
  const documents = new Map(), ref = (path) => ({path});
  let shouldFailCommit = false, tail = Promise.resolve();
  const snapshot = (path) => {
    const value = copy(documents.get(path));
    return {ref: ref(path), exists: value !== undefined, data: () => copy(value)};
  };
  const collection = (queryPath, filters = [], count) => ({queryPath, filters, count,
    doc: (id) => ref(`${queryPath}/${id}`),
    where: (field, operation, value) => collection(queryPath, [...filters, [field, operation, value]], count),
    limit: (limit) => collection(queryPath, filters, limit)});
  const db = {collection, runTransaction(callback) {
    const current = tail.then(async () => {
      const writes = [];
      const result = await callback({
        async get(reference) {
          assert.equal(writes.length, 0, "Transaction reads must precede every write");
          if (!reference.queryPath) return snapshot(reference.path);
          const prefix = reference.queryPath + "/";
          return {docs: [...documents.keys()].filter((key) => key.startsWith(prefix) && !key.slice(prefix.length).includes("/"))
            .filter((key) => reference.filters.every(([field, operation, value]) => {
              assert.equal(operation, "==");return documents.get(key)?.[field] === value;
            })).sort().slice(0, reference.count).map(snapshot)};
        },
        set: (reference, value) => writes.push({path: reference.path, value: copy(value)}),
        delete: (reference) => writes.push({path: reference.path, remove: true}),
      });
      if (shouldFailCommit) {shouldFailCommit = false;throw new Error("Local fixture commit interruption");}
      for (const write of writes) {
        if (write.remove) documents.delete(write.path);else documents.set(write.path, write.value);
      }
      return result;
    });
    tail = current.catch(() => {});return current;
  }};
  const common = (binding) => ({schemaVersion: 1, ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch,
    writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), validUntilMs: NOW + 60000});
  const paths = (ownerUID) => [`users/${ownerUID}/favorites`, `users/${ownerUID}/preferences/reader`];
  const store = createReaderAccountDeletionStore({db, now: () => NOW,
    verifyBoundary: async (binding) => ({...common(binding), scope: SCOPE, readerSchemaVersion: 1,
      allowedPaths: paths(binding.ownerUID), unresolved: [...UNRESOLVED]}),
    verifyLedgerBoundary: async (binding) => ({...common(binding), scope: LEDGER_SCOPE,
      parentRequestID: binding.parentRequestID, mutationSchemaVersion: 1,
      collections: [RECEIPTS, REVISIONS], unresolved: [...LEDGER_UNRESOLVED]}),
  });
  const mutationStore = createReaderMutationStore({db, now: () => NOW,
    verifyBoundary: async (binding) => ({...common(binding), scope: MUTATION_SCOPE,
      readerSchemaVersion: 1, allowedPaths: paths(binding.ownerUID)}),
  });
  documents.set(`${MEMBERSHIPS}/${uid}`, {schemaVersion: 1, ownerUID: uid, epoch, state: "active"});
  const sharedProfile = {displayName: "Shared Research profile", bookmarkedArticles: ["legacy"]};
  documents.set(`users/${uid}`, sharedProfile);
  if (populate) {
    const payloads = [
      ["favorite_set", {id: "article-1", pressAccreditation: false, name: "Første artikel"}],
      ["favorite_set", {id: "article-2", pressAccreditation: false, name: "Anden artikel"}],
      ["preferences_set", {interestTopicIDs: ["kultur", "musik"], onboardingCompleted: true}],
    ];
    for (const [index, [kind, payload]] of payloads.entries()) {
      await mutationStore.commit({authorizationValidUntilMs: NOW + 60000, request: {schemaVersion: 1, expectedUID: uid,
        membershipEpoch: epoch, mutationID: `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
        expectedRevision: 0, kind, payload}});
    }
  }
  const begin = (request) => beginReaderAccountDeletion({store, request, expectedAppID: APP, now: () => NOW,
    verifyClient: async () => ({uid, tenantID: null, appID: APP, authTimeMs: NOW - 1000,
      issuedAtMs: NOW - 500, expiresAtMs: NOW + 600000})});
  const parent = await begin({expectedUID: uid, membershipEpoch: epoch});
  const parentReceipt = await runReaderAccountDeletion({store, requestID: parent.requestID});
  assert.equal(parentReceipt.status, "scopedCloudDataRemoved");
  const parentRecord = copy(documents.get(`${REQUESTS}/${parent.requestID}`));
  const frozen = copy(documents.get(`${MEMBERSHIPS}/${uid}`));
  const request = {schemaVersion: 1, scope: LEDGER_SCOPE, expectedUID: uid, membershipEpoch: epoch, parentRequestID: parent.requestID};
  return {request, parentReceipt, begin: () => begin(request),
    run: (requestID, maximumSteps = 10) => runReaderAccountDeletion({store, requestID, maximumSteps, scope: LEDGER_SCOPE}),
    failNext: () => {shouldFailCommit = true;},
    verifyPreserved() {
      assert.deepEqual(documents.get(`${REQUESTS}/${parent.requestID}`), parentRecord);
      assert.deepEqual(documents.get(`${MEMBERSHIPS}/${uid}`), frozen);
      assert.deepEqual(documents.get(`users/${uid}`), sharedProfile);
    },
  };
}

async function generateReaderLedgerCleanupWire() {
  const main = await fixture("reader_a", 1, true);
  const admissionPending = await main.begin();
  const boundedPending = await main.run(admissionPending.requestID, 1);
  const progressPending = await main.begin();
  main.failNext();
  const paused = await main.run(admissionPending.requestID);
  const complete = await main.run(admissionPending.requestID);
  assert.equal(paused.status, "paused");assert.equal(paused.code, "transport_unavailable");
  assert.equal(complete.status, "ledgerDataRemoved");
  assert.equal(complete.removedReceiptDocuments, 3);assert.equal(complete.removedRevisionDocuments, 3);
  main.verifyPreserved();
  const vectors = [];
  for (const [name, uid, epoch] of [["minimum-uid", "a", 1], ["punctuation-uid", "reader-Z_9", 42],
    ["maximum-uid", "a".repeat(128), 1], ["maximum-safe-epoch", "reader_a", Number.MAX_SAFE_INTEGER]]) {
    const current = await fixture(uid, epoch);
    const accepted = await current.begin();current.verifyPreserved();
    vectors.push({name, request: current.request, requestID: accepted.requestID});
  }
  return {schemaVersion: 1, scope: LEDGER_SCOPE, request: main.request, parentReceipt: main.parentReceipt,
    receipts: {admissionPending, boundedPending, progressPending, paused, complete}, vectors};
}
module.exports = {generateReaderLedgerCleanupWire};
if (require.main === module) {
  generateReaderLedgerCleanupWire().then((value) => {process.stdout.write(JSON.stringify(value, null, 2) + "\n");},
    (error) => {process.stderr.write(String(error) + "\n");process.exitCode = 1;});
}

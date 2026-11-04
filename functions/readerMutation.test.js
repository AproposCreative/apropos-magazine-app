const {test} = require("node:test");
const assert = require("node:assert/strict");
const {SCOPE, MEMBERSHIPS, RECEIPTS, REVISIONS, validateReaderMutationRequest, validateReaderMutationReceipt,
  readerMutationRequestID, createReaderMutationStore, commitReaderMutation} = require("./readerMutation");
const deletion = require("./readerAccountDeletion");
const wire = require("./fixtures/reader-mutation-wire-v1.json");
const NOW = Date.parse("2026-10-23T12:00:00Z"), UID = "reader_a", APP = "verified-ios-app";
const clone = (value) => structuredClone(value), code = (value) => (error) => error.code === value && error.message === value;
const request = (overrides = {}) => ({schemaVersion: 1, expectedUID: UID, membershipEpoch: 1,
  mutationID: "12345678-1234-1234-1234-123456789abc", expectedRevision: 0, kind: "favorite_set", payload: {id: "article-1", pressAccreditation: false}, ...overrides});
const next = (previous, overrides = {}) => ({...previous, mutationID: "22345678-1234-1234-1234-123456789abc", expectedRevision: previous.expectedRevision + 1, ...overrides});
const favoritePath = `users/${UID}/favorites/article-1`, preferencesPath = `users/${UID}/preferences/reader`;
function fixture({boundaryEnabled = true} = {}) {
  let nowMs = NOW, tail = Promise.resolve(), failCommit = false, loseResponse = false, retryCallback, beforeTransaction, beforeBoundary, proofOverride;
  const documents = new Map(), commits = [], reads = [], callbacks = [];
  const reference = (path) => ({path}), snapshot = (path) => ({exists: documents.has(path), ref: reference(path), data: () => clone(documents.get(path))});
  const db = {
    collection: (path) => ({doc: (id) => reference(`${path}/${id}`), limit: (count) => ({queryPath: path, count})}),
    runTransaction: (callback) => {
      const result = tail.then(async () => {
        if (beforeTransaction) {const perform = beforeTransaction;beforeTransaction = undefined;await perform();}
        let wrote = false;const pending = [];
        const transaction = {
          get: async (ref) => {
            assert.equal(wrote, false, "Every authoritative read precedes every write, including the injected boundary");reads.push(ref.path || ref.queryPath);
            if (ref.queryPath) {const prefix = ref.queryPath + "/";return {docs: [...documents.keys()].filter((path) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/")).sort().slice(0, ref.count).map(snapshot)};}
            return snapshot(ref.path);
          },
          set: (ref, value) => {wrote = true;pending.push({path: ref.path, value: clone(value)});},
          delete: (ref) => {wrote = true;pending.push({path: ref.path, remove: true});},
        };
        callbacks.push("attempt");let result = await callback(transaction);
        if (retryCallback) {const retry = retryCallback;retryCallback = undefined;pending.length = 0;wrote = false;await retry();callbacks.push("retry");result = await callback(transaction);}
        if (failCommit) {failCommit = false;throw Error("PRIVATE DATABASE DETAIL");}
        for (const operation of pending) {if (operation.remove) documents.delete(operation.path);else documents.set(operation.path, operation.value);}
        commits.push(pending);
        if (loseResponse) {loseResponse = false;throw Error("PRIVATE RESPONSE TOKEN");}
        return result;
      });tail = result.catch(() => {});return result;
    },
  };
  const capability = (ownerUID = UID, membershipEpoch = 1) => ({schemaVersion: 1, scope: SCOPE, ownerUID, membershipEpoch,
    readerSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), validUntilMs: nowMs + 60000,
    allowedPaths: [`users/${ownerUID}/favorites`, `users/${ownerUID}/preferences/reader`]});
  const boundary = async ({transaction, ownerUID, membershipEpoch}) => {
    // Exercise the same transaction's read-before-write contract at the adapter seam.
    await transaction.get(db.collection("test_boundary_attestations").doc("local_fixture"));
    if (beforeBoundary) {const perform = beforeBoundary;beforeBoundary = undefined;await perform();}
    return {...capability(ownerUID, membershipEpoch), ...proofOverride};
  };
  const store = createReaderMutationStore({db, now: () => nowMs, ...(boundaryEnabled ? {verifyBoundary: boundary} : {})});
  const identity = (overrides = {}) => ({uid: UID, appID: APP, issuedAtMs: nowMs - 1000, expiresAtMs: nowMs + 600000,
    appCheckIssuedAtMs: nowMs - 500, appCheckExpiresAtMs: nowMs + 60000, ...overrides});
  const commit = (value = request(), auth = identity()) => commitReaderMutation({store, verifyClient: async () => auth, expectedAppID: APP, request: value, now: () => nowMs});
  const seed = (uid = UID, epoch = 1) => {
    documents.set(`${MEMBERSHIPS}/${uid}`, {schemaVersion: 1, ownerUID: uid, epoch, state: "active"});
    documents.set(`users/${uid}`, {role: "editor", researchArticle: "keep", bookmarkedArticles: ["legacy"], newsletter: true});
    documents.set(`users/${uid}/preferences/other`, {secretSharedField: "keep"});
    documents.set(`research/articles/${uid}`, {title: "keep"});
  };
  return {db, documents, commits, reads, callbacks, store, identity, commit, seed, capability,
    now: () => nowMs, advance: (milliseconds) => {nowMs += milliseconds;},
    fail: () => {failCommit = true;}, lose: () => {loseResponse = true;}, retry: (fn = () => {}) => {retryCallback = fn;},
    before: (fn) => {beforeTransaction = fn;}, atBoundary: (fn) => {beforeBoundary = fn;}, override: (value) => {proofOverride = value;},
    revisionRows: () => [...documents.entries()].filter(([path]) => path.startsWith(REVISIONS + "/")),
    receiptRows: () => [...documents.entries()].filter(([path]) => path.startsWith(RECEIPTS + "/")),
  };
}
for (const vector of wire.vectors) test(`shared wire ${vector.name} executes against the actual transactional store`, async () => {
  const f = fixture();f.seed(vector.request.expectedUID, vector.request.membershipEpoch);
  assert.equal(readerMutationRequestID(validateReaderMutationRequest(vector.request)), vector.requestID);
  assert.deepEqual(validateReaderMutationReceipt(vector.receipt, vector.request), vector.receipt);
  if (vector.request.expectedRevision === 0) {
    const result = await f.commit(vector.request, f.identity({uid: vector.request.expectedUID}));assert.deepEqual(result, vector.receipt);
  } else {
    // Wire decoding alone never authorizes skipping the actual CAS state.
    await assert.rejects(f.commit(vector.request, f.identity({uid: vector.request.expectedUID})), code("revision_conflict"));assert.equal(f.commits.length, 0);
  }
});
for (const vector of wire.invalidRequests) test(`shared malformed request ${vector.name} fails before database access`, async () => {
  const f = fixture();f.seed();await assert.rejects(f.commit(vector.request), code("invalid_request"));assert.equal(f.reads.length, 0);assert.equal(f.commits.length, 0);
});
test("absent boundary or public verifier is inert and cannot initialize a data operation", async () => {
  const f = fixture({boundaryEnabled: false});f.seed();await assert.rejects(f.commit(), code("reader_boundary_unavailable"));assert.equal(f.reads.length, 0);
  await assert.rejects(createReaderMutationStore().commit({request: request()}), code("reader_boundary_unavailable"));
  await assert.rejects(commitReaderMutation({request: request()}), code("authentication_unavailable"));
});
test("new favorite commit writes only bounded metadata plus marker and two server ledgers atomically", async () => {
  const f = fixture();f.seed();const before = new Map(f.documents);const result = await f.commit();
  assert.equal(result.committedRevision, 1);assert.equal(result.status, "committed");assert.deepEqual(result.request, request());
  assert.equal(f.documents.get(favoritePath).readerMutation.membershipEpoch, 1);assert.equal(f.documents.get(favoritePath).readerMutation.requestID, result.requestID);
  assert.equal(f.commits.length, 1);assert.equal(f.commits[0].length, 3);assert.equal(f.revisionRows().length, 1);assert.equal(f.receiptRows().length, 1);
  for (const [path, value] of before) assert.deepEqual(f.documents.get(path), value, `Shared/Research/membership preserved: ${path}`);
  assert.equal(Object.hasOwn(f.documents.get(favoritePath), "content"), false);
});
test("preferences retain ordered topics and do not touch shared profile or favorites", async () => {
  const f = fixture();f.seed();await f.commit();const favorite = clone(f.documents.get(favoritePath));
  const prefs = request({mutationID: "32345678-1234-1234-1234-123456789abc", kind: "preferences_set", payload: {interestTopicIDs: ["musik", "film"], onboardingCompleted: true}});
  await f.commit(prefs);assert.deepEqual(f.documents.get(preferencesPath).interestTopicIDs, ["musik", "film"]);assert.deepEqual(f.documents.get(favoritePath), favorite);
  await f.commit(next(prefs, {payload: {interestTopicIDs: [], onboardingCompleted: false}}));assert.deepEqual(f.documents.get(preferencesPath).interestTopicIDs, []);assert.equal(f.documents.get(preferencesPath).onboardingCompleted, false);
});
test("parallel duplicates commit one intent and do not increment revision twice", async () => {
  const f = fixture();f.seed();const values = await Promise.all([f.commit(), f.commit(), f.commit()]);assert.deepEqual(values[0], values[1]);assert.deepEqual(values[1], values[2]);
  assert.equal(f.commits.filter((ops) => ops.length).length, 1);assert.equal(f.documents.get(favoritePath).readerMutation.revision, 1);
});
test("two different intents with the same CAS revision cannot both overwrite a target", async () => {
  const f = fixture();f.seed();const results = await Promise.allSettled([f.commit(), f.commit(next(request(), {expectedRevision: 0, payload: {id: "article-1", pressAccreditation: true}}))]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);assert.equal(results.find((r) => r.status === "rejected").reason.code, "revision_conflict");
  assert.equal(f.documents.get(favoritePath).pressAccreditation, false);assert.equal(f.receiptRows().length, 1);
});
test("remove retains a revision tombstone and a later favorite cannot be erased by an old remove", async () => {
  const f = fixture();f.seed();await f.commit();const remove = next(request(), {kind: "favorite_remove", payload: {articleID: "article-1"}});
  const oldReceipt = await f.commit(remove);assert.equal(f.documents.has(favoritePath), false);assert.equal(f.revisionRows()[0][1].revision, 2);
  const restored = next(remove, {mutationID: "32345678-1234-1234-1234-123456789abc", kind: "favorite_set", payload: {id: "article-1", pressAccreditation: true, name: "Newest"}});
  await f.commit(restored);const before = clone(f.documents.get(favoritePath));assert.deepEqual(await f.commit(remove), oldReceipt);assert.deepEqual(f.documents.get(favoritePath), before);
  await assert.rejects(f.commit(next(remove, {mutationID: "42345678-1234-1234-1234-123456789abc", expectedRevision: 1})), code("revision_conflict"));assert.deepEqual(f.documents.get(favoritePath), before);
});
test("removing an absent favorite still commits a tombstone, so revision zero never reappears", async () => {
  const f = fixture();f.seed();const remove = request({kind: "favorite_remove", payload: {articleID: "article-1"}});await f.commit(remove);
  assert.equal(f.documents.has(favoritePath), false);assert.equal(f.revisionRows()[0][1].exists, false);
  await assert.rejects(f.commit(next(request(), {expectedRevision: 0})), code("revision_conflict"));assert.equal(f.documents.has(favoritePath), false);
});
test("lost response retries return original historical acknowledgement after a newer intent", async () => {
  const f = fixture();f.seed();f.lose();await assert.rejects(f.commit(), code("transport_unavailable"));
  const first = clone(f.receiptRows()[0][1].receipt);const later = next(request(), {payload: {id: "article-1", pressAccreditation: true, name: "New"}});await f.commit(later);
  assert.deepEqual(await f.commit(), first);assert.equal(f.documents.get(favoritePath).name, "New");assert.equal(f.documents.get(favoritePath).readerMutation.revision, 2);assert.equal(f.receiptRows().length, 2);
});
test("failed physical commit leaves no half-written target/revision/receipt", async () => {
  const f = fixture();f.seed();const before = clone([...f.documents]);f.fail();await assert.rejects(f.commit(), code("transport_unavailable"));assert.deepEqual([...f.documents], before);
  await f.commit();assert.equal(f.commits.length, 1);
});
for (const [name, change] of [
  ["payload", (r) => ({...r, payload: {...r.payload, name: "Different"}})],
  ["target", (r) => ({...r, payload: {...r.payload, id: "article-2"}})],
  ["kind", (r) => ({...r, kind: "favorite_remove", payload: {articleID: "article-1"}})],
  ["revision", (r) => ({...r, expectedRevision: 1})],
]) test(`same mutationID cannot be reused for different ${name}`, async () => {
  const f = fixture();f.seed();await f.commit();const before = clone([...f.documents]);await assert.rejects(f.commit(change(request())), code("mutation_id_conflict"));assert.deepEqual([...f.documents], before);
});
test("request is copied before verifier awaits; caller mutation cannot retag owner/epoch/payload", async () => {
  const f = fixture();f.seed();const input = request();let release;const gate = new Promise((resolve) => {release = resolve;});
  const pending = commitReaderMutation({store: f.store, request: input, expectedAppID: APP, verifyClient: async () => {await gate;return f.identity();}, now: f.now});
  input.expectedUID = "reader_b";input.membershipEpoch = 2;input.payload.name = "Late";release();const receipt = await pending;
  assert.deepEqual(receipt.request, request());assert.equal(f.documents.get(favoritePath).name, undefined);assert.equal(f.documents.has("users/reader_b/favorites/article-1"), false);
});
test("store independently snapshots a trusted binding before waiting for a transaction", async () => {
  const f = fixture();f.seed();const input = {request: request(), authorizationValidUntilMs: NOW + 60000};
  f.before(() => {input.request.payload.id = "other";input.authorizationValidUntilMs = 0;});const result = await f.store.commit(input);
  assert.equal(result.request.payload.id, "article-1");assert.equal(f.documents.has(favoritePath), true);
});
for (const [name, auth, error] of [
  ["missing", null, "identity_mismatch"], ["foreign uid", {uid: "reader_b"}, "identity_mismatch"], ["foreign app", {appID: "other"}, "identity_mismatch"],
  ["tenant identity", {tenantID: "tenant-a"}, "identity_mismatch"], ["expired auth", {expiresAtMs: NOW}, "authentication_rejected"],
  ["expired AppCheck", {appCheckExpiresAtMs: NOW}, "authentication_rejected"], ["future auth", {issuedAtMs: NOW + 30001}, "authentication_rejected"],
  ["future AppCheck", {appCheckIssuedAtMs: NOW + 30001}, "authentication_rejected"], ["missing AppCheck times", {appCheckExpiresAtMs: undefined}, "authentication_rejected"],
  ["invalid expiry type", {expiresAtMs: true}, "authentication_rejected"], ["auth expiry before issuance", {expiresAtMs: NOW + 100, issuedAtMs: NOW + 200}, "authentication_rejected"],
]) test(`public trusted identity rejects ${name} before database access`, async () => {
  const f = fixture();f.seed();await assert.rejects(f.commit(request(), auth === null ? null : f.identity(auth)), code(error));assert.equal(f.reads.length, 0);
});
test("verifier failure is sanitized and no raw token/provider detail is exposed", async () => {
  const f = fixture();await assert.rejects(commitReaderMutation({store: f.store, request: request(), expectedAppID: APP, now: f.now, verifyClient: async () => {throw Error("PRIVATE AUTH TOKEN");}}), code("authentication_rejected"));assert.equal(f.reads.length, 0);
});
test("a forged response from the storage adapter cannot become an accepted receipt", async () => {
  const f = fixture();f.seed();const good = await f.commit();
  await assert.rejects(commitReaderMutation({store: {commit: async () => ({...good, committedRevision: 2})}, request: request(), verifyClient: async () => f.identity(), expectedAppID: APP, now: f.now}), code("invalid_receipt"));
});
for (const [name, at] of [["queued transaction", "before"], ["awaited boundary", "atBoundary"], ["transaction retry", "retry"]]) test(`auth/AppCheck expiry checked again at ${name}`, async () => {
  const f = fixture();f.seed();f[at](() => f.advance(60001));await assert.rejects(f.commit(), code("authentication_expired"));assert.equal(f.commits.length, 0);assert.equal(f.documents.has(favoritePath), false);
});
for (const state of [undefined, {schemaVersion: 1, ownerUID: UID, epoch: 2, state: "active"}, {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "deletion_frozen", deletionRequestID: "a".repeat(64)}, {schemaVersion: 1, ownerUID: "reader_b", epoch: 1, state: "active"}, {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "active", extra: true}]) test(`membership ${JSON.stringify(state)} fails closed`, async () => {
  const f = fixture();f.seed();if (state) f.documents.set(`${MEMBERSHIPS}/${UID}`, state);else f.documents.delete(`${MEMBERSHIPS}/${UID}`);
  await assert.rejects(f.commit(), code("reader_membership_mismatch"));assert.equal(f.commits.length, 0);
});
test("epoch transition on transaction retry discards already staged old-epoch writes", async () => {
  const f = fixture();f.seed();f.retry(() => f.seed(UID, 2));await assert.rejects(f.commit(), code("reader_membership_mismatch"));assert.equal(f.documents.has(favoritePath), false);assert.equal(f.receiptRows().length, 0);assert.equal(f.commits.length, 0);
});
test("old E1 set/remove/replay cannot change a new E2 favorite", async () => {
  const f = fixture();f.seed();await f.commit();f.seed(UID, 2);
  // Explicit migration fixture: E2 starts after separate lifecycle removal; its ledger never adopts E1 rows.
  f.documents.delete(favoritePath);const e2 = request({membershipEpoch: 2, payload: {id: "article-1", pressAccreditation: true, name: "E2"}});await f.commit(e2);const before = clone([...f.documents]);
  for (const old of [request(), next(request(), {payload: {id: "article-1", pressAccreditation: false, name: "Old E1"}}), next(request(), {kind: "favorite_remove", payload: {articleID: "article-1"}})]) await assert.rejects(f.commit(old), code("reader_membership_mismatch"));
  assert.deepEqual([...f.documents], before);
});
test("new epoch cannot overwrite an old epoch target merely because its new ledger is absent", async () => {
  const f = fixture();f.seed();await f.commit();f.seed(UID, 2);const before = clone([...f.documents]);await assert.rejects(f.commit(request({membershipEpoch: 2})), code("migration_required"));assert.deepEqual([...f.documents], before);
});
for (const [name, value] of [
  ["absent scope", {scope: undefined}], ["foreign scope", {scope: "reader-cloud-slice-v1"}], ["foreign uid", {ownerUID: "reader_b"}], ["foreign epoch", {membershipEpoch: 2}],
  ["expired", {validUntilMs: NOW}], ["unknown field", {allowsSharedProfile: true}], ["unbounded paths", {allowedPaths: [`users/${UID}`]}], ["missing fence", {writerFenceRevision: null}],
]) test(`boundary ${name} cannot authorize a write`, async () => {
  const f = fixture();f.seed();f.override(value);await assert.rejects(f.commit(), code("reader_boundary_unverified"));assert.equal(f.commits.length, 0);
});
test("boundary revision change during retry fails closed even for the first mutation", async () => {
  const f = fixture();f.seed();f.retry(() => f.override({writerFenceRevision: "c".repeat(64)}));await assert.rejects(f.commit(), code("reader_boundary_changed"));assert.equal(f.commits.length, 0);
});
test("boundary revision changes cannot reauthorize old receipts or a later same-epoch intent", async () => {
  const f = fixture();f.seed();await f.commit();f.override({migrationRevision: "c".repeat(64)});
  await assert.rejects(f.commit(), code("reader_boundary_changed"));await assert.rejects(f.commit(next(request())), code("reader_boundary_changed"));assert.equal(f.commits.length, 1);
});
test("unchanged boundary transaction retry produces one physical commit", async () => {
  const f = fixture();f.seed();f.retry();const result = await f.commit();assert.equal(result.committedRevision, 1);assert.equal(f.callbacks.length, 2);assert.equal(f.commits.length, 1);assert.equal(f.receiptRows().length, 1);
});
for (const [name, path, value] of [["legacy favorite", favoritePath, {id: "article-1", content: "legacy"}], ["legacy preference", preferencesPath, {interestTopicIDs: ["film"], onboardingCompleted: true}]]) test(`${name} cannot be implicitly adopted by revision zero`, async () => {
  const f = fixture();f.seed();f.documents.set(path, value);const before = clone([...f.documents]);const req = path === preferencesPath ? request({kind: "preferences_set", payload: {interestTopicIDs: [], onboardingCompleted: false}}) : request();
  await assert.rejects(f.commit(req), code("migration_required"));assert.deepEqual([...f.documents], before);
});
for (const [name, change] of [["metadata changed", (value) => ({...value, name: "untracked"})], ["unknown Research field", (value) => ({...value, editorialRole: "owner"})], ["foreign marker epoch", (value) => ({...value, readerMutation: {...value.readerMutation, membershipEpoch: 2}})], ["unknown marker field", (value) => ({...value, readerMutation: {...value.readerMutation, admin: true}})]]) test(`${name} blocks both fresh writes and replay without overwriting`, async () => {
  const f = fixture();f.seed();await f.commit();f.documents.set(favoritePath, change(f.documents.get(favoritePath)));const before = clone([...f.documents]);
  await assert.rejects(f.commit(), code("target_state_mismatch"));await assert.rejects(f.commit(next(request())), code("target_state_mismatch"));assert.deepEqual([...f.documents], before);
});
test("missing target beneath a present revision is not silently recreated", async () => {
  const f = fixture();f.seed();await f.commit();f.documents.delete(favoritePath);await assert.rejects(f.commit(next(request())), code("target_state_mismatch"));assert.equal(f.documents.has(favoritePath), false);
});
test("a foreign target beneath a remove tombstone is never silently erased", async () => {
  const f = fixture();f.seed();const remove = request({kind: "favorite_remove", payload: {articleID: "article-1"}});await f.commit(remove);f.documents.set(favoritePath, {foreign: true});
  await assert.rejects(f.commit(remove), code("target_state_mismatch"));await assert.rejects(f.commit(next(remove)), code("target_state_mismatch"));assert.deepEqual(f.documents.get(favoritePath), {foreign: true});
});
test("a corrupt remove-tombstone payload hash cannot authorize a later write", async () => {
  const f = fixture();f.seed();const remove = request({kind: "favorite_remove", payload: {articleID: "article-1"}});await f.commit(remove);
  const [path, row] = f.revisionRows()[0];f.documents.set(path, {...row, payloadFingerprint: "a".repeat(64)});const before = clone([...f.documents]);
  await assert.rejects(f.commit(next(remove, {kind: "favorite_set", payload: {id: "article-1", pressAccreditation: false}})), code("invalid_revision_record"));
  await assert.rejects(f.commit(remove), code("invalid_revision_record"));assert.deepEqual([...f.documents], before);
});
for (const [name, transform] of [["unknown ledger field", (row) => ({...row, unsafe: true})], ["foreign owner", (row) => ({...row, ownerUID: "reader_b"})], ["noninteger revision", (row) => ({...row, revision: 1.5})], ["incorrect target", (row) => ({...row, target: {kind: "favorite", id: "other"}})], ["invalid tombstone kind", (row) => ({...row, exists: false})]]) test(`${name} revision row fails closed`, async () => {
  const f = fixture();f.seed();await f.commit();const [path, value] = f.revisionRows()[0];f.documents.set(path, transform(value));const before = clone([...f.documents]);
  await assert.rejects(f.commit(), code("invalid_revision_record"));assert.deepEqual([...f.documents], before);
});
for (const [name, transform] of [["unknown receipt field", (row) => ({...row, unsafe: true})], ["foreign owner", (row) => ({...row, ownerUID: "reader_b"})], ["bad fingerprint", (row) => ({...row, requestFingerprint: "a".repeat(64)})], ["false revision", (row) => ({...row, receipt: {...row.receipt, committedRevision: 8}})], ["changed echoed payload", (row) => ({...row, receipt: {...row.receipt, request: {...row.receipt.request, payload: {id: "article-1", pressAccreditation: true}}}})]]) test(`${name} receipt row fails closed`, async () => {
  const f = fixture();f.seed();await f.commit();const [path, value] = f.receiptRows()[0];f.documents.set(path, transform(value));const before = clone([...f.documents]);
  await assert.rejects(f.commit(), code("invalid_receipt_record"));assert.deepEqual([...f.documents], before);
});
test("orphaned receipt cannot reset missing revision ledger to zero", async () => {
  const f = fixture();f.seed();await f.commit();f.documents.delete(f.revisionRows()[0][0]);f.documents.delete(favoritePath);await assert.rejects(f.commit(), code("invalid_receipt_record"));assert.equal(f.documents.has(favoritePath), false);
});
test("receipt cannot assert historical acceptance beyond the latest revision", async () => {
  const f = fixture();f.seed();await f.commit();const newer = next(request());await f.commit(newer);
  const oldState = fixture();oldState.seed();await oldState.commit();f.documents.set(favoritePath, oldState.documents.get(favoritePath));f.documents.set(f.revisionRows()[0][0], oldState.revisionRows()[0][1]);
  await assert.rejects(f.commit(newer), code("invalid_receipt_record"));
});
test("actual deletion admission freezes mutation retries and cleanup leaves unresolved new ledgers", async () => {
  const f = fixture();f.seed();const first = await f.commit();const shared = clone(f.documents.get(`users/${UID}`));
  const deletionStore = deletion.createReaderAccountDeletionStore({db: f.db, now: f.now, verifyBoundary: async ({ownerUID, membershipEpoch}) => ({...f.capability(ownerUID, membershipEpoch), scope: deletion.SCOPE, unresolved: [...deletion.UNRESOLVED]})});
  const admitted = await deletion.beginReaderAccountDeletion({store: deletionStore, expectedAppID: APP, now: f.now, request: {expectedUID: UID, membershipEpoch: 1},
    verifyClient: async () => ({uid: UID, appID: APP, authTimeMs: NOW - 1000, issuedAtMs: NOW - 500, expiresAtMs: NOW + 60000})});
  const frozen = clone([...f.documents]);await assert.rejects(f.commit(), code("reader_membership_mismatch"));await assert.rejects(f.commit(next(request())), code("reader_membership_mismatch"));assert.deepEqual([...f.documents], frozen);
  const result = await deletion.runReaderAccountDeletion({store: deletionStore, requestID: admitted.requestID});assert.equal(result.status, "scopedCloudDataRemoved");assert.equal(result.accountDeletionComplete, false);
  assert.equal(f.documents.has(favoritePath), false);assert.equal(f.documents.has(preferencesPath), false);assert.deepEqual(f.documents.get(`users/${UID}`), shared);
  assert.equal(f.receiptRows()[0][1].receipt.requestID, first.requestID);assert.equal(f.revisionRows().length, 1);
  // This unchanged worker does not yet purge either new ledger. Activation requires an explicit retention/purge design.
});
test("actual deletion freeze during a discarded transaction rejects old pending writes", async () => {
  const f = fixture();f.seed();
  // Avoid nesting serialized transactions: obtain the actual worker-produced frozen row independently.
  const other = fixture();other.seed();const separate = deletion.createReaderAccountDeletionStore({db: other.db, now: other.now, verifyBoundary: async ({ownerUID, membershipEpoch}) => ({...other.capability(ownerUID, membershipEpoch), scope: deletion.SCOPE, unresolved: [...deletion.UNRESOLVED]})});
  await separate.begin({ownerUID: UID, membershipEpoch: 1, authorizationValidUntilMs: NOW + 60000});f.retry(() => f.documents.set(`${MEMBERSHIPS}/${UID}`, clone(other.documents.get(`${MEMBERSHIPS}/${UID}`))));
  await assert.rejects(f.commit(), code("reader_membership_mismatch"));assert.equal(f.documents.has(favoritePath), false);
});
test("strict JSON rejects JS-only coercions, lone surrogates, and overlarge input", () => {
  const getter = request();Object.defineProperty(getter.payload, "name", {enumerable: true, get: () => {throw Error("must not invoke getter");}});
  for (const value of [request({payload: {id: "article-1", pressAccreditation: false, name: undefined}}), request({payload: {id: "article-1", pressAccreditation: false, name: "\ud800"}}), request({payload: {id: "article-1", pressAccreditation: false, name: "a".repeat(65537)}}), getter,
    request({payload: {id: "article-1", pressAccreditation: false, stjerne: NaN}}), request({kind: "preferences_set", payload: {interestTopicIDs: Array(2), onboardingCompleted: true}})]) assert.throws(() => validateReaderMutationRequest(value), code("invalid_request"));
});
test("receipt echo binds exact Unicode bytes, order, revision and payload with no normalization", () => {
  const vector = wire.vectors.find((v) => v.name === "preferences-ordered-unicode");
  for (const modify of [(r) => {r.request.payload.interestTopicIDs.reverse();}, (r) => {r.request.payload.interestTopicIDs[0] = "cafe\u0301";}, (r) => {r.committedRevision += 1;}, (r) => {r.status = "current";}, (r) => {r.accountDeletionComplete = true;}]) {
    const receipt = clone(vector.receipt);modify(receipt);assert.throws(() => validateReaderMutationReceipt(receipt, vector.request), code("invalid_receipt"));
  }
});

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {SCOPE, MEMBERSHIPS, REQUESTS, UNRESOLVED, PAGE_SIZE, createReaderAccountDeletionStore,
  beginReaderAccountDeletion, runReaderAccountDeletion} = require("./readerAccountDeletion");
const NOW = Date.parse("2026-10-21T12:00:00Z"), UID = "reader_a", APP = "verified-ios-app";
const clone = (value) => structuredClone(value);
const rejectCode = (code) => (error) => error.code === code && error.message === code;
function fixture({boundaryEnabled = true} = {}) {
  let nowMs = NOW, tail = Promise.resolve(), failBeforeCommit = 0, loseResponseAfterCommit = 0, injectedPage = null, beforeTransaction = null, beforeQuery = null, capabilityOverride = null, retryCallback = null;
  const documents = new Map(), commits = [], reads = [];
  const activity = {storeBegins: 0, collections: 0, references: 0, transactions: 0};
  const ref = (path) => {activity.references += 1;return {path};};
  const snapshot = (path) => ({ref: ref(path), exists: documents.has(path), data: () => clone(documents.get(path))});
  const db = {
    collection: (path) => {activity.collections += 1;return {doc: (id) => ref(`${path}/${id}`), limit: (count) => ({queryPath: path, count})};},
    runTransaction: (callback) => {
      activity.transactions += 1;
      const result = tail.then(async () => {
        if (beforeTransaction) {const fn = beforeTransaction;beforeTransaction = null;await fn();}
        let wrote = false;const pending = [];
        const transaction = {
          get: async (reference) => {
            assert.equal(wrote, false, "Firestore transactions must read before writing");
            reads.push(reference.path || reference.queryPath);
            if (reference.queryPath) {
              if (beforeQuery) {const fn = beforeQuery;beforeQuery = null;await fn();}
              if (injectedPage) return {docs: injectedPage.map((path) => snapshot(path))};
              const prefix = reference.queryPath + "/";
              return {docs: [...documents.keys()].filter((path) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
                .sort().slice(0, reference.count).map(snapshot)};
            }
            return snapshot(reference.path);
          },
          set: (reference, value) => {wrote = true;pending.push({path: reference.path, value: clone(value)});},
          delete: (reference) => {wrote = true;pending.push({path: reference.path, remove: true});},
        };
        let value = await callback(transaction);
        if (retryCallback) {
          const retry = retryCallback;retryCallback = null;
          // Firestore can discard a callback's writes and replay it after contention.
          pending.length = 0;wrote = false;await retry();value = await callback(transaction);
        }
        if (failBeforeCommit) {failBeforeCommit -= 1;throw new Error("PRIVATE DATABASE TOKEN");}
        for (const operation of pending) {
          if (operation.remove) documents.delete(operation.path);else documents.set(operation.path, operation.value);
        }
        commits.push(pending);
        if (loseResponseAfterCommit) {loseResponseAfterCommit -= 1;throw new Error("PRIVATE HTTP RESPONSE");}
        return value;
      });tail = result.catch(() => {});return result;
    },
  };
  const capability = (ownerUID, membershipEpoch) => ({schemaVersion: 1, scope: SCOPE, ownerUID, membershipEpoch,
    readerSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), validUntilMs: nowMs + 60000,
    allowedPaths: [`users/${ownerUID}/favorites`, `users/${ownerUID}/preferences/reader`], unresolved: [...UNRESOLVED]});
  const actualStore = createReaderAccountDeletionStore({db, now: () => nowMs, ...(boundaryEnabled ? {verifyBoundary: async ({transaction, ownerUID, membershipEpoch}) => {
    assert.equal(typeof transaction.get, "function");return {...capability(ownerUID, membershipEpoch), ...capabilityOverride};
  }} : {})});
  const store = {...actualStore, begin: (binding) => {activity.storeBegins += 1;return actualStore.begin(binding);}};
  const seed = (uid = UID, epoch = 1, count = 0) => {
    documents.set(`${MEMBERSHIPS}/${uid}`, {schemaVersion: 1, ownerUID: uid, epoch, state: "active"});
    documents.set(`users/${uid}`, {displayName: "Shared profile", role: "editor", researchArticle: "preserve", bookmarkedArticles: ["legacy"]});
    documents.set(`users/${uid}/preferences/reader`, {interestTopicIDs: ["film"]});
    for (let index = 0; index < count; index += 1) documents.set(`users/${uid}/favorites/favorite-${String(index).padStart(3, "0")}`, {title: "Content"});
  };
  const identity = (uid = UID) => ({uid, appID: APP, authTimeMs: nowMs - 1000, issuedAtMs: nowMs - 500, expiresAtMs: nowMs + 600000});
  const begin = (request = {expectedUID: UID, membershipEpoch: 1}, auth = identity()) => beginReaderAccountDeletion({store,
    verifyClient: async () => auth, expectedAppID: APP, request, now: () => nowMs});
  return {documents, commits, reads, activity, db, store, seed, identity, begin, capability,
    now: () => nowMs, advance: (ms) => {nowMs += ms;}, failCommit: () => {failBeforeCommit += 1;}, loseResponse: () => {loseResponseAfterCommit += 1;},
    page: (paths) => {injectedPage = paths;}, override: (value) => {capabilityOverride = value;}, before: (fn) => {beforeTransaction = fn;}, beforePage: (fn) => {beforeQuery = fn;}, retry: (fn = () => {}) => {retryCallback = fn;},
    member: (uid = UID) => documents.get(`${MEMBERSHIPS}/${uid}`), job: (id) => documents.get(`${REQUESTS}/${id}`)};
}

function namespaceFixture() {
  const f = fixture();f.seed(UID, 1, 2);f.seed("reader_b", 1, 1);
  for (const path of [`users/${UID}/preferences/research`, `users/${UID}/favorites/favorite-000/comments/private`,
    "research_articles/private", "newsletter_subscribers/private", "push_installations/private"]) {
    f.documents.set(path, {preserve: true, ownerUID: UID});
  }
  return f;
}
function checkpoint(f) {
  return {documents: clone(f.documents), activity: clone(f.activity), reads: clone(f.reads), commits: clone(f.commits)};
}
function assertNoAdmissionEffects(f, before) {
  assert.deepEqual(f.activity, before.activity, "Rejected namespace must not enter store.begin or create any database reference/transaction");
  assert.deepEqual(f.reads, before.reads, "Rejected namespace must not read default-namespace documents");
  assert.deepEqual(f.commits, before.commits, "Rejected namespace must not commit or resume cleanup");
  assert.deepEqual(f.documents, before.documents, "All Research, shared, reader and other-owner documents must survive unchanged");
}

test("tenant regression: colliding tenant cannot freeze default-namespace reader membership", async () => {
  const f = namespaceFixture(), before = checkpoint(f);
  await assert.rejects(f.begin(undefined, {...f.identity(), tenantID: "colliding-tenant"}), rejectCode("identity_mismatch"));
  assertNoAdmissionEffects(f, before);
  assert.deepEqual(f.activity, {storeBegins: 0, collections: 0, references: 0, transactions: 0});
  assert.equal(f.member().state, "active");
});
for (const [name, projection] of [["absent", {}], ["null", {tenantID: null}]]) {
  test(`default-namespace identity with ${name} tenant admits the existing scoped deletion store`, async () => {
    const f = namespaceFixture(), shared = clone(f.documents.get(`users/${UID}`));
    const result = await f.begin(undefined, {...f.identity(), ...projection});
    assert.equal(result.status, "pending");assert.equal(result.accountDeletionComplete, false);
    assert.equal(f.activity.storeBegins, 1);assert.equal(f.activity.transactions, 1);
    assert.ok(f.activity.references > 0);assert.equal(f.commits.length, 1);
    assert.equal(f.member().state, "deletion_frozen");
    assert.deepEqual(f.documents.get(`users/${UID}`), shared);
    assert.equal(f.documents.has(`users/${UID}/favorites/favorite-000`), true);
    assert.equal(f.documents.get("research_articles/private").preserve, true);
  });
}
test("empty or malformed verifier tenant projection is not treated as the default namespace", async () => {
  for (const tenantID of ["", 0, false, {}, []]) {
    const f = namespaceFixture(), before = checkpoint(f);
    await assert.rejects(f.begin(undefined, {...f.identity(), tenantID}), rejectCode("identity_mismatch"));
    assertNoAdmissionEffects(f, before);
  }
});
test("a delayed verifier result from a colliding tenant is rejected before any admission effect", async () => {
  const f = namespaceFixture(), before = checkpoint(f);
  let deliver, verifierCalls = 0;
  const verified = new Promise((resolve) => {deliver = resolve;});
  const operation = beginReaderAccountDeletion({store: f.store,
    verifyClient: () => {verifierCalls += 1;return verified;}, expectedAppID: APP,
    request: {expectedUID: UID, membershipEpoch: 1}, now: f.now});
  const rejected = assert.rejects(operation, rejectCode("identity_mismatch"));
  assert.equal(verifierCalls, 1);assertNoAdmissionEffects(f, before);
  f.advance(1000);
  deliver({...f.identity(), tenantID: "colliding-tenant"});
  await rejected;
  assertNoAdmissionEffects(f, before);assert.equal(f.member().state, "active");
});
for (const status of ["pending", "scopedCloudDataRemoved"]) {
  test(`colliding-tenant public retry cannot resume or receive an existing ${status} receipt`, async () => {
    const f = namespaceFixture(), accepted = await f.begin();
    if (status === "scopedCloudDataRemoved") await runReaderAccountDeletion({store: f.store, requestID: accepted.requestID});
    assert.equal(f.job(accepted.requestID).status, status);
    const before = checkpoint(f);
    await assert.rejects(f.begin(undefined, {...f.identity(), tenantID: "colliding-tenant"}), rejectCode("identity_mismatch"));
    assertNoAdmissionEffects(f, before);
    assert.equal(f.job(accepted.requestID).status, status);
  });
}

test("absent deployment boundary fails closed before any database read or write", async () => {
  const f = fixture({boundaryEnabled: false});f.seed();await assert.rejects(f.begin(), rejectCode("reader_boundary_unavailable"));
  assert.equal(f.reads.length, 0);assert.equal(f.commits.length, 0);assert.equal(f.member().state, "active");
});
test("missing reader membership is not inferred from a shared Research profile", async () => {
  const f = fixture();f.documents.set(`users/${UID}`, {role: "editor"});await assert.rejects(f.begin(), rejectCode("reader_membership_mismatch"));
  assert.equal(f.commits.length, 0);
});
test("admission atomically freezes original membership and creates one durable request", async () => {
  const f = fixture();f.seed();const result = await f.begin();
  assert.equal(result.status, "pending");assert.equal(result.accountDeletionComplete, false);assert.equal(result.requestID.length, 64);
  assert.equal(f.member().state, "deletion_frozen");assert.equal(f.member().deletionRequestID, result.requestID);
  assert.equal(f.job(result.requestID).ownerUID, UID);assert.equal(f.job(result.requestID).membershipEpoch, 1);
  assert.deepEqual(f.commits[0].map((operation) => operation.path), [`${MEMBERSHIPS}/${UID}`, `${REQUESTS}/${result.requestID}`]);
  assert.equal(JSON.stringify(result).includes(UID), false);
});
test("parallel duplicate requests coalesce to the original owner/epoch request", async () => {
  const f = fixture();f.seed();const results = await Promise.all([f.begin(), f.begin(), f.begin()]);
  assert.equal(new Set(results.map((value) => value.requestID)).size, 1);
  assert.equal(f.commits.filter((operations) => operations.length).length, 1);
});
test("failed admission has no partial frozen membership or accepted job", async () => {
  const f = fixture();f.seed();f.failCommit();await assert.rejects(f.begin(), rejectCode("transport_unavailable"));
  assert.equal(f.member().state, "active");assert.equal([...f.documents.keys()].some((key) => key.startsWith(REQUESTS + "/")), false);
  assert.equal((await f.begin()).status, "pending");
});
test("admission response loss retries against the same already committed request", async () => {
  const f = fixture();f.seed();f.loseResponse();await assert.rejects(f.begin(), rejectCode("transport_unavailable"));
  const id = f.member().deletionRequestID, result = await f.begin();assert.equal(result.requestID, id);
  assert.equal(f.commits.filter((operations) => operations.length).length, 1);
});
for (const [name, change, code] of [
  ["missing identity", () => null, "identity_mismatch"],
  ["another Firebase owner", (auth) => ({...auth, uid: "reader_b"}), "identity_mismatch"],
  ["another app attestation", (auth) => ({...auth, appID: "different_app"}), "identity_mismatch"],
  ["stale reauthentication", (auth) => ({...auth, authTimeMs: NOW - 300001}), "recent_authentication_required"],
  ["future reauthentication", (auth) => ({...auth, authTimeMs: NOW + 30001, issuedAtMs: NOW + 30001}), "recent_authentication_required"],
  ["token issued before authentication", (auth) => ({...auth, issuedAtMs: auth.authTimeMs - 1}), "recent_authentication_required"],
  ["expired token", (auth) => ({...auth, expiresAtMs: NOW}), "recent_authentication_required"],
  ["noninteger authentication time", (auth) => ({...auth, authTimeMs: NaN}), "recent_authentication_required"],
]) test(`${name} is rejected before deletion storage`, async () => {
  const f = fixture();f.seed();await assert.rejects(f.begin(undefined, change(f.identity())), rejectCode(code));assert.equal(f.reads.length, 0);
});
test("a rejected signature/token verifier cannot be replaced by client identity", async () => {
  const f = fixture();f.seed();await assert.rejects(beginReaderAccountDeletion({store: f.store,
    verifyClient: async () => {throw new Error("PRIVATE TOKEN");}, expectedAppID: APP,
    request: {expectedUID: UID, membershipEpoch: 1}, now: f.now}), rejectCode("authentication_rejected"));assert.equal(f.reads.length, 0);
});
test("an injected store failure never exposes its underlying response", async () => {
  const f = fixture();await assert.rejects(beginReaderAccountDeletion({store: {begin: async () => {throw new Error("PRIVATE PROVIDER DETAIL");}},
    verifyClient: async () => f.identity(), expectedAppID: APP,
    request: {expectedUID: UID, membershipEpoch: 1}, now: f.now}), rejectCode("transport_unavailable"));
});
test("recent auth is checked again after waiting for the admission transaction", async () => {
  const f = fixture();f.seed();f.before(() => f.advance(300000));await assert.rejects(f.begin(), rejectCode("recent_authentication_required"));
  assert.equal(f.member().state, "active");assert.equal(f.commits.length, 0);
});
for (const [name, request] of [
  ["nested UID", {expectedUID: "reader_a/child", membershipEpoch: 1}],
  ["dot traversal UID", {expectedUID: "..", membershipEpoch: 1}],
  ["zero epoch", {expectedUID: UID, membershipEpoch: 0}],
  ["fractional epoch", {expectedUID: UID, membershipEpoch: 1.1}],
  ["client-supplied deletion path", {expectedUID: UID, membershipEpoch: 1, path: `users/${UID}`}],
  ["client-supplied auth timestamp", {expectedUID: UID, membershipEpoch: 1, authTimeMs: NOW}],
]) test(`${name} cannot choose cleanup scope`, async () => {
  const f = fixture();f.seed();await assert.rejects(f.begin(request), rejectCode("invalid_request"));assert.equal(f.reads.length, 0);
});
test("the exact allowed cloud slice is removed while Research, shared profile, newsletter and nested data survive", async () => {
  const f = fixture();f.seed(UID, 1, 3);f.seed("reader_b", 1, 2);
  const preserved = [`users/${UID}`, `users/${UID}/preferences/research`, `users/${UID}/favorites/favorite-000/comments/legacy`,
    `research_articles/private`, `newsletter_subscribers/${UID}`, `push_installations/device`, `users/reader_b/favorites/favorite-000`];
  for (const path of preserved.slice(1, -1)) f.documents.set(path, {untouched: true});
  const before = new Map(preserved.map((path) => [path, clone(f.documents.get(path))]));
  const {requestID} = await f.begin();const result = await runReaderAccountDeletion({store: f.store, requestID});
  assert.equal(result.status, "scopedCloudDataRemoved");assert.equal(result.accountDeletionComplete, false);
  assert.equal(result.removedFavoriteDocuments, 3);assert.deepEqual(result.unresolved, UNRESOLVED);
  for (const [path, value] of before) assert.deepEqual(f.documents.get(path), value, path);
  assert.equal(f.documents.has(`users/${UID}/favorites/favorite-000`), false);
  assert.equal(f.documents.has(`users/${UID}/preferences/reader`), false);
  assert.equal(f.member().state, "deletion_frozen", "cleanup must not silently enable re-enrollment or stale writes");
});
test("bounded paging pauses then resumes without deleting unrelated documents", async () => {
  const f = fixture();f.seed(UID, 1, PAGE_SIZE + 7);const {requestID} = await f.begin();
  const first = await runReaderAccountDeletion({store: f.store, requestID, maximumSteps: 1});assert.equal(first.status, "pending");
  assert.equal(f.job(requestID).removedFavoriteDocuments, PAGE_SIZE);assert.equal(f.documents.has(`users/${UID}/preferences/reader`), true);
  const last = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(last.status, "scopedCloudDataRemoved");
  assert.equal(last.removedFavoriteDocuments, PAGE_SIZE + 7);
  assert.ok(f.commits.every((commit) => commit.filter((op) => op.remove).length <= PAGE_SIZE));
});
test("a failed page transaction retains all page documents and its previous checkpoint", async () => {
  const f = fixture();f.seed(UID, 1, 3);const {requestID} = await f.begin();f.failCommit();
  const result = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(result.status, "paused");assert.equal(result.code, "transport_unavailable");
  assert.equal(f.job(requestID).removedFavoriteDocuments, 0);assert.equal(f.documents.has(`users/${UID}/favorites/favorite-000`), true);
  assert.equal(JSON.stringify(result).includes("PRIVATE"), false);
  assert.equal((await runReaderAccountDeletion({store: f.store, requestID})).removedFavoriteDocuments, 3);
});
test("crash after a cleanup commit but before its response does not recount or replay effects", async () => {
  const f = fixture();f.seed(UID, 1, PAGE_SIZE + 1);const {requestID} = await f.begin();f.loseResponse();
  const first = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(first.status, "paused");
  assert.equal(f.job(requestID).removedFavoriteDocuments, PAGE_SIZE);
  const final = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(final.status, "scopedCloudDataRemoved");
  assert.equal(final.removedFavoriteDocuments, PAGE_SIZE + 1);
});
test("concurrent workers serialize page deletion and cannot count the same documents twice", async () => {
  const f = fixture();f.seed(UID, 1, PAGE_SIZE + 1);const {requestID} = await f.begin();
  const results = await Promise.all([runReaderAccountDeletion({store: f.store, requestID}), runReaderAccountDeletion({store: f.store, requestID})]);
  assert.ok(results.every((r) => r.status === "scopedCloudDataRemoved"));assert.equal(f.job(requestID).removedFavoriteDocuments, PAGE_SIZE + 1);
});
test("a transaction callback replay commits one page and one checkpoint", async () => {
  const f = fixture();f.seed(UID, 1, 3);const {requestID} = await f.begin();f.retry();
  const result = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(result.removedFavoriteDocuments, 3);
  assert.equal(f.commits.flat().filter((operation) => operation.remove && operation.path.includes("/favorites/")).length, 3);
});
test("a newer epoch discovered on callback replay discards the old callback's pending deletes", async () => {
  const f = fixture();f.seed(UID, 1, 3);const {requestID} = await f.begin();f.retry(() => f.seed(UID, 2, 3));
  const result = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(result.code, "reader_membership_mismatch");
  assert.equal(f.documents.has(`users/${UID}/favorites/favorite-000`), true);assert.equal(f.job(requestID).removedFavoriteDocuments, 0);
  assert.equal(f.commits.flat().filter((operation) => operation.remove).length, 0);
});
test("completed slice retries are idempotent, not a full account deletion receipt", async () => {
  const f = fixture();f.seed();const {requestID} = await f.begin();await runReaderAccountDeletion({store: f.store, requestID});
  const writes = f.commits.reduce((count, commit) => count + commit.length, 0);
  const worker = await runReaderAccountDeletion({store: f.store, requestID}), client = await f.begin();
  assert.equal(worker.accountDeletionComplete, false);assert.equal(client.status, "scopedCloudDataRemoved");
  assert.equal(f.commits.reduce((count, commit) => count + commit.length, 0), writes);
});
test("old owner/epoch worker cannot delete a newly enrolled membership's data", async () => {
  const f = fixture();f.seed(UID, 1, 1);const {requestID} = await f.begin();f.seed(UID, 2, 1);
  const old = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(old.code, "reader_membership_mismatch");
  assert.equal(f.documents.has(`users/${UID}/favorites/favorite-000`), true);
  await assert.rejects(f.begin(), rejectCode("reader_membership_mismatch"));
  const current = await f.begin({expectedUID: UID, membershipEpoch: 2});assert.notEqual(current.requestID, requestID);
});
test("account B cannot retry account A's public deletion request", async () => {
  const f = fixture();f.seed();const first = await f.begin();
  await assert.rejects(f.begin(undefined, f.identity("reader_b")), rejectCode("identity_mismatch"));assert.equal(f.job(first.requestID).ownerUID, UID);
});
test("changed boundary revision pauses already admitted cleanup without touching data", async () => {
  const f = fixture();f.seed(UID, 1, 1);const {requestID} = await f.begin();f.override({writerFenceRevision: "c".repeat(64)});
  const result = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(result.code, "reader_boundary_changed");
  assert.equal(f.documents.has(`users/${UID}/favorites/favorite-000`), true);
});
test("capability expiry during a suspended query prevents the whole page mutation", async () => {
  const f = fixture();f.seed(UID, 1, 1);const {requestID} = await f.begin();f.beforePage(() => f.advance(60001));
  const result = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(result.code, "reader_boundary_unverified");
  assert.equal(f.documents.has(`users/${UID}/favorites/favorite-000`), true);assert.equal(f.job(requestID).removedFavoriteDocuments, 0);
});
for (const [name, value] of [
  ["wrong owner", {ownerUID: "reader_b"}], ["wrong epoch", {membershipEpoch: 2}], ["unknown schema", {readerSchemaVersion: 2}],
  ["missing migration", {migrationRevision: undefined}], ["expired capability", {validUntilMs: NOW}],
  ["broader paths", {allowedPaths: [`users/${UID}`]}], ["hidden unresolved scope", {unresolved: []}],
]) test(`boundary with ${name} cannot freeze or clean data`, async () => {
  const f = fixture();f.seed();f.override(value);await assert.rejects(f.begin(), rejectCode("reader_boundary_unverified"));
  assert.equal(f.member().state, "active");assert.equal(f.commits.length, 0);
});
for (const [name, paths] of [
  ["shared parent", [`users/${UID}`]], ["other owner", ["users/reader_b/favorites/x"]],
  ["nested child", [`users/${UID}/favorites/x/child/data`]], ["dot traversal", [`users/${UID}/favorites/..`]],
  ["empty document", [`users/${UID}/favorites/`]], ["control character", [`users/${UID}/favorites/x\n`]],
  ["duplicate reference", [`users/${UID}/favorites/x`, `users/${UID}/favorites/x`]],
]) test(`adapter page containing ${name} is rejected before any delete`, async () => {
  const f = fixture();f.seed(UID, 1, 1);const {requestID} = await f.begin();f.page(paths);
  const result = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(result.code, "invalid_cleanup_path");
  assert.equal(f.commits.flat().filter((operation) => operation.remove).length, 0);
});
test("oversized cleanup pages are rejected without partial effects", async () => {
  const f = fixture();f.seed();const {requestID} = await f.begin();f.page(Array.from({length: PAGE_SIZE + 1}, (_, i) => `users/${UID}/favorites/${i}`));
  const result = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(result.code, "invalid_cleanup_page");
  assert.equal(f.commits.flat().filter((operation) => operation.remove).length, 0);
});
test("worker bounds and malformed ids are rejected before storage", async () => {
  const f = fixture();for (const request of [{requestID: "../private"}, {requestID: "a".repeat(64), maximumSteps: 21}, {requestID: "a".repeat(64), maximumSteps: 0}]) {
    await assert.rejects(runReaderAccountDeletion({store: f.store, ...request}), rejectCode("invalid_worker_request"));
  }
  assert.equal(f.reads.length, 0);
});
test("corrupt persisted owner binding cannot be redirected to another account", async () => {
  const f = fixture();f.seed(UID, 1, 1);const {requestID} = await f.begin();f.job(requestID).ownerUID = "reader_b";
  const result = await runReaderAccountDeletion({store: f.store, requestID});assert.equal(result.code, "invalid_deletion_record");
  assert.equal(f.documents.has(`users/${UID}/favorites/favorite-000`), true);
});

test("native wire fixtures match actual admission, bounded worker and partial cleanup receipts", async () => {
  const wire = require("./fixtures/reader-account-deletion-wire-v1.json");
  const f = fixture();f.seed(wire.request.expectedUID, wire.request.membershipEpoch, 2);
  assert.deepEqual(await f.begin(wire.request), wire.receipts.pending);
  assert.deepEqual(await runReaderAccountDeletion({store: f.store, requestID: wire.receipts.pending.requestID}), wire.receipts.partial);
  const paused = fixture();paused.seed();const started = await paused.begin();paused.failCommit();
  assert.deepEqual(await runReaderAccountDeletion({store: paused.store, requestID: started.requestID}), wire.receipts.paused);
  for (const vector of wire.vectors) {
    const v = fixture();v.seed(vector.request.expectedUID, vector.request.membershipEpoch);
    const result = await v.begin(vector.request, v.identity(vector.request.expectedUID));
    assert.equal(result.requestID, vector.requestID);
  }
});

// Shared with the native membership projection. These exercise the real worker
// against injected atomic storage, not a duplicate implementation of its policy.
const membershipWire = require("./fixtures/reader-membership-wire-v1.json");
for (const vector of membershipWire.vectors) {
  test(`membership wire ${vector.name}: actual admission freezes exactly and survives store reconstruction`, async () => {
    const {ownerUID, epoch} = vector.binding, f = fixture();
    f.seed(ownerUID, epoch, 1);
    f.documents.set(`${MEMBERSHIPS}/${ownerUID}`, clone(vector.active));
    const request = {expectedUID: ownerUID, membershipEpoch: epoch};
    const accepted = await f.begin(request, f.identity(ownerUID));
    assert.equal(accepted.requestID, vector.requestID);
    assert.deepEqual(f.member(ownerUID), vector.frozen);
    assert.equal(f.job(vector.requestID).membershipEpoch, epoch);
    const committed = f.commits.flat().length;
    const restarted = createReaderAccountDeletionStore({db: f.db, now: f.now,
      verifyBoundary: async ({transaction, ownerUID, membershipEpoch}) => {
        assert.equal(typeof transaction.get, "function");return f.capability(ownerUID, membershipEpoch);
      }});
    const resumed = await beginReaderAccountDeletion({store: restarted, request, expectedAppID: APP,
      verifyClient: async () => f.identity(ownerUID), now: f.now});
    assert.equal(resumed.requestID, vector.requestID);
    assert.equal(f.commits.flat().length, committed, "A frozen original request is reused after restart");
    const partial = await runReaderAccountDeletion({store: restarted, requestID: vector.requestID});
    assert.equal(partial.status, "scopedCloudDataRemoved");
    assert.equal(partial.accountDeletionComplete, false);
    assert.equal(partial.removedFavoriteDocuments, 1);
    assert.deepEqual(f.member(ownerUID), vector.frozen, "Partial cleanup must not re-enrol membership");
    assert.equal(f.documents.get(`users/${ownerUID}`).role, "editor");
  });
}

for (const vector of membershipWire.invalidAdmissionRows) {
  test(`membership wire ${vector.name}: invalid or absent original row cannot admit cleanup`, async () => {
    const f = fixture();f.seed(UID, 1, 1);
    if (vector.row === null) f.documents.delete(`${MEMBERSHIPS}/${UID}`);
    else f.documents.set(`${MEMBERSHIPS}/${UID}`, clone(vector.row));
    const before = clone([...f.documents]);
    await assert.rejects(f.begin(), rejectCode("reader_membership_mismatch"));
    assert.deepEqual([...f.documents], before);
    assert.equal(f.commits.length, 0);
  });
}

test("a valid frozen projection alone is not an accepted durable deletion request", async () => {
  const f = fixture();f.seed();
  f.documents.set(`${MEMBERSHIPS}/${UID}`, clone(membershipWire.vectors[0].frozen));
  await assert.rejects(f.begin(), rejectCode("reader_membership_mismatch"));
  assert.equal(f.commits.length, 0);
  assert.equal(f.job(membershipWire.vectors[0].requestID), undefined);
});

for (const [name, replacement] of [
  ["missing", null],
  ["active again", {state: "active"}],
  ["different owner", {ownerUID: "reader_b"}],
  ["different epoch", {epoch: 2}],
  ["unknown schema", {schemaVersion: 2}],
  ["another request", {deletionRequestID: "a".repeat(64)}],
  ["missing request", {deletionRequestID: undefined}],
]) {
  test(`accepted membership ${name}: actual worker preserves data and pauses`, async () => {
    const f = fixture();f.seed(UID, 1, 1);
    const {requestID} = await f.begin();
    if (replacement === null) f.documents.delete(`${MEMBERSHIPS}/${UID}`);
    else f.documents.set(`${MEMBERSHIPS}/${UID}`, {...clone(membershipWire.vectors[0].frozen), ...replacement});
    const committed = f.commits.flat().length, before = clone([...f.documents]);
    const result = await runReaderAccountDeletion({store: f.store, requestID});
    assert.equal(result.status, "paused");
    assert.equal(result.code, "reader_membership_mismatch");
    assert.equal(result.accountDeletionComplete, false);
    assert.deepEqual([...f.documents], before);
    assert.equal(f.commits.flat().length, committed);
  });
}

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {SCOPE, MEMBERSHIPS, RECEIPTS, REVISIONS, createReaderMutationStore, commitReaderMutation,
  createReaderAuthoritativeReadStore, readReaderMembership, readReaderResource} = require("./readerMutation");
const membershipWire = require("./fixtures/reader-membership-wire-v1.json");

// These are SDK-free transactional fixtures, not Firebase/service acceptance.
const NOW = Date.parse("2026-10-23T12:00:00Z"), UID = "reader_a", APP = "verified-ios-app";
const clone = (value) => structuredClone(value);
const code = (value) => (error) => error.code === value && error.message === value;
const membershipRequest = (overrides = {}) => ({schemaVersion: 1, expectedUID: UID,
  readID: "12345678-1234-1234-1234-123456789abc", ...overrides});
const resourceRequest = (overrides = {}) => ({...membershipRequest(), membershipEpoch: 1,
  target: {kind: "favorite", id: "article-1"}, ...overrides});
const mutation = (overrides = {}) => ({schemaVersion: 1, expectedUID: UID, membershipEpoch: 1,
  mutationID: "22345678-1234-1234-1234-123456789abc", expectedRevision: 0, kind: "favorite_set",
  payload: {id: "article-1", pressAccreditation: false, name: "Café / café\u0301 🎵"}, ...overrides});
const favoritePath = `users/${UID}/favorites/article-1`, preferencesPath = `users/${UID}/preferences/reader`;

function fixture({boundaryEnabled = true} = {}) {
  let nowMs = NOW, tail = Promise.resolve(), beforeTransaction, beforeBoundary, retryCallback, afterTransaction, proofOverride;
  const documents = new Map(), snapshotOverrides = new Map(), reads = [], writes = [], attempts = [], boundaryCalls = [];
  const ref = (path) => ({path});
  const snapshot = (path) => {
    const value = clone(documents.get(path));
    const result = {exists: value !== undefined, ref: ref(path), data: () => clone(value)};
    return snapshotOverrides.has(path) ? snapshotOverrides.get(path)(result) : result;
  };
  const db = {
    collection: (path) => ({doc: (id) => ref(`${path}/${id}`)}),
    runTransaction: (callback) => {
      const run = tail.then(async () => {
        if (beforeTransaction) {const hook = beforeTransaction;beforeTransaction = undefined;await hook();}
        let staged = [], hasWrite = false;
        const transaction = {
          get: async (document) => {
            assert.equal(hasWrite, false, "Every read must precede writes within the transaction");
            reads.push(document.path);return snapshot(document.path);
          },
          set: (document, value) => {hasWrite = true;const op = {path: document.path, value: clone(value)};writes.push(op);staged.push(op);},
          delete: (document) => {hasWrite = true;const op = {path: document.path, remove: true};writes.push(op);staged.push(op);},
        };
        attempts.push("first");let result = await callback(transaction);
        if (retryCallback) {
          const hook = retryCallback;retryCallback = undefined;staged = [];hasWrite = false;await hook();
          attempts.push("retry");result = await callback(transaction);
        }
        for (const op of staged) {if (op.remove) documents.delete(op.path);else documents.set(op.path, clone(op.value));}
        if (afterTransaction) {const hook = afterTransaction;afterTransaction = undefined;await hook();}
        return result;
      });
      tail = run.catch(() => {});return run;
    },
  };
  const capability = (ownerUID, membershipEpoch) => ({schemaVersion: 1, scope: SCOPE, ownerUID, membershipEpoch,
    readerSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64),
    validUntilMs: nowMs + 60000, allowedPaths: [`users/${ownerUID}/favorites`, `users/${ownerUID}/preferences/reader`]});
  const verifyBoundary = async (input) => {
    boundaryCalls.push({scope: input.scope, ownerUID: input.ownerUID, membershipEpoch: input.membershipEpoch});
    await input.transaction.get(db.collection("test_boundary_attestations").doc("local_fixture"));
    if (beforeBoundary) {const hook = beforeBoundary;beforeBoundary = undefined;await hook();}
    return {...capability(input.ownerUID, input.membershipEpoch), ...proofOverride};
  };
  const now = () => nowMs;
  const identity = (overrides = {}) => ({uid: UID, appID: APP, issuedAtMs: nowMs - 1000, expiresAtMs: nowMs + 600000,
    appCheckIssuedAtMs: nowMs - 500, appCheckExpiresAtMs: nowMs + 60000, ...overrides});
  const store = createReaderAuthoritativeReadStore({db, now, ...(boundaryEnabled ? {verifyBoundary} : {})});
  const writer = createReaderMutationStore({db, now, verifyBoundary});
  const member = (request = membershipRequest(), auth = identity()) => readReaderMembership({store, request, expectedAppID: APP, verifyClient: async () => auth, now});
  const resource = (request = resourceRequest(), auth = identity()) => readReaderResource({store, request, expectedAppID: APP, verifyClient: async () => auth, now});
  const commit = (request = mutation()) => commitReaderMutation({store: writer, request, expectedAppID: APP, verifyClient: async () => identity({uid: request.expectedUID}), now});
  const seed = (ownerUID = UID, epoch = 1) => {
    documents.set(`${MEMBERSHIPS}/${ownerUID}`, {schemaVersion: 1, ownerUID, epoch, state: "active"});
    documents.set(`users/${ownerUID}`, {editorialRole: "editor", bookmarkedArticles: ["legacy"], newsletter: true});
    documents.set(`users/${ownerUID}/preferences/other`, {shared: "preserve"});
    documents.set(`research/articles/${ownerUID}`, {title: "preserve"});
  };
  return {db, documents, reads, writes, attempts, boundaryCalls, store, writer, identity, now, member, resource, commit, seed,
    advance: (ms) => {nowMs += ms;}, before: (fn) => {beforeTransaction = fn;}, atBoundary: (fn) => {beforeBoundary = fn;},
    retry: (fn = () => {}) => {retryCallback = fn;}, after: (fn) => {afterTransaction = fn;}, override: (value) => {proofOverride = value;},
    snapshot: (path, change) => {snapshotOverrides.set(path, change);},
    resetLogs: () => {reads.length = 0;writes.length = 0;attempts.length = 0;boundaryCalls.length = 0;},
    revisions: () => [...documents.entries()].filter(([path]) => path.startsWith(REVISIONS + "/")),
    receipts: () => [...documents.entries()].filter(([path]) => path.startsWith(RECEIPTS + "/")),
  };
}
function assertReadOnly(f, before) {
  assert.equal(f.writes.length, 0, "Authoritative reads must never stage writes");
  assert.deepEqual([...f.documents], before, "Shared/profile/research/reader state changed during a read");
}
function assertEnvelope(result, request, scope) {
  assert.equal(result.schemaVersion, 1);assert.equal(result.scope, scope);assert.deepEqual(result.request, request);
  assert.ok(Number.isSafeInteger(result.validUntilMs) && result.validUntilMs > NOW && result.validUntilMs <= NOW + 60000);
}

test("missing membership is an explicit null snapshot and never creates a member or reads shared profile", async () => {
  const f = fixture(), request = membershipRequest(), before = clone([...f.documents]);
  const result = await f.member(request);assertEnvelope(result, request, "reader-membership-read-v1");
  assert.equal(result.membership, null);assert.deepEqual(f.reads, [`${MEMBERSHIPS}/${UID}`]);assertReadOnly(f, before);
});

for (const vector of membershipWire.vectors) for (const state of ["active", "frozen"]) {
  test(`membership projection preserves ${vector.name} ${state} without adopting another account`, async () => {
    const f = fixture(), owner = vector.binding.ownerUID, request = membershipRequest({expectedUID: owner});
    f.documents.set(`${MEMBERSHIPS}/${owner}`, clone(vector[state]));const before = clone([...f.documents]);
    const result = await f.member(request, f.identity({uid: owner}));
    assertEnvelope(result, request, "reader-membership-read-v1");assert.deepEqual(result.membership, vector[state]);
    assertReadOnly(f, before);
  });
}

test("fresh resource without target or revision is revision zero only after active membership and boundary attestation", async () => {
  const f = fixture();f.seed();const request = resourceRequest(), before = clone([...f.documents]);
  const result = await f.resource(request);assertEnvelope(result, request, "reader-resource-read-v1");
  assert.deepEqual(result.membership, membershipWire.vectors[0].active);
  assert.deepEqual(result.boundary, {readerSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64)});
  assert.deepEqual(result.resource, {revision: 0, exists: false, payload: null});
  assert.deepEqual(f.boundaryCalls, [{scope: SCOPE, ownerUID: UID, membershipEpoch: 1}]);
  assert.equal(f.reads.some((path) => path === `users/${UID}` || path.startsWith(RECEIPTS + "/")), false);
  assertReadOnly(f, before);
});

test("actual mutation set, newer intent and remove read their current revision instead of a historical receipt", async () => {
  const f = fixture();f.seed();const original = mutation();const first = await f.commit(original);
  const later = mutation({mutationID: "32345678-1234-1234-1234-123456789abc", expectedRevision: 1,
    payload: {id: "article-1", pressAccreditation: true, name: "Later exact bytes / café\u0301"}});
  await f.commit(later);assert.deepEqual(await f.commit(original), first);
  f.resetLogs();let before = clone([...f.documents]);const latest = await f.resource();
  assert.deepEqual(latest.resource, {revision: 2, exists: true, payload: later.payload});assertReadOnly(f, before);
  const remove = mutation({mutationID: "42345678-1234-1234-1234-123456789abc", expectedRevision: 2,
    kind: "favorite_remove", payload: {articleID: "article-1"}});
  await f.commit(remove);assert.deepEqual(await f.commit(original), first);
  f.resetLogs();before = clone([...f.documents]);const removed = await f.resource();
  assert.deepEqual(removed.resource, {revision: 3, exists: false, payload: null});assertReadOnly(f, before);
});

test("actual preference mutations return ordered exact topics and no private marker or shared profile fields", async () => {
  const f = fixture();f.seed();await f.commit();
  const original = mutation({mutationID: "52345678-1234-1234-1234-123456789abc", kind: "preferences_set",
    payload: {interestTopicIDs: ["café", "cafe\u0301", "film 🎬"], onboardingCompleted: true}});
  await f.commit(original);f.resetLogs();const before = clone([...f.documents]);
  const result = await f.resource(resourceRequest({target: {kind: "preferences", id: "reader"}}));
  assert.deepEqual(result.resource, {revision: 1, exists: true, payload: original.payload});assertReadOnly(f, before);
  assert.equal(Object.hasOwn(result.resource.payload, "readerMutation"), false);
  assert.equal(f.reads.includes(favoritePath), false);assert.equal(f.reads.includes(`users/${UID}/preferences/other`), false);
});

for (const [name, request] of [
  ["missing read ID", {...membershipRequest(), readID: undefined}], ["uppercase read ID", membershipRequest({readID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"})],
  ["path owner", membershipRequest({expectedUID: "reader_a/path"})], ["unknown member key", {...membershipRequest(), currentAccount: UID}],
  ["schema boolean", membershipRequest({schemaVersion: true})], ["invalid schema", membershipRequest({schemaVersion: 2})],
]) test(`membership request ${name} is rejected before verifier and DB`, async () => {
  const f = fixture();let verifications = 0;
  await assert.rejects(readReaderMembership({store: f.store, request, expectedAppID: APP, now: f.now,
    verifyClient: async () => {verifications++;return f.identity();}}), code("invalid_request"));
  assert.equal(verifications, 0);assert.equal(f.attempts.length, 0);assert.equal(f.reads.length, 0);
});

for (const [name, changed] of [
  ["missing epoch", {membershipEpoch: undefined}], ["zero epoch", {membershipEpoch: 0}], ["unsafe epoch", {membershipEpoch: Number.MAX_SAFE_INTEGER + 1}],
  ["bool epoch", {membershipEpoch: true}], ["unknown field", {mutationID: "not a mutation"}], ["shared profile target", {target: {kind: "profile", id: "reader"}}],
  ["other preference", {target: {kind: "preferences", id: "other"}}], ["slash target", {target: {kind: "favorite", id: "a/b"}}],
  ["dot target", {target: {kind: "favorite", id: ".."}}], ["reserved target", {target: {kind: "favorite", id: "__reserved__"}}],
  ["unknown target field", {target: {kind: "favorite", id: "article-1", epoch: 1}}], ["lone surrogate", {target: {kind: "favorite", id: "\ud800"}}],
]) test(`resource request ${name} is rejected before verifier and DB`, async () => {
  const f = fixture();let verifications = 0;
  await assert.rejects(readReaderResource({store: f.store, request: resourceRequest(changed), expectedAppID: APP, now: f.now,
    verifyClient: async () => {verifications++;return f.identity();}}), code("invalid_request"));
  assert.equal(verifications, 0);assert.equal(f.attempts.length, 0);assert.equal(f.reads.length, 0);
});

for (const method of ["member", "resource"]) for (const [name, change, expected] of [
  ["wrong owner", {uid: "reader_b"}, "identity_mismatch"], ["wrong app", {appID: "untrusted"}, "identity_mismatch"],
  ["tenant", {tenantID: "other-namespace"}, "identity_mismatch"], ["expired ID token", {expiresAtMs: NOW}, "authentication_rejected"],
  ["expired AppCheck", {appCheckExpiresAtMs: NOW}, "authentication_rejected"], ["future ID token", {issuedAtMs: NOW + 30001}, "authentication_rejected"],
  ["future AppCheck", {appCheckIssuedAtMs: NOW + 30001}, "authentication_rejected"], ["wrong expiry type", {appCheckExpiresAtMs: "future"}, "authentication_rejected"],
]) test(`${method} rejects ${name} before data access`, async () => {
  const f = fixture();f.seed();const request = method === "member" ? membershipRequest() : resourceRequest();
  await assert.rejects(f[method](request, f.identity(change)), code(expected));assert.equal(f.reads.length, 0);assert.equal(f.attempts.length, 0);
});

for (const [method, call, original] of [["member", readReaderMembership, membershipRequest], ["resource", readReaderResource, resourceRequest]]) {
  test(`${method} copies original input before verifier await`, async () => {
    const f = fixture();f.seed();const input = original(), expected = clone(input);let release;
    const gate = new Promise((resolve) => {release = resolve;});
    const pending = call({store: f.store, request: input, expectedAppID: APP, now: f.now,
      verifyClient: async () => {await gate;return f.identity();}});
    input.expectedUID = "reader_b";input.readID = "92345678-1234-1234-1234-123456789abc";
    if (input.target) {input.membershipEpoch = 2;input.target.id = "another";}
    release();const result = await pending;assert.deepEqual(result.request, expected);
    assert.equal(f.reads.some((path) => path.includes("reader_b") || path.endsWith("/another")), false);assert.equal(f.writes.length, 0);
  });
  test(`${method} direct store snapshots binding and authorization before the transaction wait`, async () => {
    const f = fixture();f.seed();const input = {request: original(), authorizationValidUntilMs: NOW + 60000};
    const expected = clone(input.request);
    f.before(() => {input.request.expectedUID = "reader_b";input.authorizationValidUntilMs = 0;if (input.request.target) input.request.target.id = "another";});
    const result = await f.store[method === "member" ? "readMembership" : "readResource"](input);
    assert.deepEqual(result.request, expected);assert.equal(f.reads.some((path) => path.includes("reader_b") || path.endsWith("/another")), false);
    assert.equal(f.writes.length, 0);
  });
}

for (const [name, row] of [
  ["foreign owner", {schemaVersion: 1, ownerUID: "reader_b", epoch: 1, state: "active"}],
  ["unknown fields", {...membershipWire.vectors[0].active, editorialRole: "editor"}],
  ["invalid epoch", {...membershipWire.vectors[0].active, epoch: 0}],
  ["active with frozen ID", {...membershipWire.vectors[0].active, deletionRequestID: membershipWire.vectors[0].requestID}],
  ["frozen without ID", {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "deletion_frozen"}],
  ["frozen with wrong ID", {...membershipWire.vectors[0].frozen, deletionRequestID: "a".repeat(64)}],
]) test(`malformed membership ${name} cannot become an authoritative result`, async () => {
  const f = fixture();f.documents.set(`${MEMBERSHIPS}/${UID}`, clone(row));const before = clone([...f.documents]);
  await assert.rejects(f.member(), code("invalid_membership_record"));assertReadOnly(f, before);
});

for (const [name, row] of [["missing", undefined], ["frozen", membershipWire.vectors[0].frozen], ["newer epoch", membershipWire.vectors[2].active]]) {
  test(`resource read rejects ${name} membership without claiming a revision-zero target`, async () => {
    const f = fixture();if (row) f.documents.set(`${MEMBERSHIPS}/${UID}`, clone(row));const before = clone([...f.documents]);
    await assert.rejects(f.resource(), code("reader_membership_mismatch"));assertReadOnly(f, before);
  });
}

for (const [name, target, path, row] of [
  ["favorite", {kind: "favorite", id: "article-1"}, favoritePath, {id: "article-1", pressAccreditation: false}],
  ["preferences", {kind: "preferences", id: "reader"}, preferencesPath, {interestTopicIDs: [], onboardingCompleted: false}],
]) test(`legacy ${name} without revision ledger requires migration instead of revision-zero adoption`, async () => {
  const f = fixture();f.seed();f.documents.set(path, row);const before = clone([...f.documents]);
  await assert.rejects(f.resource(resourceRequest({target})), code("migration_required"));assertReadOnly(f, before);
});

for (const [name, change] of [
  ["untracked payload", (row) => ({...row, name: "unexpected"})],
  ["private extra field", (row) => ({...row, editorialRole: "owner"})],
  ["wrong owner marker", (row) => ({...row, readerMutation: {...row.readerMutation, ownerUID: "reader_b"}})],
  ["wrong epoch marker", (row) => ({...row, readerMutation: {...row.readerMutation, membershipEpoch: 2}})],
  ["wrong revision marker", (row) => ({...row, readerMutation: {...row.readerMutation, revision: 99}})],
  ["missing target", () => undefined],
]) test(`resource target ${name} fails integrity check without mutating data`, async () => {
  const f = fixture();f.seed();await f.commit();const replacement = change(f.documents.get(favoritePath));
  if (replacement === undefined) f.documents.delete(favoritePath);else f.documents.set(favoritePath, replacement);
  f.resetLogs();const before = clone([...f.documents]);await assert.rejects(f.resource(), code("target_state_mismatch"));assertReadOnly(f, before);
});

for (const [name, change] of [
  ["unknown field", (row) => ({...row, futureAuthority: true})], ["wrong owner", (row) => ({...row, ownerUID: "reader_b"})],
  ["wrong epoch", (row) => ({...row, membershipEpoch: 2})], ["wrong target", (row) => ({...row, target: {kind: "favorite", id: "other"}})],
  ["fractional revision", (row) => ({...row, revision: 1.5})], ["invalid exists", (row) => ({...row, exists: false})],
]) test(`resource ledger ${name} is refused`, async () => {
  const f = fixture();f.seed();await f.commit();const [path, row] = f.revisions()[0];f.documents.set(path, change(row));
  f.resetLogs();const before = clone([...f.documents]);await assert.rejects(f.resource(), code("invalid_revision_record"));assertReadOnly(f, before);
});

test("remove tombstone must retain its payload hash and cannot hide a foreign target", async () => {
  const f = fixture();f.seed();await f.commit(mutation({kind: "favorite_remove", payload: {articleID: "article-1"}}));
  const [path, row] = f.revisions()[0];f.documents.set(path, {...row, payloadFingerprint: "c".repeat(64)});
  f.resetLogs();let before = clone([...f.documents]);await assert.rejects(f.resource(), code("invalid_revision_record"));assertReadOnly(f, before);
  f.documents.set(path, row);f.documents.set(favoritePath, {foreign: true});f.resetLogs();before = clone([...f.documents]);
  await assert.rejects(f.resource(), code("target_state_mismatch"));assertReadOnly(f, before);
});

test("resource boundary is required and uses the existing mutation scope instead of a fabricated read authority", async () => {
  const f = fixture({boundaryEnabled: false});f.seed();const before = clone([...f.documents]);
  await assert.rejects(f.resource(), code("reader_boundary_unavailable"));assert.equal(f.reads.length, 0);assertReadOnly(f, before);
});

for (const [name, override] of [
  ["foreign scope", {scope: "reader-resource-read-v1"}], ["foreign owner", {ownerUID: "reader_b"}], ["foreign epoch", {membershipEpoch: 2}],
  ["expired proof", {validUntilMs: NOW}], ["invalid fence", {writerFenceRevision: null}],
  ["unbounded paths", {allowedPaths: [`users/${UID}`]}], ["unknown field", {trustCurrentUser: true}],
]) test(`resource boundary ${name} is rejected without writes`, async () => {
  const f = fixture();f.seed();f.override(override);const before = clone([...f.documents]);
  await assert.rejects(f.resource(), code("reader_boundary_unverified"));assertReadOnly(f, before);
});

test("different current boundary cannot reinterpret an existing revision ledger", async () => {
  const f = fixture();f.seed();await f.commit();f.resetLogs();f.override({migrationRevision: "c".repeat(64)});const before = clone([...f.documents]);
  await assert.rejects(f.resource(), code("reader_boundary_changed"));assertReadOnly(f, before);
});

test("boundary replacement during transaction retry rejects even a missing resource", async () => {
  const f = fixture();f.seed();f.retry(() => f.override({writerFenceRevision: "c".repeat(64)}));const before = clone([...f.documents]);
  await assert.rejects(f.resource(), code("reader_boundary_changed"));assert.equal(f.attempts.length, 2);assertReadOnly(f, before);
});

test("transaction retry revalidates epoch and frozen state instead of returning the discarded earlier resource", async () => {
  for (const replacement of [membershipWire.vectors[2].active, membershipWire.vectors[0].frozen]) {
    const f = fixture();f.seed();f.retry(() => f.documents.set(`${MEMBERSHIPS}/${UID}`, clone(replacement)));
    await assert.rejects(f.resource(), code("reader_membership_mismatch"));assert.equal(f.attempts.length, 2);assert.equal(f.writes.length, 0);
    assert.deepEqual(f.documents.get(`${MEMBERSHIPS}/${UID}`), replacement);
  }
});

test("membership transaction retry returns the final original-owner snapshot with the same read ID", async () => {
  const f = fixture();f.seed();f.retry(() => f.documents.set(`${MEMBERSHIPS}/${UID}`, clone(membershipWire.vectors[0].frozen)));
  const result = await f.member();assert.deepEqual(result.request, membershipRequest());
  assert.deepEqual(result.membership, membershipWire.vectors[0].frozen);assert.equal(f.attempts.length, 2);assert.equal(f.writes.length, 0);
});

for (const method of ["member", "resource"]) for (const [name, at] of [["queued transaction", "before"], ["transaction retry", "retry"], ["delayed transaction completion", "after"]]) {
  test(`${method} rejects auth/AppCheck expiry at ${name}`, async () => {
    const f = fixture();f.seed();f[at](() => f.advance(60001));const before = clone([...f.documents]);
    await assert.rejects(f[method](), code("authentication_expired"));assertReadOnly(f, before);
  });
}

test("resource authority cannot outlive the boundary even when ID token and AppCheck remain valid", async () => {
  const f = fixture();f.seed();f.override({validUntilMs: NOW + 100});f.after(() => f.advance(101));const before = clone([...f.documents]);
  await assert.rejects(f.resource(), code("reader_boundary_unverified"));assertReadOnly(f, before);
});

for (const [name, publicRead, request] of [["membership", readReaderMembership, membershipRequest], ["resource", readReaderResource, resourceRequest]]) {
  test(`${name} verifier failure and missing verifier are sanitized before database access`, async () => {
    const f = fixture();
    await assert.rejects(publicRead({store: f.store, request: request(), expectedAppID: APP, now: f.now}), code("authentication_unavailable"));
    await assert.rejects(publicRead({store: f.store, request: request(), expectedAppID: APP, now: f.now,
      verifyClient: async () => {throw Error("PRIVATE TOKEN / PROVIDER DETAIL");}}), code("authentication_rejected"));
    assert.equal(f.reads.length, 0);assert.equal(f.writes.length, 0);
  });
}

test("membership lookup needs no migration proof and still performs exactly one authoritative transaction read", async () => {
  const f = fixture({boundaryEnabled: false});f.seed();const before = clone([...f.documents]);
  const result = await f.member();assert.deepEqual(result.membership, membershipWire.vectors[0].active);
  assert.deepEqual(f.reads, [`${MEMBERSHIPS}/${UID}`]);assert.equal(f.boundaryCalls.length, 0);assertReadOnly(f, before);
});

for (const [name, transform, expected] of [
  ["cached", (snap) => ({...snap, metadata: {isFromCache: true}}), "authoritative_read_required"],
  ["pending local writes", (snap) => ({...snap, metadata: {hasPendingWrites: true}}), "authoritative_read_required"],
  ["untyped existence", (snap) => ({...snap, exists: 1}), "authoritative_read_required"],
  ["missing data API", (snap) => ({...snap, data: undefined}), "authoritative_read_required"],
  ["exists false with data", (snap) => ({...snap, exists: false}), "invalid_snapshot"],
  ["exists true without data", (snap) => ({...snap, data: () => undefined}), "invalid_snapshot"],
]) for (const location of ["membership", "favorite", "revision"]) test(`${location} snapshot ${name} cannot provide read authority`, async () => {
  const f = fixture();f.seed();if (location !== "membership") await f.commit();
  const path = location === "membership" ? `${MEMBERSHIPS}/${UID}` : location === "favorite" ? favoritePath : f.revisions()[0][0];
  f.snapshot(path, transform);f.resetLogs();const before = clone([...f.documents]);
  await assert.rejects(location === "membership" ? f.member() : f.resource(), code(expected));assertReadOnly(f, before);
});

test("resource zero revision rejects an absent snapshot with a fabricated data object", async () => {
  const f = fixture();f.seed();f.snapshot(favoritePath, (snap) => ({...snap, data: () => ({id: "fabricated"})}));
  const before = clone([...f.documents]);await assert.rejects(f.resource(), code("invalid_snapshot"));assertReadOnly(f, before);
});

test("resource read expiry during the awaited boundary remains a failure before a response is delivered", async () => {
  const f = fixture();f.seed();f.atBoundary(() => f.advance(60001));const before = clone([...f.documents]);
  await assert.rejects(f.resource(), code("authentication_expired"));assertReadOnly(f, before);
});

for (const [method, fn, makeRequest, adapterMethod] of [
  ["membership", readReaderMembership, membershipRequest, "readMembership"],
  ["resource", readReaderResource, resourceRequest, "readResource"],
]) {
  for (const [name, change] of [
    ["foreign read ID", (value) => {value.request.readID = "92345678-1234-1234-1234-123456789abc";}],
    ["foreign owner", (value) => {value.request.expectedUID = "reader_b";}],
    ["foreign scope", (value) => {value.scope = "reader-mutation-v1";}],
    ["unknown claim", (value) => {value.accountDeletionComplete = true;}],
    ["expiry beyond authorization", (value) => {value.validUntilMs = NOW + 60001;}],
  ]) test(`${method} public boundary rejects storage response with ${name}`, async () => {
    const f = fixture();f.seed();const request = makeRequest();
    const good = await f.store[adapterMethod]({request, authorizationValidUntilMs: NOW + 60000});
    const altered = clone(good);change(altered);f.resetLogs();const before = clone([...f.documents]);
    await assert.rejects(fn({store: {[adapterMethod]: async () => altered}, request, expectedAppID: APP,
      verifyClient: async () => f.identity(), now: f.now}), code("invalid_read_response"));assertReadOnly(f, before);
  });
  test(`${method} public boundary rechecks auth expiry after a custom store returns`, async () => {
    const f = fixture();f.seed();const request = makeRequest();
    const good = await f.store[adapterMethod]({request, authorizationValidUntilMs: NOW + 60000});
    f.resetLogs();const before = clone([...f.documents]);
    await assert.rejects(fn({store: {[adapterMethod]: async () => {f.advance(60001);return good;}}, request,
      expectedAppID: APP, verifyClient: async () => f.identity(), now: f.now}), code("authentication_expired"));assertReadOnly(f, before);
  });
  test(`${method} public boundary rejects expired response while auth remains valid`, async () => {
    const f = fixture();f.seed();const request = makeRequest();
    const good = await f.store[adapterMethod]({request, authorizationValidUntilMs: NOW + 60000});
    f.resetLogs();const before = clone([...f.documents]);
    await assert.rejects(fn({store: {[adapterMethod]: async () => ({...good, validUntilMs: NOW})}, request,
      expectedAppID: APP, verifyClient: async () => f.identity(), now: f.now}), code("reader_boundary_unverified"));assertReadOnly(f, before);
  });
  test(`${method} raw database failure is sanitized and never mistaken for missing data`, async () => {
    const f = fixture();f.seed();f.before(() => {throw Error("PRIVATE DATABASE DOCUMENT DETAIL");});const before = clone([...f.documents]);
    await assert.rejects(method === "membership" ? f.member() : f.resource(), code("transport_unavailable"));assertReadOnly(f, before);
  });
}

for (const [name, change] of [
  ["frozen membership", (value) => {value.membership = clone(membershipWire.vectors[0].frozen);}],
  ["different epoch", (value) => {value.membership.epoch = 2;}],
  ["exists without positive revision", (value) => {value.resource = {revision: 0, exists: true, payload: mutation().payload};}],
  ["missing with payload", (value) => {value.resource.payload = mutation().payload;}],
  ["unbounded revision", (value) => {value.resource.revision = Number.MAX_SAFE_INTEGER + 1;}],
  ["unknown boundary field", (value) => {value.boundary.allowedAllUsers = true;}],
]) test(`resource public response rejects ${name} from injected storage`, async () => {
  const f = fixture();f.seed();const request = resourceRequest();const good = await f.resource(request);
  const altered = clone(good);change(altered);f.resetLogs();const before = clone([...f.documents]);
  await assert.rejects(readReaderResource({store: {readResource: async () => altered}, request, expectedAppID: APP,
    verifyClient: async () => f.identity(), now: f.now}), code("invalid_read_response"));assertReadOnly(f, before);
});

test("membership read rejects getter-backed request without evaluating the getter or verifier", async () => {
  const f = fixture();const request = membershipRequest();let getterCalls = 0, verifierCalls = 0;
  Object.defineProperty(request, "expectedUID", {enumerable: true, get: () => {getterCalls++;return UID;}});
  await assert.rejects(readReaderMembership({store: f.store, request, expectedAppID: APP, now: f.now,
    verifyClient: async () => {verifierCalls++;return f.identity();}}), code("invalid_request"));
  assert.equal(getterCalls, 0);assert.equal(verifierCalls, 0);assert.equal(f.attempts.length, 0);
});

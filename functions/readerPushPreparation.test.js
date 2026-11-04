const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const fs = require("node:fs"), vm = require("node:vm");
const endpointModule = require("./readerDeletionEndpoint");
const {createReaderDeletionEndpoint} = endpointModule;
const deletion = require("./readerAccountDeletion");
const {SCOPE, LEDGER_SCOPE, LEDGER_UNRESOLVED, MEMBERSHIPS, REQUESTS, UNRESOLVED,
  createReaderAccountDeletionStore, beginReaderAccountDeletion, runReaderAccountDeletion} = deletion;
const {SCOPE: MUTATION_SCOPE, RECEIPTS, REVISIONS, createReaderMutationStore} = require("./readerMutation");
const {INSTALLATIONS, CHALLENGES, TOKENS, createRecipientRegistry} = require("./recipientRegistry");
const UID = "push_reader_a", APP = "1:123456789:ios:abcdef123456", PROJECT = "local-apropos-test";
const iid = "44444444-4444-4444-8444-000000000001", key = "private-installation-key-" + "k".repeat(32);
const token = "private-registration-token-" + "t".repeat(50), clone = structuredClone;
const hash = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
const parentID = () => hash([SCOPE, UID, 1]);
const ledgerID = () => hash([LEDGER_SCOPE, parentID(), UID, 1]);
const registration = (extra = {}) => ({installationId: iid, key, token, clientRevision: 1, permission: true,
  preferences: {articles: "categories", categoryIds: ["film"], podcasts: true}, ...extra});
const registryClient = {appId: APP, ownerUID: UID};

// Local buffered transactional double only: no SDK, server, network or credentials.
function coreFixture() {
  const documents = new Map(), transactions = [], hooks = {afterRead: null, beforeCommit: null, beforeTransaction: null,
    retryCommits: 0, failCommit: false, loseReply: false, parentProof: null, ledgerProof: null, pushProof: null, identity: null, afterCommit: null};
  const overrides = {parent: {}, ledger: {}, push: {}};
  let clock = Date.parse("2026-10-27T18:00:00Z"), tail = Promise.resolve(), nonce = 0;
  const collection = (queryPath, filters = [], count) => ({queryPath, filters, count,
    doc: (id) => ({path: `${queryPath}/${id}`}), where: (field, op, value) => collection(queryPath, [...filters, [field, op, value]], count),
    limit: (size) => collection(queryPath, filters, size)});
  const select = (query) => [...documents].filter(([path, value]) => path.startsWith(query.queryPath + "/") &&
      !path.slice(query.queryPath.length + 1).includes("/") && query.filters.every(([field, op, target]) => {
        assert.equal(op, "=="); return value?.[field] === target;
      })).sort(([a], [b]) => a.localeCompare(b)).slice(0, query.count).map(([path, value]) => [path, clone(value)]);
  const db = {projectId: PROJECT, databaseId: "(default)", collection, runTransaction: (work) => {
    const result = tail.then(async () => {
      if (hooks.beforeTransaction) await hooks.beforeTransaction();
      for (let attempt = 0; attempt < 5; attempt += 1) {
        const writes = [], reads = new Map(), queries = []; let written = false;
        const trace = {reads: [], sets: [], deletes: [], committed: false}; transactions.push(trace);
        const value = await work({get: async (ref) => {
          assert.equal(written, false, "All transaction reads must precede writes"); trace.reads.push(ref.path || ref.queryPath);
          if (ref.path) {
            const row = clone(documents.get(ref.path)); reads.set(ref.path, row);
            if (hooks.afterRead) await hooks.afterRead(ref.path, attempt);
            return {ref, exists: row !== undefined, data: () => clone(row)};
          }
          const rows = select(ref); queries.push([ref, rows]); if (hooks.afterRead) await hooks.afterRead(ref.queryPath, attempt);
          return {docs: rows.map(([path, row]) => ({ref: {path}, exists: true, data: () => clone(row)}))};
        }, set: (ref, row) => {written = true; trace.sets.push(ref.path); writes.push({path: ref.path, row: clone(row)});},
        delete: (ref) => {written = true; trace.deletes.push(ref.path); writes.push({path: ref.path, remove: true});}});
        if (hooks.beforeCommit) await hooks.beforeCommit(trace, attempt);
        if (hooks.retryCommits > 0) {hooks.retryCommits -= 1; continue;}
        if ([...reads].some(([path, row]) => !isDeepStrictEqual(documents.get(path), row)) || queries.some(([query, rows]) => !isDeepStrictEqual(select(query), rows))) continue;
        if (hooks.failCommit) {hooks.failCommit = false; throw new Error("injected atomic failure");}
        for (const write of writes) {if (write.remove) documents.delete(write.path); else documents.set(write.path, write.row);}
        trace.committed = true;
        if (hooks.afterCommit) await hooks.afterCommit(trace);
        if (hooks.loseReply) {hooks.loseReply = false; throw new Error("injected committed response loss");}
        return value;
      }
      throw new Error("Local transaction retry budget exhausted");
    }); tail = result.catch(() => {}); return result;
  }};
  const proof = ({ownerUID, membershipEpoch}, scope = SCOPE) => ({schemaVersion: 1, scope, ownerUID, membershipEpoch,
    readerSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), validUntilMs: clock + 60000,
    allowedPaths: [`users/${ownerUID}/favorites`, `users/${ownerUID}/preferences/reader`], ...(scope === SCOPE ? {unresolved: [...UNRESOLVED]} : {})});
  let store;
  const reopen = ({push = true, policy = true} = {}) => {
    store = createReaderAccountDeletionStore({db, now: () => clock,
      ...(policy ? {pushPolicy: {projectID: PROJECT, appID: APP}} : {}),
      verifyBoundary: async (binding) => {
        const value = {...proof(binding), ...overrides.parent}; if (hooks.parentProof) await hooks.parentProof(binding); return value;
      }, verifyLedgerBoundary: async (binding) => {
        const value = {schemaVersion: 1, scope: LEDGER_SCOPE, ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch,
          parentRequestID: binding.parentRequestID, mutationSchemaVersion: 1, writerFenceRevision: "a".repeat(64),
          migrationRevision: "b".repeat(64), validUntilMs: clock + 60000, collections: [RECEIPTS, REVISIONS],
          unresolved: [...LEDGER_UNRESOLVED], ...overrides.ledger};
        if (hooks.ledgerProof) await hooks.ledgerProof(binding); return value;
      }, ...(push ? {verifyPushBoundary: async (binding) => {
        assert.equal(typeof binding.transaction.get, "function");
        const {transaction, ...echo} = binding;
        const value = {...echo, schemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64),
          validUntilMs: clock + 60000, unresolved: [...deletion.PUSH_UNRESOLVED], ...overrides.push};
        if (hooks.pushProof) await hooks.pushProof(binding); return value;
      }} : {})});
    return store;
  };
  reopen();
  const registry = createRecipientRegistry({db, now: () => clock, nonce: () => "nonce-" + String(++nonce).padStart(50, "0")});
  const mutation = createReaderMutationStore({db, now: () => clock, verifyBoundary: async (binding) => proof(binding, MUTATION_SCOPE)});
  const identity = () => ({uid: UID, appID: APP, projectID: PROJECT, tenantID: null,
    authTimeMs: clock - 1000, issuedAtMs: clock - 500, expiresAtMs: clock + 600000,
    appCheckIssuedAtMs: clock - 500, appCheckExpiresAtMs: clock + 600000});
  const seed = async ({active = true} = {}) => {
    documents.set(`${MEMBERSHIPS}/${UID}`, {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "active"});
    documents.set(`users/${UID}`, {role: "editor", bookmarkedArticles: ["legacy"], researchDraft: "preserve"});
    documents.set(`users/${UID}/preferences/research`, {private: "preserve"});
    await mutation.commit({authorizationValidUntilMs: clock + 60000, request: {schemaVersion: 1, expectedUID: UID, membershipEpoch: 1,
      mutationID: "55555555-5555-4555-8555-000000000001", expectedRevision: 0, kind: "favorite_set",
      payload: {id: "local-article", pressAccreditation: false, name: "Local article"}}});
    const pending = await registry.begin(registration(), registryClient);
    if (active) await registry.confirm({installationId: iid, key, challengeId: pending.challengeId, nonce: pending.challengeDelivery.data.nonce}, registryClient);
    return pending;
  };
  const completeParents = async () => {
    const accepted = await beginReaderAccountDeletion({store, verifyClient: async () => identity(), expectedAppID: APP,
      request: {expectedUID: UID, membershipEpoch: 1}, now: () => clock});
    const parent = await runReaderAccountDeletion({store, requestID: accepted.requestID});
    assert.equal(parent.status, "scopedCloudDataRemoved");
    const ledgerAccepted = await beginReaderAccountDeletion({store, verifyClient: async () => identity(), expectedAppID: APP,
      request: {schemaVersion: 1, scope: LEDGER_SCOPE, expectedUID: UID, membershipEpoch: 1, parentRequestID: parent.requestID}, now: () => clock});
    const ledger = await runReaderAccountDeletion({store, scope: LEDGER_SCOPE, requestID: ledgerAccepted.requestID});
    assert.equal(ledger.status, "ledgerDataRemoved"); return {parent, ledger};
  };
  const pushRequest = async () => {
    const row = documents.get(`${INSTALLATIONS}/${iid}`), owner = row.active || documents.get(`${CHALLENGES}/${row.pending.challengeId}`);
    const retirement = {installationId: iid, key, requestId: "original-push-cleanup-request-001",
      expected: {ownerEpoch: owner.ownerEpoch, revision: owner.revision, clientRevision: row.clientRevision}};
    const snapshot = await registry.prepareRetirement(retirement, registryClient);
    return {schemaVersion: 1, scope: deletion.PUSH_SCOPE, expectedUID: UID, membershipEpoch: 1,
      parentRequestID: parentID(), ledgerRequestID: ledgerID(), installation: {...retirement, snapshot}};
  };
  const push = (request, options = {}) => deletion.beginReaderPushRetirement({store,
    verifyClient: async () => {const value = identity(); if (hooks.identity) await hooks.identity(value); return value;},
    expectedProjectID: PROJECT, expectedAppID: APP, request, now: () => clock, ...options});
  return {documents, transactions, hooks, overrides, db, get store() {return store;}, registry, identity, seed, completeParents,
    reopen, pushRequest, push, now: () => clock,
    advance: (ms) => {clock += ms;}, row: () => documents.get(`${INSTALLATIONS}/${iid}`)};
}


function fixture() {
  const f = coreFixture(), hooks = {}, tokens = new Map(), consumed = new Set(), authInputs = [], appInputs = [];
  const calls = {services: 0, auth: 0, app: 0, user: 0, boundary: 0, ledger: 0, push: 0}; let sequence = 0;
  const options = {config: {enabled: true, projectID: PROJECT, appID: APP, runtimeProjectID: PROJECT}, now: f.now,
    verifyBoundary: async (binding) => {
      calls.boundary += 1;
      const value = {schemaVersion: 1, scope: SCOPE, ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch,
        readerSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), validUntilMs: f.now() + 60000,
        allowedPaths: [`users/${binding.ownerUID}/favorites`, `users/${binding.ownerUID}/preferences/reader`], unresolved: [...UNRESOLVED]};
      await hooks.boundary?.(value, binding); return value;
    }, verifyLedgerBoundary: async (binding) => {
      calls.ledger += 1;
      const value = {schemaVersion: 1, scope: LEDGER_SCOPE, ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch,
        parentRequestID: binding.parentRequestID, mutationSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64),
        validUntilMs: f.now() + 60000, collections: [RECEIPTS, REVISIONS], unresolved: [...LEDGER_UNRESOLVED]};
      await hooks.ledger?.(value, binding); return value;
    }, verifyPushBoundary: async (binding) => {
      calls.push += 1; const {transaction, ...echo} = binding; assert.equal(typeof transaction.get, "function");
      const value = {...echo, schemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64),
        validUntilMs: f.now() + 60000, unresolved: [...deletion.PUSH_UNRESOLVED]};
      await hooks.push?.(value, binding); return value;
    }, createServices: async () => {
      calls.services += 1; await hooks.services?.();
      return {db: f.db, appCheck: {verifyToken: async (token, settings) => {
        calls.app += 1; appInputs.push({token, settings: clone(settings)}); assert.deepEqual(settings, {consume: true});
        const minted = tokens.get(token); assert.ok(minted); const result = clone(minted.app);
        result.alreadyConsumed = consumed.has(token); consumed.add(token); await hooks.app?.(result); return result;
      }}, auth: {verifyIdToken: async (token, checkRevoked) => {
        calls.auth += 1; authInputs.push({token, checkRevoked}); assert.equal(checkRevoked, true);
        const result = clone(tokens.get(token)?.claims); assert.ok(result); await hooks.auth?.(result); return result;
      }, getUser: async (uid) => {calls.user += 1; const result = {uid, disabled: false}; await hooks.user?.(result); return result;}}};
    }};
  const http = (body, changes = {}) => {
    const number = ++sequence, auth = `local.auth.${number}`, app = `local.app.${number}`, seconds = Math.floor(f.now() / 1000);
    tokens.set(auth, {claims: {uid: UID, sub: UID, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
      auth_time: seconds - 1, iat: seconds, exp: seconds + 3600, firebase: {sign_in_provider: "apple.com"}, ...changes.claims}});
    tokens.set(app, {app: {alreadyConsumed: false, appId: APP, token: {sub: APP, app_id: APP,
      iss: "https://firebaseappcheck.googleapis.com/123456789", aud: [`projects/${PROJECT}`, "projects/123456789"],
      iat: seconds - 1, exp: seconds + 600, ...changes.appClaims}}});
    return {method: "POST", query: {}, headers: {"content-type": "application/json; charset=utf-8", authorization: `Bearer ${auth}`,
      "x-firebase-appcheck": app}, rawBody: Buffer.from(JSON.stringify(body))};
  };
  const call = (request, changes = {}, override = {}) => createReaderDeletionEndpoint({...options, ...override})(http(request, changes));
  return {...f, httpHooks: hooks, options, calls, http, call, consumed, authInputs, appInputs, tokens};
}
const queuedWrites = (f, from) => f.transactions.slice(from).flatMap((tx) => [...tx.sets, ...tx.deletes]);
const committedWrites = (f, from) => f.transactions.slice(from).filter((tx) => tx.committed).flatMap((tx) => [...tx.sets, ...tx.deletes]);
const deferred = () => {let resolve; const promise = new Promise((finish) => {resolve = finish;}); return {promise, resolve};};
const PREPARE_SCOPE = "reader-push-installation-prepare-v1";
async function ready(options) {
  const f = fixture(); await f.seed(options); await f.completeParents(); const commit = await f.pushRequest();
  const {snapshot, ...installation} = commit.installation;
  const request = {...commit, scope: PREPARE_SCOPE, installation};
  return {f, request, originalSnapshot: snapshot};
}
function safeUnavailable(result, status = 503) {
  assert.equal(result.status, status); assert.equal(result.headers["cache-control"], "no-store");
  assert.equal(result.headers.pragma, "no-cache"); assert.equal(result.body.status, "unavailable");
  assert.deepEqual(Object.keys(result.body).sort(), ["error", "status"]);
  assert.equal(JSON.stringify(result).includes("PRIVATE"), false);
}


const safeError = (error) => typeof error?.code === "string" && error.message === error.code;
function prepareDirect(f, request, options = {}) {
  return deletion.prepareReaderPushRetirement({store: f.store, verifyClient: async () => f.identity(),
    expectedProjectID: PROJECT, expectedAppID: APP, request, now: f.now, ...options});
}
function assertPrepared(body, request, snapshot) {
  assert.equal(body.schemaVersion, 1); assert.equal(body.scope, PREPARE_SCOPE); assert.equal(body.status, "prepared");
  assert.equal(body.expectedUID, request.expectedUID); assert.equal(body.membershipEpoch, request.membershipEpoch);
  assert.equal(body.parentRequestID, request.parentRequestID); assert.equal(body.ledgerRequestID, request.ledgerRequestID);
  assert.equal(body.installationId, request.installation.installationId); assert.equal(body.preparedOnly, true);
  for (const flag of ["retirementComplete", "accountDeletionComplete", "historicalMaterialComplete", "deliveriesRecalled"]) assert.equal(body[flag], false);
  assert.deepEqual(body.unresolved, deletion.PUSH_UNRESOLVED); assert.deepEqual(body.snapshot, snapshot);
}
function commitFromPrepared(request, prepared) {
  return {...request, scope: deletion.PUSH_SCOPE, installation: {...request.installation, snapshot: clone(prepared.snapshot)}};
}
async function assertDirectDenied(f, request, options) {
  const before = clone(f.documents), index = f.transactions.length;
  await assert.rejects(() => prepareDirect(f, request, options), safeError);
  assert.deepEqual(f.documents, before); assert.deepEqual(queuedWrites(f, index), []);
}

for (const active of [true, false]) test(`actual store and HTTP prepare an original ${active ? "active" : "pending-only"} snapshot with no writes`, async () => {
  const {f, request, originalSnapshot} = await ready({active}), before = clone(f.documents), index = f.transactions.length;
  const direct = await prepareDirect(f, request); assertPrepared(direct, request, originalSnapshot);
  assert.ok(direct.authorizationValidUntilMs > f.now());
  const result = await f.call(request); assert.equal(result.status, 200); assertPrepared(result.body, request, originalSnapshot);
  assert.equal(Object.hasOwn(result.body, "authorizationValidUntilMs"), false); assert.equal(result.headers["cache-control"], "no-store");
  assert.deepEqual(f.documents, before); assert.deepEqual(queuedWrites(f, index), []);
  assert.deepEqual(f.calls, {services: 1, auth: 1, app: 1, user: 1, boundary: 1, ledger: 1, push: 1});
  assert.equal(f.authInputs[0].checkRevoked, true); assert.deepEqual(f.appInputs[0].settings, {consume: true});
  for (const secret of [key, token, "nonce-" + String(1).padStart(50, "0")]) assert.equal(JSON.stringify(result).includes(secret), false);
});

test("preparation accepts independent reader and registry epochs but never substitutes a stale binding", async () => {
  const {f, request} = await ready();
  await f.registry.begin(registration({clientRevision: 2}), {appId: APP, ownerUID: "account_b"});
  await f.registry.begin(registration({clientRevision: 3}), registryClient);
  await assertDirectDenied(f, request);
  const commit = await f.pushRequest(), {snapshot, ...installation} = commit.installation;
  const current = {...commit, scope: PREPARE_SCOPE, installation};
  assert.equal(current.membershipEpoch, 1); assert.equal(current.installation.expected.ownerEpoch, 3);
  const index = f.transactions.length; assertPrepared(await prepareDirect(f, current), current, snapshot); assert.deepEqual(queuedWrites(f, index), []);
});

test("missing push verifier or disabled configuration is inert before service construction", async () => {
  const {f, request} = await ready(), before = clone(f.documents), index = f.transactions.length;
  for (const override of [{verifyPushBoundary: undefined}, {verifyPushBoundary: {}}, {verifyBoundary: undefined},
    {verifyLedgerBoundary: undefined}, {config: {...f.options.config, enabled: false}}]) safeUnavailable(await f.call(request, {}, override));
  assert.equal(f.calls.services, 0); assert.equal(f.transactions.length, index); assert.deepEqual(f.documents, before);
});

test("preparation validates raw nested fields and refuses caller snapshots or alternate scopes before services", async () => {
  const {f, request, originalSnapshot} = await ready(), valid = JSON.stringify(request), index = f.transactions.length;
  for (const raw of [valid.replace('"ownerEpoch":1', '"ownerEpoch":1,"owner\\u0045poch":2'), "{", "[]", "null",
    JSON.stringify({...request, installation: {...request.installation, snapshot: originalSnapshot}}),
    JSON.stringify({...request, scope: "reader-push-installation-prepare-v2"}),
    JSON.stringify({...request, parentRequestID: "f".repeat(64)}),
    JSON.stringify({...request, installation: {...request.installation, allDevices: true}}),
  ]) {const input = f.http(request); input.rawBody = Buffer.from(raw); safeUnavailable(await createReaderDeletionEndpoint(f.options)(input), 400);}
  const over = f.http(request); over.rawBody = Buffer.alloc(endpointModule.MAX_BODY_BYTES + 1);
  safeUnavailable(await createReaderDeletionEndpoint(f.options)(over), 413);
  const duplicate = f.http(request); duplicate.rawHeaders = Object.entries(duplicate.headers).flat(); duplicate.rawHeaders.push("Authorization", "Bearer second");
  safeUnavailable(await createReaderDeletionEndpoint(f.options)(duplicate), 400);
  assert.equal(f.calls.services, 0); assert.equal(f.transactions.length, index);
});

test("original completed parent ledger and frozen membership are required for preparation", async () => {
  for (const alter of [
    (f) => f.documents.delete(`${REQUESTS}/${parentID()}`), (f) => f.documents.delete(`${REQUESTS}/${ledgerID()}`),
    (f) => {f.documents.get(`${REQUESTS}/${parentID()}`).status = "pending";},
    (f) => {f.documents.get(`${REQUESTS}/${ledgerID()}`).status = "pending"; f.documents.get(`${REQUESTS}/${ledgerID()}`).phase = "receipts";},
    (f) => {f.documents.get(`${MEMBERSHIPS}/${UID}`).state = "active";},
    (f) => {f.documents.get(`${MEMBERSHIPS}/${UID}`).epoch = 2;},
  ]) {const {f, request} = await ready(); alter(f); await assertDirectDenied(f, request);}
});

test("preparation cannot borrow commit proof scope or foreign project app owner and inventory", async () => {
  for (const bad of [{scope: deletion.PUSH_SCOPE}, {ownerUID: "foreign_owner"}, {projectID: "foreign-project"},
    {appID: "foreign-app"}, {installationId: "44444444-4444-4444-8444-000000000002"},
    {requestDigest: "c".repeat(64)}, {parentRequestID: "c".repeat(64)}, {unresolved: []}]) {
    const {f, request} = await ready(); f.overrides.push = bad; await assertDirectDenied(f, request);
  }
});

test("B guest and A-to-B-to-A ownership changes reject the original expected registry counters", async () => {
  for (const owners of [["account_b"], [null], ["account_b", UID]]) {
    const {f, request} = await ready(); let revision = 1;
    for (const ownerUID of owners) await f.registry.begin(registration({clientRevision: ++revision}), {appId: APP, ownerUID});
    await assertDirectDenied(f, request);
    const result = await f.call(request); assert.notEqual(result.status, 200); assert.equal(Object.hasOwn(result.body, "snapshot"), false);
  }
});

test("raw request and configuration are frozen before awaited identity and proof work", async () => {
  for (const phase of ["services", "auth", "push"]) {
    const {f, request, originalSnapshot} = await ready(), entered = deferred(), release = deferred(), original = clone(request);
    const input = f.http(request); f.httpHooks[phase] = async () => {entered.resolve(); await release.promise;};
    const pending = createReaderDeletionEndpoint(f.options)(input); await entered.promise;
    input.rawBody.fill(32); input.headers.authorization = "Bearer changed"; f.options.config.projectID = "foreign-project";
    request.installation.expected.ownerEpoch += 1; request.installation.key = "changed"; release.resolve();
    const result = await pending; assert.equal(result.status, 200); assertPrepared(result.body, original, originalSnapshot);
    assert.equal(f.authInputs[0].token, "local.auth.1");
  }
});

test("direct preparation captures nested request primitives before identity verification awaits", async () => {
  const {f, request, originalSnapshot} = await ready(), entered = deferred(), release = deferred(), original = clone(request), identity = f.identity();
  const pending = prepareDirect(f, request, {verifyClient: async () => {entered.resolve(); await release.promise; return identity;}});
  await entered.promise; request.installation.expected.clientRevision += 1; request.installation.key = "changed";
  request.expectedUID = "foreign_owner"; release.resolve(); assertPrepared(await pending, original, originalSnapshot);
});

test("readset conflict cannot replace the first observed snapshot even when counters remain unchanged", async () => {
  const {f, request} = await ready(), original = clone(f.row()); let changed = false;
  f.hooks.beforeCommit = async (trace, attempt) => {
    if (attempt !== 0 || !trace.reads.includes(`${INSTALLATIONS}/${iid}`)) return;
    changed = true; const challenge = f.documents.get(`${CHALLENGES}/${f.row().active.proof.challengeId}`); challenge.confirmedAtMs += 1;
  };
  const index = f.transactions.length;
  await assert.rejects(() => prepareDirect(f, request), safeError);
  assert.equal(changed, true); assert.ok(f.transactions.length >= index + 2); assert.deepEqual(f.row(), original); assert.deepEqual(queuedWrites(f, index), []);
});

test("read-only transaction retries pin the first proof family", async () => {
  const {f, request} = await ready(); const before = clone(f.documents), index = f.transactions.length; let changed = false;
  f.hooks.beforeCommit = async (_trace, attempt) => {if (attempt === 0) {changed = true; f.overrides.push.writerFenceRevision = "c".repeat(64); f.hooks.retryCommits = 1;}};
  await assert.rejects(() => prepareDirect(f, request), (error) => error.code === "reader_boundary_changed");
  assert.equal(changed, true); assert.ok(f.transactions.length >= index + 2); assert.deepEqual(f.documents, before); assert.deepEqual(queuedWrites(f, index), []);
});

test("each shortest identity and boundary deadline denies a prepared snapshot after the final registry read", async () => {
  for (const shortest of ["appCheck", "idToken", "recentAuth", "parentProof", "ledgerProof", "pushProof"]) {
    const {f, request} = await ready(), seconds = Math.floor(f.now() / 1000), changes = {};
    if (shortest === "appCheck") changes.appClaims = {exp: seconds + 1};
    if (shortest === "idToken") changes.claims = {exp: seconds + 1};
    if (shortest === "recentAuth") changes.claims = {auth_time: seconds - 299};
    const phase = {parentProof: "boundary", ledgerProof: "ledger", pushProof: "push"}[shortest];
    const proofDeadline = f.now() + 1000;
    if (phase) f.httpHooks[phase] = (value) => {value.validUntilMs = proofDeadline;};
    const index = f.transactions.length, path = [...f.documents.keys()].find((key) => key.startsWith(TOKENS + "/")); let advanced = false;
    f.hooks.afterRead = (read) => {if (read === path && !advanced) {advanced = true; f.advance(1001);}};
    const result = await f.call(request, changes); assert.notEqual(result.status, 200); assert.equal(result.body.status, "unavailable");
    assert.equal(Object.hasOwn(result.body, "snapshot"), false); assert.equal(advanced, true); assert.deepEqual(queuedWrites(f, index), []);
  }
});

test("delayed verifier and late read-only transaction return cannot release an expired snapshot", async () => {
  for (const mode of ["identity", "pushVerifier", "proofOnlyTransactionReply"]) {
    const {f, request} = await ready(), index = f.transactions.length, before = clone(f.documents); let reached = false;
    if (mode === "identity") f.httpHooks.auth = async () => {reached = true; f.advance(601000);};
    if (mode === "pushVerifier") f.httpHooks.push = async () => {reached = true; f.advance(601000);};
    if (mode === "proofOnlyTransactionReply") {
      f.httpHooks.push = (value) => {value.validUntilMs = f.now() + 1000;};
      f.hooks.afterCommit = async (trace) => {if (trace.reads.includes(`${INSTALLATIONS}/${iid}`)) {reached = true; f.advance(1001);}};
    }
    const result = await f.call(request); assert.notEqual(result.status, 200); assert.equal(result.body.status, "unavailable");
    assert.equal(Object.hasOwn(result.body, "snapshot"), false); assert.equal(reached, true);
    assert.deepEqual(f.documents, before); assert.deepEqual(queuedWrites(f, index), []);
  }
});

test("direct store and orchestration both reject a read-only reply that outlives proof validity", async () => {
  for (const directStore of [true, false]) {
    const {f, request} = await ready(), before = clone(f.documents), index = f.transactions.length;
    f.overrides.push.validUntilMs = f.now() + 1000;
    f.hooks.afterCommit = async (trace) => {if (trace.reads.includes(`${INSTALLATIONS}/${iid}`)) f.advance(1001);};
    await assert.rejects(() => directStore ? f.store.preparePush({request, identity: f.identity()}) : prepareDirect(f, request), safeError);
    assert.deepEqual(f.documents, before); assert.deepEqual(queuedWrites(f, index), []);
  }
});

test("injected provider deadline and lost read-only response have safe errors and fresh exact preparation retry", async () => {
  for (const phase of ["auth", "push", "afterTransaction"]) {
    const {f, request, originalSnapshot} = await ready(), before = clone(f.documents), index = f.transactions.length;
    const timeout = () => Object.assign(new Error("PRIVATE simulated provider timeout"), {code: "ETIMEDOUT"});
    if (phase === "afterTransaction") f.hooks.afterCommit = async () => {throw timeout();};
    else f.httpHooks[phase] = async () => {throw timeout();};
    safeUnavailable(await f.call(request)); assert.deepEqual(f.documents, before); assert.deepEqual(queuedWrites(f, index), []);
    f.hooks.afterCommit = null; delete f.httpHooks[phase];
    const result = await f.call(request); assert.equal(result.status, 200); assertPrepared(result.body, request, originalSnapshot);
    assert.deepEqual(f.documents, before); assert.deepEqual(queuedWrites(f, index), []);
  }
});

test("preparation does not authorize commit: credentials are consumed and fresh commit revalidates the original snapshot", async () => {
  for (const takeover of [false, true]) {
    const {f, request} = await ready(), input = f.http(request), endpoint = createReaderDeletionEndpoint(f.options);
    const prepared = await endpoint(input); assert.equal(prepared.status, 200); const commit = commitFromPrepared(request, prepared.body);
    if (takeover) await f.registry.begin(registration({clientRevision: 2}), {appId: APP, ownerUID: "account_b"});
    const index = f.transactions.length;
    safeUnavailable(await endpoint({...input, rawBody: Buffer.from(JSON.stringify(commit))}), 401); assert.equal(f.transactions.length, index);
    const committed = await f.call(commit);
    if (takeover) {assert.notEqual(committed.status, 200); assert.deepEqual(queuedWrites(f, index), []);}
    else {assert.equal(committed.status, 200); assert.equal(committed.body.status, "installationRetired"); assert.equal(f.row().active.state, "revoked");}
  }
});

function projectionEndpoint(prepared, options, calls) {
  const source = fs.readFileSync(require.resolve("./readerDeletionEndpoint"), "utf8"), module = {exports: {}};
  vm.runInNewContext(source, {module, exports: module.exports, Buffer, structuredClone,
    require: (name) => name === "./readerAccountDeletion" ? {...deletion,
      prepareReaderPushRetirement: async () => {calls.prepare += 1; return prepared;},
      beginReaderPushRetirement: () => {calls.commit += 1; throw new Error("PRIVATE commit branch");},
      runReaderAccountDeletion: () => {calls.worker += 1; throw new Error("PRIVATE worker branch");}} : require(name)}, {timeout: 1000});
  return module.exports.createReaderDeletionEndpoint(options);
}

test("response projection returns only the fixed prepared data and strips its internal deadline", async () => {
  const {f, request, originalSnapshot} = await ready(), prepared = await prepareDirect(f, request), calls = {prepare: 0, commit: 0, worker: 0};
  const result = await projectionEndpoint(prepared, f.options, calls)(f.http(request));
  assert.equal(result.status, 200); assertPrepared(clone(result.body), request, originalSnapshot);
  assert.equal(Object.hasOwn(result.body, "authorizationValidUntilMs"), false); assert.deepEqual(calls, {prepare: 1, commit: 0, worker: 0});
});

test("response projection rejects malformed prepared metadata snapshot claims and private extras", async () => {
  const {f, request} = await ready(), prepared = await prepareDirect(f, request);
  for (const alter of [
    (r) => {r.expectedUID = "foreign_owner";}, (r) => {r.scope = deletion.PUSH_SCOPE;}, (r) => {r.membershipEpoch += 1;},
    (r) => {r.ledgerRequestID = "f".repeat(64);}, (r) => {r.status = "installationRetired";}, (r) => {r.preparedOnly = false;},
    (r) => {r.retirementComplete = true;}, (r) => {r.accountDeletionComplete = true;}, (r) => {r.historicalMaterialComplete = true;},
    (r) => {r.deliveriesRecalled = true;}, (r) => {r.unresolved = [];}, (r) => {r.authorizationValidUntilMs = f.now();},
    (r) => {r.snapshot.stateDigest = "malformed";}, (r) => {r.snapshot.ownerUID = "foreign_owner";},
    (r) => {r.snapshot.ownerEpoch += 1;}, (r) => {r.snapshot.clientRevision += 1;}, (r) => {r.snapshot.appId = "foreign-app";},
    (r) => {r.snapshot.key = "PRIVATE secret";}, (r) => {r.PRIVATE = "PRIVATE unexpected material";},
  ]) {
    const malformed = clone(prepared); alter(malformed); const result = await projectionEndpoint(malformed, f.options, {prepare: 0, commit: 0, worker: 0})(f.http(request));
    assert.notEqual(result.status, 200); assert.equal(result.body.status, "unavailable"); assert.equal(JSON.stringify(result).includes("PRIVATE"), false);
    assert.equal(Object.hasOwn(result.body, "snapshot"), false);
  }
});

test("old public validator and parent worker cannot infer preparation and deployed index stays closed", async () => {
  const {f, request} = await ready(); assert.throws(() => deletion.validateReaderAccountDeletionRequest(request), safeError);
  await assert.rejects(() => runReaderAccountDeletion({store: f.store, scope: PREPARE_SCOPE, requestID: parentID()}), safeError);
  const source = fs.readFileSync(require.resolve("./index"), "utf8"), registrationSource = source.slice(source.indexOf("exports.readerAccountDeletion = onRequest("));
  assert.ok(registrationSource.startsWith("exports.readerAccountDeletion = onRequest("));
  for (const enabled of ["false", "true"]) {
    let sdk = 0; const exports = {}, trap = () => {sdk += 1; throw new Error("PRIVATE SDK forbidden");};
    vm.runInNewContext(registrationSource, {exports, process: {env: {READER_DELETION_ENABLED: enabled,
      READER_DELETION_PROJECT_ID: PROJECT, READER_DELETION_APP_ID: APP}}, getApp: () => ({options: {projectId: PROJECT}}),
      getAuth: trap, getAppCheck: trap, getFirestore: trap, readerDeletionConfigFromEnvironment: endpointModule.readerDeletionConfigFromEnvironment,
      createReaderDeletionHttpHandler: endpointModule.createReaderDeletionHttpHandler, onRequest: (_options, handler) => handler}, {timeout: 1000});
    const result = {}, response = {set: (value) => {result.headers = value;}, status: (value) => {result.status = value; return response;}, json: (value) => {result.body = value;}};
    await exports.readerAccountDeletion(f.http(request), response); safeUnavailable(result); assert.equal(sdk, 0);
  }
});

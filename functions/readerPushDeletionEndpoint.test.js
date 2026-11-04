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
async function ready(options) {const f = fixture(); await f.seed(options); await f.completeParents(); return {f, request: await f.pushRequest()};}
function safeUnavailable(result, status = 503) {
  assert.equal(result.status, status); assert.equal(result.headers["cache-control"], "no-store");
  assert.equal(result.headers.pragma, "no-cache"); assert.equal(result.body.status, "unavailable");
  assert.deepEqual(Object.keys(result.body).sort(), ["error", "status"]);
  assert.equal(JSON.stringify(result).includes("PRIVATE"), false);
}

for (const active of [true, false]) test(`actual HTTP identity store and registry retire an original ${active ? "active" : "pending-only"} snapshot`, async () => {
  const {f, request} = await ready({active}); const parent = clone(f.documents.get(`${REQUESTS}/${parentID()}`));
  const ledger = clone(f.documents.get(`${REQUESTS}/${ledgerID()}`)), member = clone(f.documents.get(`${MEMBERSHIPS}/${UID}`));
  const result = await f.call(request);
  assert.equal(result.status, 200); assert.equal(result.body.scope, deletion.PUSH_SCOPE); assert.equal(result.body.status, "installationRetired");
  assert.equal(result.body.accountDeletionComplete, false); assert.equal(result.body.historicalMaterialComplete, false);
  assert.equal(result.body.deliveriesRecalled, false); assert.deepEqual(result.body.unresolved, deletion.PUSH_UNRESOLVED);
  assert.equal(result.body.retirementReceipt.ownerUID, UID); assert.equal(result.body.retirementReceipt.installationId, iid);
  assert.deepEqual(f.documents.get(`${REQUESTS}/${parentID()}`), parent); assert.deepEqual(f.documents.get(`${REQUESTS}/${ledgerID()}`), ledger);
  assert.deepEqual(f.documents.get(`${MEMBERSHIPS}/${UID}`), member);
  assert.deepEqual(f.calls, {services: 1, auth: 1, app: 1, user: 1, boundary: 1, ledger: 1, push: 1});
  assert.equal(f.authInputs[0].checkRevoked, true); assert.deepEqual(f.appInputs[0].settings, {consume: true});
  assert.equal(f.row().active.state, "revoked"); assert.equal(result.headers["cache-control"], "no-store");
  for (const secret of [key, token, "nonce-" + String(1).padStart(50, "0")]) assert.equal(JSON.stringify(result).includes(secret), false);
});

test("missing explicit push verifier closes the valid push route before service creation", async () => {
  const {f, request} = await ready(), before = clone(f.documents), index = f.transactions.length;
  for (const verifyPushBoundary of [undefined, null, {verified: true}]) safeUnavailable(await f.call(request, {}, {verifyPushBoundary}));
  assert.equal(f.calls.services, 0); assert.equal(f.calls.auth, 0); assert.equal(f.transactions.length, index); assert.deepEqual(f.documents, before);
});

test("parent and ledger HTTP remain usable without the new push verifier and never retire an installation", async () => {
  const f = fixture(); await f.seed(); const pushRows = clone([...f.documents].filter(([path]) => [INSTALLATIONS, CHALLENGES, TOKENS].some((prefix) => path.startsWith(prefix + "/"))));
  const parent = await f.call({expectedUID: UID, membershipEpoch: 1}, {}, {verifyPushBoundary: undefined});
  assert.equal(parent.status, 200); assert.equal(parent.body.status, "scopedCloudDataRemoved");
  const ledger = await f.call({schemaVersion: 1, scope: LEDGER_SCOPE, expectedUID: UID, membershipEpoch: 1, parentRequestID: parentID()}, {}, {verifyPushBoundary: undefined});
  assert.equal(ledger.status, 200); assert.equal(ledger.body.status, "ledgerDataRemoved"); assert.equal(f.calls.push, 0);
  for (const [path, value] of pushRows) assert.deepEqual(f.documents.get(path), value);
});

test("strict raw body rejects nested duplicate escaped keys malformed JSON and oversized bytes before services", async () => {
  const {f, request} = await ready(), valid = JSON.stringify(request), index = f.transactions.length;
  const cases = [
    [valid.replace('"ownerEpoch":1', '"ownerEpoch":1,"owner\\u0045poch":2'), 400],
    [valid.replace('"stateDigest":', '"ownerUID":"forged","stateDigest":'), 400],
    ['{"scope":"' + deletion.PUSH_SCOPE + '","scope":"other"}', 400],
    ["{", 400], ["[]", 400], ["null", 400], [Buffer.from([255]), 400], [Buffer.alloc(endpointModule.MAX_BODY_BYTES + 1), 413],
  ];
  for (const [body, status] of cases) {const input = f.http(request); input.rawBody = Buffer.isBuffer(body) ? body : Buffer.from(body);
    safeUnavailable(await createReaderDeletionEndpoint(f.options)(input), status);}
  assert.equal(f.calls.services, 0); assert.equal(f.transactions.length, index);
});

test("push-specific invalid request method scope snapshot and credential headers never construct services", async () => {
  const {f, request} = await ready(), index = f.transactions.length;
  for (const [alter, status] of [
    [(r) => {r.method = "GET";}, 405], [(r) => {r.query = {installations: "all"};}, 400],
    [(r) => {r.rawBody = undefined; r.body = request;}, 400], [(r) => {r.headers["content-type"] = "text/plain";}, 415],
    [(r) => {r.headers["content-encoding"] = "gzip";}, 415], [(r) => {r.headers.authorization = "";}, 401],
    [(r) => {r.headers.Authorization = "Bearer second";}, 400],
    [(r) => {r.rawHeaders = Object.entries(r.headers).flat(); r.rawHeaders.push("X-Firebase-AppCheck", "second.token");}, 400],
    [(r) => {const body = clone(request); body.installation.snapshot.ownerUID = "foreign_owner"; r.rawBody = Buffer.from(JSON.stringify(body));}, 400],
    [(r) => {const body = clone(request); body.scope = "reader-push-installation-retirement-v2"; r.rawBody = Buffer.from(JSON.stringify(body));}, 400],
    [(r) => {const body = clone(request); body.installation.allDevices = true; r.rawBody = Buffer.from(JSON.stringify(body));}, 400],
  ]) {const input = f.http(request); alter(input); safeUnavailable(await createReaderDeletionEndpoint(f.options)(input), status);}
  assert.equal(f.calls.services, 0); assert.equal(f.transactions.length, index);
});

test("consumed App Check revoked Auth disabled user and foreign Firebase namespace fail before transactions", async () => {
  const {f, request} = await ready(); const reused = f.http(request); f.consumed.add(reused.headers["x-firebase-appcheck"]);
  const index = f.transactions.length; safeUnavailable(await createReaderDeletionEndpoint(f.options)(reused), 401);
  for (const change of [{claims: {aud: "foreign-project"}}, {claims: {uid: "foreign_user", sub: "foreign_user"}},
    {claims: {firebase: {tenant: "tenant-a", sign_in_provider: "apple.com"}}}, {appClaims: {app_id: "foreign-app"}}]) safeUnavailable(await f.call(request, change), 401);
  f.httpHooks.auth = () => {const error = new Error("PRIVATE revoked token"); error.code = "auth/id-token-revoked"; throw error;};
  safeUnavailable(await f.call(request), 401); delete f.httpHooks.auth;
  f.httpHooks.user = (value) => {value.disabled = true;}; safeUnavailable(await f.call(request), 401);
  assert.equal(f.transactions.length, index); assert.equal(f.row().active.state, "active");
});

test("foreign ownership and A-to-B-to-A reject the caller snapshot rather than preparing a replacement", async () => {
  for (const owners of [["account_b"], [null], ["account_b", UID]]) {
    const {f, request} = await ready(); let revision = 1;
    for (const ownerUID of owners) await f.registry.begin(registration({clientRevision: ++revision}), {appId: APP, ownerUID});
    const before = clone(f.documents), index = f.transactions.length; const result = await f.call(request);
    assert.notEqual(result.status, 200); assert.equal(result.body.status, "unavailable");
    assert.deepEqual(f.documents, before); assert.deepEqual(queuedWrites(f, index), []);
  }
});

test("raw body headers and config mutation during awaited effects cannot retarget the captured request", async () => {
  for (const phase of ["services", "auth", "push"]) {
    const {f, request} = await ready(), entered = deferred(), release = deferred(); const input = f.http(request);
    f.httpHooks[phase] = async () => {entered.resolve(); await release.promise;};
    const endpoint = createReaderDeletionEndpoint(f.options), promise = endpoint(input); await entered.promise;
    input.rawBody.fill(32); input.headers.authorization = "Bearer changed"; input.headers["x-firebase-appcheck"] = "changed.app";
    f.options.config.appID = "foreign-app"; f.options.config.projectID = "foreign-project"; request.installation.snapshot.ownerUID = "foreign_owner";
    release.resolve(); const result = await promise;
    assert.equal(result.status, 200); assert.equal(result.body.retirementReceipt.ownerUID, UID); assert.equal(result.body.retirementReceipt.appId, APP);
    assert.equal(f.authInputs[0].token, "local.auth.1"); assert.equal(f.appInputs[0].token, "local.app.1");
  }
});

test("late identity and boundary proofs reject without queuing registry writes", async () => {
  for (const phase of ["app", "auth", "user", "boundary", "ledger", "push"]) {
    const {f, request} = await ready(), entered = deferred(), release = deferred(); const index = f.transactions.length;
    f.httpHooks[phase] = async () => {entered.resolve(); await release.promise;};
    const promise = f.call(request); await entered.promise; f.advance(601000); release.resolve();
    safeUnavailable(await promise, 401); assert.deepEqual(queuedWrites(f, index), []); assert.equal(f.row().active.state, "active");
  }
});

test("each shortest HTTP identity and boundary deadline is rechecked at the last registry read", async () => {
  for (const shortest of ["appCheck", "idToken", "recentAuth", "parentProof", "ledgerProof", "pushProof"]) {
    const {f, request} = await ready(), seconds = Math.floor(f.now() / 1000), changes = {};
    if (shortest === "appCheck") changes.appClaims = {exp: seconds + 1};
    if (shortest === "idToken") changes.claims = {exp: seconds + 1};
    if (shortest === "recentAuth") changes.claims = {auth_time: seconds - 299};
    const phase = {parentProof: "boundary", ledgerProof: "ledger", pushProof: "push"}[shortest];
    if (phase) f.httpHooks[phase] = (value) => {value.validUntilMs = f.now() + 1000;};
    const index = f.transactions.length, indexPath = [...f.documents.keys()].find((path) => path.startsWith(TOKENS + "/")); let advanced = false;
    f.hooks.afterRead = (path) => {if (path === indexPath && !advanced) {advanced = true; f.advance(1001);}};
    const result = await f.call(request, changes); assert.notEqual(result.status, 200); assert.equal(result.body.status, "unavailable");
    assert.equal(advanced, true); assert.deepEqual(queuedWrites(f, index), []); assert.equal(f.row().active.state, "active");
  }
});

test("committed late reply is hidden and a fresh HTTP attempt recovers the same durable receipt without extra writes", async () => {
  const {f, request} = await ready(); let held = false;
  f.hooks.afterCommit = async (trace) => {if (!held && trace.sets.includes(`${INSTALLATIONS}/${iid}`)) {held = true; f.advance(301000);}};
  safeUnavailable(await f.call(request), 401); assert.equal(held, true); assert.equal(f.row().active.state, "revoked");
  const committed = clone(f.documents), index = f.transactions.length; f.hooks.afterCommit = null;
  const recovered = await f.call(request); assert.equal(recovered.status, 200); assert.equal(recovered.body.status, "installationRetired");
  assert.deepEqual(f.documents, committed); assert.deepEqual(committedWrites(f, index), []);
  assert.equal(f.calls.auth, 2); assert.notEqual(f.authInputs[0].token, f.authInputs[1].token);
  assert.notEqual(f.appInputs[0].token, f.appInputs[1].token);
});

test("late service factory cannot lend new token time and wrong database never reaches verifier", async () => {
  const {f, request} = await ready(), index = f.transactions.length; f.httpHooks.services = async () => {f.advance(3601000);};
  safeUnavailable(await f.call(request), 401); assert.equal(f.transactions.length, index);
  const other = await ready(), before = other.f.calls.auth; other.f.db.databaseId = "research";
  safeUnavailable(await other.f.call(other.request)); assert.equal(other.f.calls.auth, before);
});

// Evaluate only the actual closed deployment-registration slice, with inert SDK traps.
test("actual index remains closed for valid push scope with both disabled and enabled environment flags", async () => {
  const {f, request} = await ready(); const source = fs.readFileSync(require.resolve("./index"), "utf8");
  const registrationSource = source.slice(source.indexOf("exports.readerAccountDeletion = onRequest("));
  assert.ok(registrationSource.startsWith("exports.readerAccountDeletion = onRequest("));
  for (const enabled of ["false", "true"]) {
    let sdkCalls = 0, registered = 0; const exports = {}, sdk = () => {sdkCalls += 1; throw new Error("PRIVATE SDK must not start");};
    vm.runInNewContext(registrationSource, {exports, process: {env: {READER_DELETION_ENABLED: enabled,
      READER_DELETION_PROJECT_ID: PROJECT, READER_DELETION_APP_ID: APP}}, getApp: () => ({options: {projectId: PROJECT}}),
    getAuth: sdk, getAppCheck: sdk, getFirestore: sdk, readerDeletionConfigFromEnvironment: endpointModule.readerDeletionConfigFromEnvironment,
    createReaderDeletionHttpHandler: endpointModule.createReaderDeletionHttpHandler,
    onRequest: (options, handler) => {registered += 1; assert.equal(options.timeoutSeconds, 60); return handler;}}, {timeout: 1000});
    const output = {}, response = {set: (value) => {output.headers = value;}, status: (value) => {output.status = value; return response;},
      json: (value) => {output.body = value;}};
    await exports.readerAccountDeletion(f.http(request), response); safeUnavailable(output); assert.equal(sdkCalls, 0); assert.equal(registered, 1);
  }
});

// Only the response projection is substituted here. Success above uses the real stores.
function projectionEndpoint(receipt, options, calls) {
  const source = fs.readFileSync(require.resolve("./readerDeletionEndpoint"), "utf8"), module = {exports: {}};
  vm.runInNewContext(source, {module, exports: module.exports, Buffer, structuredClone,
    require: (name) => name === "./readerAccountDeletion" ? {...deletion,
      beginReaderPushRetirement: async () => {calls.push += 1; return receipt;},
      beginReaderAccountDeletion: () => {calls.parent += 1; throw new Error("PRIVATE parent branch");},
      runReaderAccountDeletion: () => {calls.worker += 1; throw new Error("PRIVATE worker branch");}} : require(name)}, {timeout: 1000});
  return module.exports.createReaderDeletionEndpoint(options);
}

test("strict response boundary accepts the actual receipt using only the explicit child branch", async () => {
  const {f, request} = await ready(), receipt = await f.push(request), calls = {push: 0, parent: 0, worker: 0};
  const result = await projectionEndpoint(receipt, f.options, calls)(f.http(request));
  assert.equal(result.status, 200); assert.equal(JSON.stringify(result.body), JSON.stringify(receipt));
  assert.deepEqual(calls, {push: 1, parent: 0, worker: 0});
});

test("strict response boundary rejects malformed bindings counters completion claims and unknown secrets", async () => {
  const {f, request} = await ready(), receipt = await f.push(request);
  for (const alter of [
    (r) => {r.requestID = "c".repeat(64);}, (r) => {r.ledgerRequestID = "c".repeat(64);}, (r) => {r.scope = SCOPE;},
    (r) => {r.installationId = "44444444-4444-4444-8444-000000000002";}, (r) => {r.accountDeletionComplete = true;},
    (r) => {r.historicalMaterialComplete = true;}, (r) => {r.deliveriesRecalled = true;}, (r) => {r.status = "pending";},
    (r) => {r.unresolved = [];}, (r) => {r.PRIVATE = "PRIVATE top-level material";},
    (r) => {r.retirementReceipt.ownerUID = "foreign_owner";}, (r) => {r.retirementReceipt.appId = "foreign-app";},
    (r) => {r.retirementReceipt.ownerEpoch += 1;}, (r) => {r.retirementReceipt.revision += 1;},
    (r) => {r.retirementReceipt.clientRevision += 1;}, (r) => {r.retirementReceipt.retiredAtMs = Number.NaN;},
    (r) => {r.retirementReceipt.retiredChallenges = -1;}, (r) => {r.retirementReceipt.removedTokenOwners = 3;},
    (r) => {r.retirementReceipt.retiredChallenges = 2; r.retirementReceipt.preservedForeignChallenges = 1;},
    (r) => {r.retirementReceipt.removedTokenOwners = 2; r.retirementReceipt.preservedUnprovenTokenOwners = 1;},
    (r) => {r.retirementReceipt.accountDeletionComplete = true;}, (r) => {r.retirementReceipt.token = "PRIVATE raw token";},
  ]) {
    const malformed = clone(receipt); alter(malformed); const calls = {push: 0, parent: 0, worker: 0};
    safeUnavailable(await projectionEndpoint(malformed, f.options, calls)(f.http(request)));
    assert.deepEqual(calls, {push: 1, parent: 0, worker: 0});
  }
});

test("response projection does not execute accessor fields or serialize private unresolved extensions", async () => {
  const {f, request} = await ready(), receipt = await f.push(request); let accessors = 0;
  for (const alter of [
    (r) => {Object.defineProperty(r, "requestID", {enumerable: true, get: () => {accessors += 1; return "PRIVATE";}});},
    (r) => {Object.defineProperty(r.retirementReceipt, "ownerUID", {enumerable: true, get: () => {accessors += 1; return "PRIVATE";}});},
    (r) => {Object.defineProperty(r.unresolved, "0", {enumerable: true, get: () => {accessors += 1; return "PRIVATE";}});},
    (r) => {r.unresolved.PRIVATE = "PRIVATE hidden material";},
  ]) {const malformed = clone(receipt); alter(malformed);
    safeUnavailable(await projectionEndpoint(malformed, f.options, {push: 0, parent: 0, worker: 0})(f.http(request)));}
  assert.equal(accessors, 0);
});

test("injected provider deadline rejection is safe before mutation and preserves a committed retirement for exact retry", async () => {
  // Simulated provider/transport deadline errors, not a local cancellation mechanism.
  const timeout = () => Object.assign(new Error("PRIVATE provider deadline detail"), {code: "ETIMEDOUT"});
  for (const phase of ["auth", "push"]) {
    const {f, request} = await ready(), index = f.transactions.length, before = clone(f.documents);
    f.httpHooks[phase] = async () => {throw timeout();};
    const result = await f.call(request); safeUnavailable(result);
    assert.deepEqual(result.body, {status: "unavailable", error: "deletion_unavailable"});
    assert.deepEqual(queuedWrites(f, index), []); assert.deepEqual(f.documents, before);
  }
  const {f, request} = await ready(); let rejectedAfterCommit = false;
  f.hooks.afterCommit = async (trace) => {
    if (trace.sets.includes(`${INSTALLATIONS}/${iid}`)) {rejectedAfterCommit = true; throw timeout();}
  };
  const failedReply = await f.call(request); safeUnavailable(failedReply);
  assert.deepEqual(failedReply.body, {status: "unavailable", error: "deletion_unavailable"});
  assert.equal(rejectedAfterCommit, true); assert.equal(f.row().active.state, "revoked");
  const child = [...f.documents].find(([path, row]) => path.startsWith(REQUESTS + "/") && row.scope === deletion.PUSH_SCOPE)?.[1];
  assert.equal(child?.status, "installationRetired");
  const exactReceipt = clone(child.retirementReceipt), committed = clone(f.documents), index = f.transactions.length;
  f.hooks.afterCommit = null;
  const retried = await f.call(request); assert.equal(retried.status, 200);
  assert.deepEqual(retried.body.retirementReceipt, exactReceipt); assert.deepEqual(f.documents, committed);
  assert.deepEqual(queuedWrites(f, index), []); assert.equal(f.calls.auth, 2);
});

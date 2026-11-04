const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const deletion = require("./readerAccountDeletion");
const {SCOPE, LEDGER_SCOPE, LEDGER_UNRESOLVED, MEMBERSHIPS, REQUESTS, UNRESOLVED,
  createReaderAccountDeletionStore, beginReaderAccountDeletion, runReaderAccountDeletion} = deletion;
const {SCOPE: MUTATION_SCOPE, RECEIPTS, REVISIONS, createReaderMutationStore} = require("./readerMutation");
const {INSTALLATIONS, CHALLENGES, TOKENS, createRecipientRegistry} = require("./recipientRegistry");
const UID = "push_reader_a", APP = "verified-ios-app", PROJECT = "local-apropos-test";
const iid = "44444444-4444-4444-8444-000000000001", key = "private-installation-key-" + "k".repeat(32);
const token = "private-registration-token-" + "t".repeat(50), clone = structuredClone;
const hash = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
const parentID = () => hash([SCOPE, UID, 1]);
const ledgerID = () => hash([LEDGER_SCOPE, parentID(), UID, 1]);
const registration = (extra = {}) => ({installationId: iid, key, token, clientRevision: 1, permission: true,
  preferences: {articles: "categories", categoryIds: ["film"], podcasts: true}, ...extra});
const registryClient = {appId: APP, ownerUID: UID};

// Local buffered transactional double only: no SDK, server, network or credentials.
function fixture() {
  const documents = new Map(), transactions = [], hooks = {afterRead: null, beforeCommit: null, beforeTransaction: null,
    retryCommits: 0, failCommit: false, loseReply: false, parentProof: null, ledgerProof: null, pushProof: null, identity: null};
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

test("BEFORE: actual completed parent and ledger cleanup leave push installation challenge and token index untouched", async () => {
  const f = fixture(); await f.seed();
  const pushRows = () => new Map([...f.documents].filter(([path]) => [INSTALLATIONS, CHALLENGES, TOKENS].some((name) => path.startsWith(name + "/"))));
  const before = clone(pushRows()), {parent, ledger} = await f.completeParents();
  assert.deepEqual(pushRows(), before);
  assert.equal(parent.accountDeletionComplete, false); assert.equal(ledger.accountDeletionComplete, false);
  assert.ok(parent.unresolved.includes("push_membership_and_pending_delivery"));
  assert.ok(ledger.unresolved.includes("push_membership_and_pending_delivery"));
  assert.equal(f.documents.get(`${MEMBERSHIPS}/${UID}`).state, "deletion_frozen");
  assert.equal(f.documents.has(`users/${UID}/favorites/local-article`), false);
  assert.equal([...f.documents.keys()].some((path) => path.startsWith(RECEIPTS + "/") || path.startsWith(REVISIONS + "/")), false);
});

const safeFailure = (error) => typeof error?.code === "string" && error.message === error.code;
const deferred = () => {let resolve; const promise = new Promise((finish) => {resolve = finish;}); return {promise, resolve};};
const state = (f) => clone(f.documents);
const queuedWritesSince = (f, index) => f.transactions.slice(index).flatMap((tx) => [...tx.sets, ...tx.deletes]);
const writesSince = (f, index) => f.transactions.slice(index).filter((tx) => tx.committed).flatMap((tx) => [...tx.sets, ...tx.deletes]);
async function ready(options) {const f = fixture(); await f.seed(options); await f.completeParents(); return {f, request: await f.pushRequest()};}
async function rejectsUnchanged(f, action) {const before = state(f), index = f.transactions.length;
  await assert.rejects(action, safeFailure); assert.deepEqual(f.documents, before); assert.deepEqual(writesSince(f, index), []);}

for (const active of [true, false]) test(`explicit push child atomically retires original ${active ? "active" : "pending-only"} installation and remains scoped`, async () => {
  const {f, request} = await ready({active});
  const parent = clone(f.documents.get(`${REQUESTS}/${parentID()}`)), ledger = clone(f.documents.get(`${REQUESTS}/${ledgerID()}`));
  const member = clone(f.documents.get(`${MEMBERSHIPS}/${UID}`)), research = clone(f.documents.get(`users/${UID}`));
  const result = await f.push(request);
  assert.equal(result.scope, deletion.PUSH_SCOPE); assert.equal(result.status, "installationRetired");
  assert.equal(result.accountDeletionComplete, false); assert.deepEqual(result.unresolved, deletion.PUSH_UNRESOLVED);
  assert.equal(result.retirementReceipt.status, "retired"); assert.equal(result.retirementReceipt.installationId, iid);
  assert.equal(result.retirementReceipt.ownerUID, UID); assert.equal(result.retirementReceipt.historicalMaterialComplete, false);
  assert.equal(result.retirementReceipt.deliveriesRecalled, false);
  assert.deepEqual(f.documents.get(`${REQUESTS}/${parentID()}`), parent); assert.deepEqual(f.documents.get(`${REQUESTS}/${ledgerID()}`), ledger);
  assert.deepEqual(f.documents.get(`${MEMBERSHIPS}/${UID}`), member); assert.deepEqual(f.documents.get(`users/${UID}`), research);
  const persisted = JSON.stringify([...f.documents]);
  for (const secret of [key, token, "nonce-" + String(1).padStart(50, "0")]) assert.equal(persisted.includes(secret), false, "No raw registration secret in completed records");
  assert.equal([...f.documents.keys()].some((path) => path.startsWith(TOKENS + "/")), false);
});

test("unknown or incomplete original parent, ledger and membership cannot authorize push retirement", async () => {
  for (const alter of [
    (f) => f.documents.delete(`${REQUESTS}/${parentID()}`),
    (f) => f.documents.delete(`${REQUESTS}/${ledgerID()}`),
    (f) => {f.documents.get(`${REQUESTS}/${parentID()}`).status = "pending";},
    (f) => {f.documents.get(`${REQUESTS}/${ledgerID()}`).phase = "receipts";},
    (f) => {f.documents.get(`${REQUESTS}/${ledgerID()}`).ownerUID = "other_owner";},
    (f) => {f.documents.get(`${MEMBERSHIPS}/${UID}`).state = "active";},
    (f) => {f.documents.get(`${MEMBERSHIPS}/${UID}`).epoch = 2;},
  ]) {const {f, request} = await ready(); alter(f); await rejectsUnchanged(f, () => f.push(request));}
});

test("request family, scope, extra fields and installation snapshot are exact before identity or storage", async () => {
  for (const alter of [
    (r) => {r.scope = SCOPE;}, (r) => {r.parentRequestID = "e".repeat(64);}, (r) => {r.ledgerRequestID = "e".repeat(64);},
    (r) => {r.extra = "unrecognized";}, (r) => {r.installation.snapshot.ownerUID = "other_owner";},
    (r) => {r.installation.expected.ownerEpoch += 1;}, (r) => {r.installation.snapshot.appId = "foreign-app";},
  ]) {const {f, request} = await ready(); alter(request); await rejectsUnchanged(f, () => f.push(request));}
});

test("verified identity rejects wrong owner project app tenant stale auth and expired App Check", async () => {
  for (const bad of [
    {uid: "other_owner"}, {projectID: "foreign-project"}, {appID: "foreign-app"}, {tenantID: "tenant"},
    {authTimeMs: 1}, {expiresAtMs: 1}, {appCheckExpiresAtMs: 1}, {appCheckIssuedAtMs: Number.NaN},
  ]) {const {f, request} = await ready(); const identity = {...f.identity(), ...bad};
    await rejectsUnchanged(f, () => f.push(request, {verifyClient: async () => identity}));}
});

test("unconfigured boundary policy or non-default database cannot fall back to parent deletion authority", async () => {
  for (const alter of [
    (f) => f.reopen({push: false}), (f) => f.reopen({policy: false}),
    (f) => {f.db.projectId = "another-project";}, (f) => {f.db.databaseId = "research";},
  ]) {const {f, request} = await ready(); alter(f); await rejectsUnchanged(f, () => f.push(request));}
});

test("fresh parent ledger and push inventory evidence must all match the original family", async () => {
  for (const [surface, bad] of [
    ["parent", {writerFenceRevision: "c".repeat(64)}], ["ledger", {migrationRevision: "c".repeat(64)}],
    ["push", {ownerUID: "other_owner"}], ["push", {membershipEpoch: 2}], ["push", {projectID: "foreign-project"}],
    ["push", {appID: "foreign-app"}], ["push", {parentRequestID: "c".repeat(64)}],
    ["push", {ledgerRequestID: "c".repeat(64)}], ["push", {installationId: "44444444-4444-4444-8444-000000000002"}],
    ["push", {requestDigest: "c".repeat(64)}], ["push", {unresolved: []}], ["push", {validUntilMs: 1}],
  ]) {const {f, request} = await ready(); f.overrides[surface] = bad; await rejectsUnchanged(f, () => f.push(request));}
});

test("delayed boundary proof cannot outlive its captured authorization or proof expiry", async () => {
  for (const phase of ["parentProof", "ledgerProof", "pushProof"]) {
    const {f, request} = await ready(); const entered = deferred(), release = deferred();
    f.hooks[phase] = async () => {entered.resolve(); await release.promise;};
    const before = state(f), index = f.transactions.length, outcome = f.push(request).then((value) => ({value}), (error) => ({error}));
    await entered.promise; f.advance(600001); release.resolve(); const result = await outcome;
    assert.ok(safeFailure(result.error)); assert.deepEqual(f.documents, before); assert.deepEqual(writesSince(f, index), []);
  }
});

test("expiry after the last registry read prevents every child and retirement write", async () => {
  const {f, request} = await ready();
  const indexPath = [...f.documents.keys()].find((path) => path.startsWith(TOKENS + "/"));
  const index = f.transactions.length;
  let advanced = false; f.hooks.afterRead = async (path) => {if (path === indexPath && !advanced) {advanced = true; f.advance(600001);}};
  await rejectsUnchanged(f, () => f.push(request)); assert.equal(advanced, true); assert.deepEqual(queuedWritesSince(f, index), []);
});

test("delayed identity verification rechecks current time before beginning child work", async () => {
  const {f, request} = await ready(), entered = deferred(), release = deferred();
  const identity = f.identity(), index = f.transactions.length;
  const task = f.push(request, {verifyClient: async () => {entered.resolve(); await release.promise; return identity;}});
  const outcome = task.then((value) => ({value}), (error) => ({error})); await entered.promise; f.advance(600001); release.resolve();
  assert.ok(safeFailure((await outcome).error)); assert.equal(f.transactions.length, index);
});

test("request and verified identity primitives are captured before subsequent awaits", async () => {
  const {f, request} = await ready(), entered = deferred(), release = deferred(), original = clone(request);
  const identity = f.identity(); f.hooks.pushProof = async () => {entered.resolve(); await release.promise;};
  const task = f.push(request, {verifyClient: async () => identity}); await entered.promise;
  request.expectedUID = "other_owner"; request.installation.key = "mutated"; request.installation.snapshot.ownerUID = "other_owner";
  identity.uid = "other_owner"; identity.appID = "foreign-app"; release.resolve();
  const result = await task; assert.equal(result.retirementReceipt.ownerUID, original.expectedUID);
  assert.equal(result.retirementReceipt.installationId, original.installation.installationId);
});

test("B guest and A-to-B-to-A takeover before the child transaction reject the original installation snapshot", async () => {
  for (const owners of [["account_b"], [null], ["account_b", UID]]) {
    const {f, request} = await ready(); let revision = 1;
    for (const ownerUID of owners) await f.registry.begin(registration({clientRevision: ++revision}), {appId: APP, ownerUID});
    await rejectsUnchanged(f, () => f.push(request));
  }
});

test("transaction conflict replays all original family checks and cannot commit a discarded retirement plan", async () => {
  const {f, request} = await ready(), other = await ready();
  await other.f.registry.begin(registration({clientRevision: 2}), {appId: APP, ownerUID: "account_b"});
  const changed = new Map([...other.f.documents].filter(([path]) => [INSTALLATIONS, CHALLENGES, TOKENS].some((name) => path.startsWith(name + "/"))));
  const index = f.transactions.length; let conflicts = 0;
  f.hooks.beforeCommit = async (trace, attempt) => {if (attempt === 0 && trace.reads.includes(`${INSTALLATIONS}/${iid}`)) {
    conflicts += 1; for (const [path, row] of changed) f.documents.set(path, clone(row));
  }};
  await assert.rejects(() => f.push(request), safeFailure); assert.equal(conflicts, 1);
  assert.ok(f.transactions.length >= index + 2); assert.deepEqual(writesSince(f, index), []);
  for (const [path, row] of changed) assert.deepEqual(f.documents.get(path), row);
});

test("retry callback reruns the same transaction-bound boundary verifier", async () => {
  const {f, request} = await ready(); let proofs = 0;
  f.hooks.pushProof = async () => {proofs += 1;}; f.hooks.retryCommits = 1;
  const result = await f.push(request); assert.equal(result.status, "installationRetired"); assert.equal(proofs, 2);
});

test("atomic commit failure preserves parent and installation and permits exact retry", async () => {
  const {f, request} = await ready(); f.hooks.failCommit = true;
  await rejectsUnchanged(f, () => f.push(request));
  assert.equal((await f.push(request)).status, "installationRetired");
});

test("lost reply is recovered by freshly authenticated identical request after logical store reconstruction", async () => {
  const {f, request} = await ready(); f.hooks.loseReply = true;
  await assert.rejects(() => f.push(request), safeFailure); const committed = state(f), index = f.transactions.length;
  f.reopen(); let verified = 0;
  const result = await f.push(request, {verifyClient: async () => {verified += 1; return f.identity();}});
  assert.equal(result.status, "installationRetired"); assert.equal(verified, 1);
  assert.deepEqual(f.documents, committed); assert.deepEqual(writesSince(f, index), []);
});

test("idempotent child retry does not become authority for a changed request or expired identity", async () => {
  const {f, request} = await ready(); const first = await f.push(request), index = f.transactions.length;
  assert.deepEqual(await f.push(request), first); assert.deepEqual(writesSince(f, index), []);
  const changed = clone(request); changed.installation.requestId = "different-push-cleanup-request-002";
  await rejectsUnchanged(f, () => f.push(changed));
  await rejectsUnchanged(f, () => f.push(request, {verifyClient: async () => ({...f.identity(), appCheckExpiresAtMs: 1})}));
});

test("malformed persisted child receipt fails closed and never overwrites its record", async () => {
  for (const alter of [(job) => {job.ownerUID = "other_owner";}, (job) => {job.retirementReceipt.accountDeletionComplete = true;}]) {
    const {f, request} = await ready(); const result = await f.push(request);
    const path = `${REQUESTS}/${result.requestID}`; const job = f.documents.get(path);
    assert.ok(job, "Actual child record must be persisted"); alter(job);
    await rejectsUnchanged(f, () => f.push(request));
  }
});

test("the existing deletion entry and worker cannot expose or execute the explicit push child", async () => {
  const {f, request} = await ready(), before = state(f), index = f.transactions.length;
  assert.throws(() => deletion.validateReaderAccountDeletionRequest(request), safeFailure);
  await assert.rejects(() => beginReaderAccountDeletion({store: f.store, verifyClient: async () => f.identity(), expectedAppID: APP,
    request, now: f.now}), safeFailure);
  await assert.rejects(() => runReaderAccountDeletion({store: f.store, requestID: parentID(), scope: deletion.PUSH_SCOPE}), safeFailure);
  assert.deepEqual(f.documents, before); assert.deepEqual(writesSince(f, index), []);
});

test("reader membership epoch and actual registry ownership epoch remain independent", async () => {
  const {f} = await ready();
  await f.registry.begin(registration({clientRevision: 2}), {appId: APP, ownerUID: "account_b"});
  await f.registry.begin(registration({clientRevision: 3}), registryClient);
  const request = await f.pushRequest();
  assert.equal(request.membershipEpoch, 1); assert.equal(request.installation.expected.ownerEpoch, 3);
  const result = await f.push(request);
  assert.equal(result.status, "installationRetired"); assert.equal(result.retirementReceipt.ownerEpoch, 3);
  assert.equal(f.documents.get(`${MEMBERSHIPS}/${UID}`).epoch, 1);
});

test("each shortest identity deadline independently denies writes after the final registry read", async () => {
  for (const shortest of ["appCheck", "idToken", "recentAuth"]) {
    const {f, request} = await ready(), identity = f.identity();
    if (shortest === "appCheck") identity.appCheckExpiresAtMs = f.now() + 1000;
    if (shortest === "idToken") identity.expiresAtMs = f.now() + 1000;
    if (shortest === "recentAuth") identity.authTimeMs = f.now() - 299000;
    const deadlines = {appCheck: identity.appCheckExpiresAtMs, idToken: identity.expiresAtMs, recentAuth: identity.authTimeMs + 300000};
    const indexPath = [...f.documents.keys()].find((path) => path.startsWith(TOKENS + "/")), index = f.transactions.length; let advanced = false;
    f.hooks.afterRead = async (path) => {if (path === indexPath && !advanced) {advanced = true; f.advance(1001);}};
    await rejectsUnchanged(f, () => f.push(request, {verifyClient: async () => identity})); assert.equal(advanced, true);
    assert.deepEqual(queuedWritesSince(f, index), []);
    assert.ok(deadlines[shortest] < f.now());
    for (const [kind, deadline] of Object.entries(deadlines)) if (kind !== shortest) assert.ok(deadline > f.now());
  }
});

test("transaction replay cannot adopt a different push proof or a consistently replaced parent-ledger boundary family", async () => {
  for (const mode of ["push", "parentAndLedger"]) {
    const {f, request} = await ready(); const index = f.transactions.length; let changes = 0;
    let other;
    if (mode === "parentAndLedger") {
      other = fixture(); other.overrides.parent.writerFenceRevision = "c".repeat(64); other.overrides.ledger.writerFenceRevision = "c".repeat(64);
      await other.seed(); await other.completeParents();
    }
    f.hooks.beforeCommit = async (_trace, attempt) => {
      if (attempt !== 0) return; changes += 1;
      if (mode === "push") {f.overrides.push.writerFenceRevision = "c".repeat(64); f.hooks.retryCommits = 1;}
      else {
        f.overrides.parent.writerFenceRevision = "c".repeat(64); f.overrides.ledger.writerFenceRevision = "c".repeat(64);
        for (const id of [parentID(), ledgerID()]) f.documents.set(`${REQUESTS}/${id}`, clone(other.documents.get(`${REQUESTS}/${id}`)));
      }
    };
    await assert.rejects(() => f.push(request), (error) => error.code === "reader_boundary_changed");
    assert.equal(changes, 1); assert.ok(f.transactions.length >= index + 2); assert.deepEqual(writesSince(f, index), []);
    assert.equal(f.row().active.state, "active");
    if (other) for (const id of [parentID(), ledgerID()]) assert.deepEqual(f.documents.get(`${REQUESTS}/${id}`), other.documents.get(`${REQUESTS}/${id}`));
  }
});

test("caller-owned registry transaction requires a synchronous assertion guard for mutation and historical retry", async () => {
  const {f, request} = await ready();
  for (const beforeWrite of [undefined, async () => {}, () => false]) {
    const index = f.transactions.length;
    await rejectsUnchanged(f, () => f.db.runTransaction((transaction) =>
      f.registry.retireInTransaction(transaction, request.installation, registryClient, {beforeWrite})));
    assert.deepEqual(queuedWritesSince(f, index), []);
  }
  let assertions = 0; const beforeWrite = () => {assertions += 1;};
  const first = await f.db.runTransaction((transaction) => f.registry.retireInTransaction(transaction, request.installation, registryClient, {beforeWrite}));
  assert.equal(first.status, "retired"); assert.equal(assertions, 1); const index = f.transactions.length;
  const second = await f.db.runTransaction((transaction) => f.registry.retireInTransaction(transaction, request.installation, registryClient, {beforeWrite}));
  assert.deepEqual(second, first); assert.equal(assertions, 2); assert.deepEqual(queuedWritesSince(f, index), []);
});

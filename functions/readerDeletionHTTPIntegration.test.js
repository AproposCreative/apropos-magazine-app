// Actual HTTP -> identity verifier -> deletion stores/worker, entirely in memory.
// Trusted boundary values below are local test evidence, never deployment proof.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {createReaderDeletionEndpoint} = require("./readerDeletionEndpoint");
const {SCOPE, LEDGER_SCOPE, LEDGER_UNRESOLVED, MEMBERSHIPS, REQUESTS, UNRESOLVED, PAGE_SIZE} = require("./readerAccountDeletion");
const {SCOPE: MUTATION_SCOPE, RECEIPTS, REVISIONS, createReaderMutationStore} = require("./readerMutation");
const NOW = Date.parse("2026-10-25T12:00:00Z"), UID = "http_reader_a", OTHER = "http_reader_b";
const PROJECT = "fixture-project", APP = "1:123456789:ios:abcdef123456";
const clone = (value) => structuredClone(value);
const hash = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
const parentID = (uid = UID, epoch = 1) => hash([SCOPE, uid, epoch]);
const childID = (uid = UID, epoch = 1) => hash([LEDGER_SCOPE, parentID(uid, epoch), uid, epoch]);
const parentRequest = () => ({expectedUID: UID, membershipEpoch: 1});
const ledgerRequest = () => ({schemaVersion: 1, scope: LEDGER_SCOPE, expectedUID: UID, membershipEpoch: 1, parentRequestID: parentID()});

function fixture() {
  let time = NOW, sequence = 0, mutationSequence = 0, tail = Promise.resolve();
  const documents = new Map(), commits = [], queries = [], refs = [], authInputs = [], appInputs = [];
  const tokens = new Map(), consumed = new Set(), hooks = {};
  const calls = {services: 0, auth: 0, app: 0, user: 0, transactions: 0, boundary: 0, ledgerBoundary: 0};
  const snapshot = (path) => {
    const value = clone(documents.get(path));
    return {ref: {path}, exists: value !== undefined, data: () => clone(value)};
  };
  const reference = (path) => {refs.push(path);return {path};};
  const collection = (path, filters = [], limit) => ({queryPath: path, filters, count: limit,
    doc: (id) => reference(`${path}/${id}`),
    where: (field, op, value) => collection(path, [...filters, [field, op, value]], limit),
    limit: (value) => collection(path, filters, value)});
  const db = {projectId: PROJECT, databaseId: "(default)", collection,
    runTransaction: (body) => {
      calls.transactions++;
      const result = tail.then(async () => {
        const pending = [];let wrote = false;
        const tx = {
          get: async (ref) => {
            assert.equal(wrote, false, "Actual stores must complete reads before writing");
            if (!ref.queryPath) return snapshot(ref.path);
            queries.push({path: ref.queryPath, filters: clone(ref.filters), limit: ref.count});
            await hooks.query?.(ref);
            const prefix = `${ref.queryPath}/`;
            const docs = [...documents.keys()].filter((path) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
                .filter((path) => ref.filters.every(([field, op, value]) => {
                  assert.equal(op, "==");return documents.get(path)?.[field] === value;
                })).sort().slice(0, ref.count).map(snapshot);
            return {docs};
          },
          set: (ref, value) => {wrote = true;pending.push({path: ref.path, value: clone(value)});},
          delete: (ref) => {wrote = true;pending.push({path: ref.path, remove: true});},
        };
        const answer = await body(tx);
        for (const operation of pending) {
          if (operation.remove) documents.delete(operation.path);else documents.set(operation.path, operation.value);
        }
        commits.push(clone(pending));await hooks.afterCommit?.(pending);
        return answer;
      });
      tail = result.catch(() => {});return result;
    },
  };
  const commonProof = ({ownerUID, membershipEpoch}, scope) => ({schemaVersion: 1, scope, ownerUID, membershipEpoch,
    readerSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), validUntilMs: time + 60000,
    allowedPaths: [`users/${ownerUID}/favorites`, `users/${ownerUID}/preferences/reader`]});
  const verifyBoundary = async (binding) => {
    calls.boundary++;await hooks.boundary?.(binding);
    return {...commonProof(binding, SCOPE), unresolved: [...UNRESOLVED]};
  };
  const verifyLedgerBoundary = async (binding) => {
    calls.ledgerBoundary++;await hooks.ledgerBoundary?.(binding);
    return {schemaVersion: 1, scope: LEDGER_SCOPE, ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch,
      parentRequestID: binding.parentRequestID, mutationSchemaVersion: 1, writerFenceRevision: "a".repeat(64),
      migrationRevision: "b".repeat(64), validUntilMs: time + 60000, collections: [RECEIPTS, REVISIONS], unresolved: [...LEDGER_UNRESOLVED]};
  };
  const options = {config: {enabled: true, projectID: PROJECT, appID: APP, runtimeProjectID: PROJECT},
    now: () => time, verifyBoundary, verifyLedgerBoundary, createServices: async () => {
      calls.services++;await hooks.services?.();
      return {db, auth: {
        verifyIdToken: async (token, checkRevoked) => {
          calls.auth++;authInputs.push({token, checkRevoked});assert.equal(checkRevoked, true);
          const result = clone(tokens.get(token)?.claims);assert.ok(result, "Only explicitly minted local tokens are accepted");
          await hooks.auth?.();return result;
        },
        getUser: async (uid) => {calls.user++;await hooks.user?.();return {uid, disabled: false};},
      }, appCheck: {verifyToken: async (token, settings) => {
        calls.app++;appInputs.push({token, settings: clone(settings)});assert.deepEqual(settings, {consume: true});
        const minted = tokens.get(token);assert.ok(minted, "Only explicitly minted local App Check tokens are accepted");
        const result = clone(minted.app);result.alreadyConsumed = consumed.has(token);consumed.add(token);
        await hooks.app?.();return result;
      }}};
    }};
  function http(body = parentRequest(), change = {}) {
    const id = ++sequence, idToken = `local.auth.${id}`, appToken = `local.app.${id}`;
    const claims = {uid: UID, sub: UID, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
      auth_time: Math.floor(time / 1000) - 1, iat: Math.floor(time / 1000), exp: Math.floor(time / 1000) + 3600,
      firebase: {sign_in_provider: "apple.com"}, ...(change.claims || {})};
    const app = {alreadyConsumed: false, appId: APP, token: {sub: APP, app_id: APP,
      iss: "https://firebaseappcheck.googleapis.com/123456789", aud: [`projects/${PROJECT}`, "projects/123456789"],
      iat: Math.floor(time / 1000) - 1, exp: Math.floor(time / 1000) + 600, ...(change.appClaims || {})}};
    tokens.set(idToken, {claims});tokens.set(appToken, {app});
    return {method: "POST", query: {}, headers: {"content-type": "application/json; charset=utf-8",
      authorization: `Bearer ${idToken}`, "x-firebase-appcheck": appToken}, rawBody: Buffer.from(JSON.stringify(body))};
  }
  const call = (body = parentRequest(), maximumSteps = 4, change) => createReaderDeletionEndpoint({...options, maximumSteps})(http(body, change));
  const mutation = createReaderMutationStore({db, now: () => time,
    verifyBoundary: async (binding) => commonProof(binding, MUTATION_SCOPE)});
  async function seed(count = 2, uid = UID, epoch = 1) {
    documents.set(`${MEMBERSHIPS}/${uid}`, {schemaVersion: 1, ownerUID: uid, epoch, state: "active"});
    documents.set(`users/${uid}`, {displayName: "Shared profile", role: "editor", bookmarkedArticles: ["preserve"]});
    documents.set(`users/${uid}/preferences/research`, {draft: "Keep Research preferences"});
    documents.set(`users/${uid}/preferences/reader`, {interests: ["culture"]});
    documents.set(`research_articles/${uid}`, {editorialDraft: "preserve"});
    documents.set(`newsletter_subscribers/${uid}`, {consent: true});
    for (let index = 0; index < count; index++) {
      const number = ++mutationSequence;
      await mutation.commit({authorizationValidUntilMs: time + 600000, request: {schemaVersion: 1,
        expectedUID: uid, membershipEpoch: epoch, mutationID: `00000000-0000-4000-8000-${number.toString(16).padStart(12, "0")}`,
        expectedRevision: 0, kind: "favorite_set", payload: {id: `article-${number}`, pressAccreditation: false, name: "Local fixture article"}}});
    }
  }
  const rows = (collectionName) => [...documents].filter(([key]) => key.startsWith(`${collectionName}/`));
  const job = (id = parentID()) => documents.get(`${REQUESTS}/${id}`);
  return {documents, commits, queries, refs, calls, hooks, options, db, consumed, authInputs, appInputs,
    http, call, seed, rows, job, now: () => time, advance: (ms) => {time += ms;}};
}
function assertReceipt(response, scope, status) {
  assert.equal(response.status, 200);assert.equal(response.body.scope, scope);assert.equal(response.body.status, status);
  assert.equal(response.body.accountDeletionComplete, false);assert.equal(response.headers["cache-control"], "no-store");
  assert.equal(response.body.requestID, scope === SCOPE ? parentID() : childID());
  assert.deepEqual(response.body.unresolved, scope === SCOPE ? UNRESOLVED : LEDGER_UNRESOLVED);
}
function checkpoint(f) {return {documents: clone(f.documents), commits: f.commits.length, transactions: f.calls.transactions, refs: f.refs.length};}
function noDatabaseEffects(f, before) {
  assert.deepEqual(f.documents, before.documents);assert.equal(f.commits.length, before.commits);
  assert.equal(f.calls.transactions, before.transactions);assert.equal(f.refs.length, before.refs);
}

// Configuration/verifier presence gates the actual factory, not merely its writes.
test("deletion HTTP integration stays inert until both separate trusted boundaries are supplied", async () => {
  const f = fixture();await f.seed();const before = checkpoint(f);
  for (const override of [{config: {...f.options.config, enabled: false}}, {verifyBoundary: undefined}, {verifyLedgerBoundary: undefined}]) {
    const endpoint = createReaderDeletionEndpoint({...f.options, ...override});
    assert.equal(f.calls.services, 0);
    assert.equal((await endpoint(f.http())).status, 503);
    assert.equal((await endpoint(f.http(ledgerRequest()))).status, 503);
  }
  assert.equal(f.calls.services, 0);assert.equal(f.calls.auth, 0);noDatabaseEffects(f, before);
});

test("HTTP parent then explicit ledger cleanup preserves shared Research, nested and other owner/epoch data", async () => {
  const f = fixture();await f.seed(2);await f.seed(1, OTHER);await f.seed(1, UID, 2);
  f.documents.set(`${MEMBERSHIPS}/${UID}`, {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "active"});
  f.documents.set(`users/${UID}/favorites/legacy/nested/keep`, {unknown: "preserve"});
  const preserved = [...f.documents].filter(([path, value]) => path === `users/${UID}` || path.includes("/preferences/research") ||
    path.startsWith("research_articles/") || path.startsWith("newsletter_subscribers/") || path.includes(OTHER) ||
    path.endsWith("/nested/keep") || ([RECEIPTS, REVISIONS].some((name) => path.startsWith(`${name}/`)) && (value.membershipEpoch === 2 || value.ownerUID === OTHER)));
  const ledgerBefore = clone([...f.rows(RECEIPTS), ...f.rows(REVISIONS)]);
  const parent = await f.call();assertReceipt(parent, SCOPE, "scopedCloudDataRemoved");
  assert.deepEqual([...f.rows(RECEIPTS), ...f.rows(REVISIONS)], ledgerBefore, "Parent cleanup never implies ledger cleanup");
  assert.equal(f.job(childID()), undefined);assert.equal(f.documents.has(`users/${UID}/preferences/reader`), false);
  const parentJob = clone(f.job()), frozenMember = clone(f.documents.get(`${MEMBERSHIPS}/${UID}`));
  const child = await f.call(ledgerRequest());assertReceipt(child, LEDGER_SCOPE, "ledgerDataRemoved");
  assert.equal(child.body.parentRequestID, parentID());assert.equal(child.body.removedReceiptDocuments, 2);
  assert.equal(child.body.removedRevisionDocuments, 2);
  assert.deepEqual(f.job(), parentJob);assert.deepEqual(f.documents.get(`${MEMBERSHIPS}/${UID}`), frozenMember);
  for (const [path, value] of preserved) assert.deepEqual(f.documents.get(path), value, path);
  const queries = f.queries.filter(({path}) => [RECEIPTS, REVISIONS].includes(path));assert.ok(queries.length > 0);
  for (const query of queries) {assert.deepEqual(query.filters, [["ownerUID", "==", UID], ["membershipEpoch", "==", 1]]);assert.equal(query.limit, PAGE_SIZE);}
});

test("bounded HTTP parent retries reauthenticate and resume one durable job without restarting counts", async () => {
  const f = fixture();await f.seed(PAGE_SIZE + 2);
  const first = await f.call(parentRequest(), 1);assertReceipt(first, SCOPE, "pending");
  assert.equal(f.job().removedFavoriteDocuments, PAGE_SIZE);
  assert.equal(Object.hasOwn(first.body, "removedFavoriteDocuments"), false, "Bounded worker outcome is not a full completion receipt");
  const before = checkpoint(f);f.advance(301000);
  const stale = await createReaderDeletionEndpoint({...f.options, maximumSteps: 1})(f.http(parentRequest(), {claims: {auth_time: NOW / 1000 - 1}}));
  assert.equal(stale.status, 401);noDatabaseEffects(f, before);
  const second = await f.call(parentRequest(), 1);assertReceipt(second, SCOPE, "pending");
  assert.equal(f.job().removedFavoriteDocuments, PAGE_SIZE + 2);
  const last = await f.call(parentRequest(), 1);assertReceipt(last, SCOPE, "scopedCloudDataRemoved");
  assert.equal(last.body.removedFavoriteDocuments, PAGE_SIZE + 2);assert.equal(f.calls.auth, 4);
  assert.equal(new Set(f.authInputs.map(({token}) => token)).size, 4);
  assert.equal(new Set(f.appInputs.map(({token}) => token)).size, 4);
});

test("pending parent blocks ledger HTTP admission without mutating the accepted parent or either ledger", async () => {
  const f = fixture();await f.seed(2);assertReceipt(await f.call(parentRequest(), 1), SCOPE, "pending");
  const before = clone(f.documents), commits = f.commits.length;
  const result = await f.call(ledgerRequest());assert.equal(result.status, 409);
  assert.equal(result.body.error, "parent_cleanup_required");assert.deepEqual(f.documents, before);assert.equal(f.commits.length, commits);
  assert.equal(f.job(childID()), undefined);
});

test("bounded ledger HTTP calls retain parent and original child through both phases and terminal retry", async () => {
  const f = fixture();await f.seed(2);assertReceipt(await f.call(), SCOPE, "scopedCloudDataRemoved");
  const parent = clone(f.job()), member = clone(f.documents.get(`${MEMBERSHIPS}/${UID}`));
  const expected = [["receipts", 2, 0], ["revisions", 2, 0], ["revisions", 2, 2], ["complete", 2, 2]];
  for (const [phase, receiptCount, revisionCount] of expected) {
    f.advance(1000);const response = await f.call(ledgerRequest(), 1);
    assertReceipt(response, LEDGER_SCOPE, phase === "complete" ? "ledgerDataRemoved" : "pending");
    assert.equal(f.job(childID()).phase, phase);assert.equal(f.job(childID()).removedReceiptDocuments, receiptCount);
    assert.equal(f.job(childID()).removedRevisionDocuments, revisionCount);
    assert.deepEqual(f.job(), parent);assert.deepEqual(f.documents.get(`${MEMBERSHIPS}/${UID}`), member);
  }
  const queryCount = f.queries.length, deleteCount = f.commits.flat().filter((op) => op.remove).length;
  const terminal = await f.call(ledgerRequest(), 1);assertReceipt(terminal, LEDGER_SCOPE, "ledgerDataRemoved");
  assert.equal(terminal.body.parentRequestID, parentID());assert.equal(terminal.body.removedReceiptDocuments, 2);
  assert.equal(f.queries.length, queryCount, "Terminal admission returns its receipt without executing the worker again");
  assert.equal(f.commits.flat().filter((op) => op.remove).length, deleteCount);
});

test("consumed App Check token cannot reuse even a completed HTTP deletion receipt", async () => {
  const f = fixture();await f.seed();const request = f.http(), endpoint = createReaderDeletionEndpoint(f.options);
  assertReceipt(await endpoint(request), SCOPE, "scopedCloudDataRemoved");
  const before = checkpoint(f), authCalls = f.calls.auth;
  assert.equal((await endpoint(request)).status, 401);noDatabaseEffects(f, before);assert.equal(f.calls.auth, authCalls);
  assertReceipt(await f.call(), SCOPE, "scopedCloudDataRemoved");
});

test("worker boundary outage yields a bounded paused receipt and a freshly authenticated retry resumes", async () => {
  const f = fixture();await f.seed(2);
  f.hooks.boundary = () => {if (f.calls.boundary === 2) throw new Error("PRIVATE VERIFIER DETAIL");};
  const result = await f.call();assertReceipt(result, SCOPE, "paused");
  assert.equal(result.body.code, "transport_unavailable");assert.equal(JSON.stringify(result).includes("PRIVATE"), false);
  assert.equal(f.job().status, "pending");assert.equal(f.job().removedFavoriteDocuments, 0);
  assert.equal(f.rows(RECEIPTS).length, 2);delete f.hooks.boundary;f.advance(1000);
  const retry = await f.call();assertReceipt(retry, SCOPE, "scopedCloudDataRemoved");assert.equal(retry.body.removedFavoriteDocuments, 2);
  assert.equal(f.calls.auth, 2);
});

test("lost physical commit reply and discarded HTTP success resume without duplicate deletion or new jobs", async () => {
  const f = fixture();await f.seed(2);let lost = false;
  f.hooks.afterCommit = (operations) => {
    if (!lost && operations.some((operation) => operation.remove)) {lost = true;throw new Error("PRIVATE LOST REPLY");}
  };
  const uncertain = await f.call();assertReceipt(uncertain, SCOPE, "paused");
  assert.equal(f.job().removedFavoriteDocuments, 2);assert.equal(uncertain.body.code, "transport_unavailable");
  delete f.hooks.afterCommit;
  const discarded = await f.call();assertReceipt(discarded, SCOPE, "scopedCloudDataRemoved");
  const before = clone(f.documents), deleteCount = f.commits.flat().filter((op) => op.remove).length;
  const resumed = await f.call();assertReceipt(resumed, SCOPE, "scopedCloudDataRemoved");
  assert.equal(resumed.body.requestID, uncertain.body.requestID);assert.equal(resumed.body.removedFavoriteDocuments, 2);
  assert.deepEqual(f.documents, before);assert.equal(f.commits.flat().filter((op) => op.remove).length, deleteCount);
  assert.equal(f.rows(REQUESTS).length, 1);assert.equal(f.job(childID()), undefined);
  let childLost = false;
  f.hooks.afterCommit = (operations) => {
    if (!childLost && operations.some((operation) => operation.remove && operation.path.startsWith(`${RECEIPTS}/`))) {
      childLost = true;throw new Error("PRIVATE LEDGER LOST REPLY");
    }
  };
  const uncertainChild = await f.call(ledgerRequest());assertReceipt(uncertainChild, LEDGER_SCOPE, "paused");
  assert.equal(f.job(childID()).removedReceiptDocuments, 2);delete f.hooks.afterCommit;
  const recoveredChild = await f.call(ledgerRequest());assertReceipt(recoveredChild, LEDGER_SCOPE, "ledgerDataRemoved");
  assert.equal(recoveredChild.body.removedReceiptDocuments, 2);assert.equal(recoveredChild.body.removedRevisionDocuments, 2);
  assert.equal(f.rows(REQUESTS).length, 2);assert.deepEqual(f.job(), before.get(`${REQUESTS}/${parentID()}`));
});

test("original parsed HTTP body and credentials cannot be redirected while identity verification awaits", async () => {
  const f = fixture();await f.seed(2);await f.seed(1, OTHER);
  const beforeOther = [...f.documents].filter(([path]) => path.includes(OTHER));
  const request = f.http();let ran = false;
  f.hooks.auth = () => {
    ran = true;request.rawBody = Buffer.from(JSON.stringify({expectedUID: OTHER, membershipEpoch: 1}));
    request.headers.authorization = "Bearer foreign.token";request.body = ledgerRequest();
  };
  const result = await createReaderDeletionEndpoint(f.options)(request);assert.equal(ran, true);
  assertReceipt(result, SCOPE, "scopedCloudDataRemoved");
  for (const [path, value] of beforeOther) assert.deepEqual(f.documents.get(path), value, path);
  assert.equal(f.job(parentID(OTHER)), undefined);assert.equal(f.authInputs[0].token, "local.auth.1");
});

test("same UID newer membership epoch cannot borrow an old terminal parent or child receipt", async () => {
  const f = fixture();await f.seed();assertReceipt(await f.call(), SCOPE, "scopedCloudDataRemoved");
  assertReceipt(await f.call(ledgerRequest()), LEDGER_SCOPE, "ledgerDataRemoved");
  f.documents.set(`${MEMBERSHIPS}/${UID}`, {schemaVersion: 1, ownerUID: UID, epoch: 2, state: "active"});
  const before = clone(f.documents), commits = f.commits.length;
  for (const request of [parentRequest(), ledgerRequest()]) {
    const response = await f.call(request);assert.equal(response.status, 409);assert.equal(response.body.error, "reader_membership_mismatch");
  }
  assert.deepEqual(f.documents, before);assert.equal(f.commits.length, commits);
});

test("HTTP expiry after physical mutation is an unknown outcome and fresh retry reconciles the durable job", async () => {
  const f = fixture();await f.seed(2);let expired = false;
  f.hooks.afterCommit = (operations) => {
    if (!expired && operations.some((operation) => operation.remove)) {expired = true;f.advance(3000);}
  };
  const request = f.http(parentRequest(), {appClaims: {exp: NOW / 1000 + 2}});
  const result = await createReaderDeletionEndpoint({...f.options, maximumSteps: 1})(request);
  assert.equal(result.status, 401);assert.equal(f.job().removedFavoriteDocuments, 2);
  assert.equal(f.job().status, "pending");assert.equal(f.documents.has(`users/${UID}/preferences/reader`), true);
  delete f.hooks.afterCommit;
  const fresh = await f.call();assertReceipt(fresh, SCOPE, "scopedCloudDataRemoved");assert.equal(fresh.body.removedFavoriteDocuments, 2);
});

test("tenant collision or identity expiry during verification cannot create a deletion job", async () => {
  const f = fixture();await f.seed();const before = checkpoint(f);
  const tenant = f.http(parentRequest(), {claims: {firebase: {sign_in_provider: "apple.com", tenant: "colliding-tenant"}}});
  assert.equal((await createReaderDeletionEndpoint(f.options)(tenant)).status, 401);noDatabaseEffects(f, before);
  const delayed = f.http(parentRequest(), {appClaims: {exp: Math.floor(f.now() / 1000) + 1}});
  f.hooks.user = () => f.advance(1001);
  assert.equal((await createReaderDeletionEndpoint(f.options)(delayed)).status, 401);noDatabaseEffects(f, before);
});

for (const ledger of [false, true]) test(`App Check expiry during actual ${ledger ? "ledger" : "favorites"} query cannot commit deletion or checkpoint`, async () => {
  const f = fixture();await f.seed(PAGE_SIZE + 2);
  if (ledger) assertReceipt(await f.call(), SCOPE, "scopedCloudDataRemoved");
  const input = ledger ? ledgerRequest() : parentRequest(), scope = ledger ? LEDGER_SCOPE : SCOPE;
  assertReceipt(await f.call(input, 1), scope, "pending");
  const id = ledger ? childID() : parentID(), originalJob = clone(f.job(id));
  const before = clone(f.documents), commits = f.commits.length, queryCount = f.queries.length;
  let awaited = false;
  f.hooks.query = async (query) => {
    assert.equal(query.queryPath, ledger ? RECEIPTS : `users/${UID}/favorites`);
    await Promise.resolve();awaited = true;f.advance(3000);
  };
  const request = f.http(input, {appClaims: {exp: Math.floor(f.now() / 1000) + 2}});
  const result = await createReaderDeletionEndpoint({...f.options, maximumSteps: 1})(request);
  assert.equal(awaited, true);assert.equal(f.queries.length, queryCount + 1);
  assert.equal(result.status, 401);assert.deepEqual(f.documents, before);assert.deepEqual(f.job(id), originalJob);
  // The idempotent admission may complete a read-only transaction. Neither its
  // worker nor the expired query may commit a delete or checkpoint update.
  assert.deepEqual(f.commits.slice(commits).flat(), []);
  delete f.hooks.query;
  const recovered = await f.call(input, 20);assertReceipt(recovered, scope, ledger ? "ledgerDataRemoved" : "scopedCloudDataRemoved");
  if (ledger) {
    assert.equal(recovered.body.removedReceiptDocuments, PAGE_SIZE + 2);
    assert.equal(recovered.body.removedRevisionDocuments, PAGE_SIZE + 2);
  } else assert.equal(recovered.body.removedFavoriteDocuments, PAGE_SIZE + 2);
});

test("App Check expiry while either trusted boundary awaits cannot admit or resume physical writes", async () => {
  for (const ledger of [false, true]) {
    const f = fixture();await f.seed(2);
    if (ledger) assertReceipt(await f.call(), SCOPE, "scopedCloudDataRemoved");
    const input = ledger ? ledgerRequest() : parentRequest(), scope = ledger ? LEDGER_SCOPE : SCOPE;
    assertReceipt(await f.call(input, 1), scope, "pending");
    const before = clone(f.documents), commits = f.commits.length, queryCount = f.queries.length;
    let awaited = false;
    const hook = ledger ? "ledgerBoundary" : "boundary";
    f.hooks[hook] = async () => {await Promise.resolve();awaited = true;f.advance(3000);};
    const request = f.http(input, {appClaims: {exp: Math.floor(f.now() / 1000) + 2}});
    const result = await createReaderDeletionEndpoint({...f.options, maximumSteps: 1})(request);
    assert.equal(awaited, true);assert.equal(result.status, 401);
    assert.deepEqual(f.documents, before);assert.equal(f.commits.length, commits);assert.equal(f.queries.length, queryCount);
    delete f.hooks[hook];
    assertReceipt(await f.call(input), scope, ledger ? "ledgerDataRemoved" : "scopedCloudDataRemoved");
  }
});

// Hermetic behavior of the actual mutation and deletion stores. The database
// below is memory-only; no Firebase module, credential, service or endpoint.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {SCOPE, LEDGER_SCOPE, LEDGER_UNRESOLVED, MEMBERSHIPS, REQUESTS, UNRESOLVED, PAGE_SIZE,
  createReaderAccountDeletionStore, beginReaderAccountDeletion, runReaderAccountDeletion} = require("./readerAccountDeletion");
const {SCOPE: MUTATION_SCOPE, RECEIPTS, REVISIONS, createReaderMutationStore} = require("./readerMutation");
const NOW = Date.parse("2026-10-25T12:00:00Z"), UID = "ledger_reader_a", APP = "verified-ios-app";
const clone = (value) => structuredClone(value);
const hash = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
const parentID = (uid = UID, epoch = 1) => hash([SCOPE, uid, epoch]);
const childID = (uid = UID, epoch = 1) => hash([LEDGER_SCOPE, parentID(uid, epoch), uid, epoch]);
const request = (uid = UID, epoch = 1) => ({schemaVersion: 1, scope: LEDGER_SCOPE,
  expectedUID: uid, membershipEpoch: epoch, parentRequestID: parentID(uid, epoch)});
const code = (value) => (error) => error.code === value && error.message === value;

function fixture() {
  const documents = new Map(), reads = [], queries = [], commits = [], references = [];
  let nowMs = NOW, tail = Promise.resolve(), transactionCalls = 0, mutationSequence = 0;
  let retryHook, queryHook, beforeTransaction, ledgerProofHook, injectedPage;
  let failCommit = false, loseResponse = false, ledgerOverride = {};
  let ledgerVerifierCalls = 0, identityVerifierCalls = 0, beginLedgerCalls = 0;
  const reference = (path) => {references.push(path);return {path};};
  const snapshot = (path) => {
    const value = clone(documents.get(path));
    return {ref: {path}, exists: value !== undefined, data: () => clone(value)};
  };
  const collection = (queryPath, filters = [], count) => ({queryPath, filters, count,
    doc: (id) => reference(`${queryPath}/${id}`),
    where: (field, operator, value) => collection(queryPath, [...filters, [field, operator, value]], count),
    limit: (limit) => collection(queryPath, filters, limit)});
  const db = {
    collection,
    runTransaction: (callback) => {
      transactionCalls += 1;
      const result = tail.then(async () => {
        if (beforeTransaction) {const hook = beforeTransaction;beforeTransaction = undefined;await hook();}
        let wrote = false;const pending = [];
        const transaction = {
          get: async (ref) => {
            assert.equal(wrote, false, "Every transaction must finish reads before writes");
            reads.push(ref.path ?? ref.queryPath);
            if (!ref.queryPath) return snapshot(ref.path);
            queries.push({collection: ref.queryPath, filters: clone(ref.filters), limit: ref.count});
            if (queryHook) {const hook = queryHook;queryHook = undefined;await hook();}
            const prefix = ref.queryPath + "/";
            const docs = [...documents.keys()].filter((key) => key.startsWith(prefix) && !key.slice(prefix.length).includes("/"))
                .filter((key) => ref.filters.every(([field, operator, value]) => {
                  assert.equal(operator, "==");return documents.get(key)?.[field] === value;
                })).sort().slice(0, ref.count).map(snapshot);
            return injectedPage ? injectedPage({query: ref, docs}) : {docs};
          },
          set: (ref, value) => {wrote = true;pending.push({path: ref.path, value: clone(value)});},
          delete: (ref) => {wrote = true;pending.push({path: ref.path, remove: true});},
        };
        let result = await callback(transaction);
        if (retryHook) {
          const hook = retryHook;retryHook = undefined;pending.length = 0;wrote = false;
          await hook();result = await callback(transaction);
        }
        if (failCommit) {failCommit = false;throw new Error("PRIVATE COMMIT DETAIL");}
        for (const operation of pending) {
          if (operation.remove) documents.delete(operation.path);else documents.set(operation.path, operation.value);
        }
        commits.push(clone(pending));
        if (loseResponse) {loseResponse = false;throw new Error("PRIVATE RESPONSE DETAIL");}
        return result;
      });
      tail = result.catch(() => {});return result;
    },
  };
  const v1Proof = ({ownerUID, membershipEpoch}) => ({schemaVersion: 1, scope: SCOPE, ownerUID, membershipEpoch,
    readerSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), validUntilMs: nowMs + 60000,
    allowedPaths: [`users/${ownerUID}/favorites`, `users/${ownerUID}/preferences/reader`], unresolved: [...UNRESOLVED]});
  const ledgerProof = async (binding) => {
    ledgerVerifierCalls += 1;
    assert.equal(binding.scope, LEDGER_SCOPE);assert.equal(typeof binding.transaction.get, "function");
    const result = {schemaVersion: 1, scope: LEDGER_SCOPE, ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch,
      parentRequestID: binding.parentRequestID, mutationSchemaVersion: 1, writerFenceRevision: "a".repeat(64),
      migrationRevision: "b".repeat(64), validUntilMs: nowMs + 60000, collections: [RECEIPTS, REVISIONS], unresolved: [...LEDGER_UNRESOLVED], ...ledgerOverride};
    if (ledgerProofHook) {const hook = ledgerProofHook;ledgerProofHook = undefined;await hook();}
    return result;
  };
  let store;
  function reopen({ledger = true, v1 = true, ledgerUsesV1Proof = false} = {}) {
    const actual = createReaderAccountDeletionStore({db, now: () => nowMs,
      ...(v1 ? {verifyBoundary: async (binding) => v1Proof(binding)} : {}),
      ...(ledger ? {verifyLedgerBoundary: ledgerUsesV1Proof ? async (binding) => v1Proof(binding) : ledgerProof} : {})});
    store = {...actual, beginLedger: (binding) => {beginLedgerCalls += 1;return actual.beginLedger(binding);}};
    return store;
  }
  reopen();
  const identity = () => ({uid: UID, appID: APP, authTimeMs: nowMs - 1000, issuedAtMs: nowMs - 500, expiresAtMs: nowMs + 600000});
  const begin = (input = request(), auth = identity()) => beginReaderAccountDeletion({store,
    verifyClient: async () => {identityVerifierCalls += 1;return auth;}, expectedAppID: APP, request: input, now: () => nowMs});
  const run = (id = childID(), maximumSteps = 10) => runReaderAccountDeletion({store, requestID: id, maximumSteps, scope: LEDGER_SCOPE});
  const mutationStore = createReaderMutationStore({db, now: () => nowMs, verifyBoundary: async (binding) => ({
    schemaVersion: 1, scope: MUTATION_SCOPE, ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch,
    readerSchemaVersion: 1, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), validUntilMs: nowMs + 60000,
    allowedPaths: [`users/${binding.ownerUID}/favorites`, `users/${binding.ownerUID}/preferences/reader`],
  })});
  async function seed(count = 2, uid = UID, epoch = 1) {
    documents.set(`${MEMBERSHIPS}/${uid}`, {schemaVersion: 1, ownerUID: uid, epoch, state: "active"});
    documents.set(`users/${uid}`, {displayName: "Shared", bookmarkedArticles: ["legacy"], role: "editor"});
    documents.set(`users/${uid}/preferences/research`, {privateDraft: "preserve"});
    documents.set(`research_articles/${uid}`, {private: true});
    documents.set(`newsletter_subscribers/${uid}`, {consent: true});
    for (let index = 0; index < count; index += 1) {
      mutationSequence += 1;
      const articleID = `article-${uid}-${epoch}-${String(mutationSequence).padStart(4, "0")}`;
      await mutationStore.commit({authorizationValidUntilMs: nowMs + 600000, request: {
        schemaVersion: 1, expectedUID: uid, membershipEpoch: epoch,
        mutationID: `00000000-0000-4000-8000-${mutationSequence.toString(16).padStart(12, "0")}`,
        expectedRevision: 0, kind: "favorite_set", payload: {id: articleID, pressAccreditation: false, name: "Local article"},
      }});
    }
  }
  async function completeParent() {
    const accepted = await begin({expectedUID: UID, membershipEpoch: 1});
    const done = await runReaderAccountDeletion({store, requestID: accepted.requestID, maximumSteps: 20});
    assert.equal(done.status, "scopedCloudDataRemoved");return done;
  }
  return {documents, reads, queries, commits, references, db, identity, begin, run, seed, completeParent, reopen,
    get store() {return store;}, now: () => nowMs,
    metrics: () => ({references: references.length, reads: reads.length, transactions: transactionCalls, commits: commits.length,
      ledgerVerifierCalls, identityVerifierCalls, beginLedgerCalls}),
    member: () => documents.get(`${MEMBERSHIPS}/${UID}`), parent: () => documents.get(`${REQUESTS}/${parentID()}`),
    job: () => documents.get(`${REQUESTS}/${childID()}`),
    advance: (ms) => {nowMs += ms;}, override: (value) => {ledgerOverride = value;},
    beforeQuery: (hook) => {queryHook = hook;}, beforeProof: (hook) => {ledgerProofHook = hook;},
    beforeTransaction: (hook) => {beforeTransaction = hook;}, retry: (hook = () => {}) => {retryHook = hook;},
    page: (value) => {injectedPage = value;}, failCommit: () => {failCommit = true;}, loseResponse: () => {loseResponse = true;},
    ledgerRows: (collectionName) => [...documents].filter(([key]) => key.startsWith(collectionName + "/")),
  };
}
async function ready(count = 2) {const f = fixture();await f.seed(count);await f.completeParent();return f;}
function checkpoint(f) {return {documents: clone(f.documents), commits: clone(f.commits), metrics: f.metrics()};}
function untouched(f, before) {
  assert.deepEqual(f.documents, before.documents);assert.deepEqual(f.commits, before.commits);
}
function noDatabaseEffects(f, before) {
  untouched(f, before);
  for (const key of ["references", "reads", "transactions"]) assert.equal(f.metrics()[key], before.metrics[key], key);
}
async function atRevisions(f) {
  while (f.job().phase === "receipts") {
    const result = await f.run(childID(), 1);assert.equal(result.status, "pending");
  }
  assert.equal(f.job().phase, "revisions");
}

test("explicit ledger admission creates a separately bound child without changing parent or frozen membership", async () => {
  const f = await ready(), parent = clone(f.parent()), member = clone(f.member()), before = f.commits.length;
  const accepted = await f.begin();
  assert.equal(accepted.requestID, childID());assert.notEqual(accepted.requestID, parentID());
  assert.equal(accepted.parentRequestID, parentID());assert.equal(accepted.scope, LEDGER_SCOPE);
  assert.equal(accepted.status, "pending");assert.equal(accepted.accountDeletionComplete, false);
  assert.deepEqual(accepted.unresolved, LEDGER_UNRESOLVED);
  assert.equal(accepted.removedReceiptDocuments, 0);assert.equal(accepted.removedRevisionDocuments, 0);
  assert.equal(f.job().parentBoundaryFingerprint, parent.boundaryFingerprint);assert.equal(f.job().phase, "receipts");
  assert.deepEqual(f.parent(), parent);assert.deepEqual(f.member(), member);
  assert.deepEqual(f.commits.slice(before).flat().map((op) => op.path), [`${REQUESTS}/${childID()}`]);
});

test("missing separate ledger verifier fails before references; old v1 proof cannot authorize ledger cleanup", async () => {
  for (const options of [{ledger: false}, {ledgerUsesV1Proof: true}]) {
    const f = await ready();f.reopen(options);const before = checkpoint(f);
    await assert.rejects(f.begin(), code(options.ledger === false ? "reader_boundary_unavailable" : "reader_boundary_unverified"));
    if (options.ledger === false) noDatabaseEffects(f, before);else untouched(f, before);
  }
});

test("ledger requests are strict and malformed scope, parent or client-selected paths never reach verifier", async () => {
  const invalid = [null, [], {...request(), schemaVersion: 2}, {...request(), scope: "unknown"},
    {...request(), parentRequestID: "c".repeat(64)}, {...request(), path: `users/${UID}`}, {...request(), membershipEpoch: 0}];
  for (const input of invalid) {
    const f = await ready(), before = checkpoint(f);
    await assert.rejects(f.begin(input), code("invalid_request"));
    noDatabaseEffects(f, before);assert.equal(f.metrics().identityVerifierCalls, before.metrics.identityVerifierCalls);
    assert.equal(f.metrics().beginLedgerCalls, before.metrics.beginLedgerCalls);
  }
});

test("ledger identity remains in the default Firebase namespace with recent reauthentication", async () => {
  for (const change of [(value) => ({...value, tenantID: "colliding-tenant"}), (value) => ({...value, tenantID: ""}),
    (value) => ({...value, uid: "other-reader"}), (value) => ({...value, appID: "different-app"})]) {
    const f = await ready(), before = checkpoint(f);
    await assert.rejects(f.begin(request(), change(f.identity())), code("identity_mismatch"));
    noDatabaseEffects(f, before);assert.equal(f.metrics().beginLedgerCalls, before.metrics.beginLedgerCalls);
  }
  const f = await ready(), before = checkpoint(f);
  await assert.rejects(f.begin(request(), {...f.identity(), authTimeMs: f.now() - 300001}), code("recent_authentication_required"));
  noDatabaseEffects(f, before);
  const absent = await f.begin(), nullable = await f.begin(request(), {...f.identity(), tenantID: null});
  assert.equal(absent.requestID, nullable.requestID);
});

test("request binding is copied before verifier await and cannot be redirected during verification", async () => {
  const f = await ready(), input = request();let deliver;
  const verified = new Promise((resolve) => {deliver = resolve;});
  const pending = beginReaderAccountDeletion({store: f.store, expectedAppID: APP, request: input,
    verifyClient: () => verified, now: f.now});
  input.expectedUID = "other-reader";input.membershipEpoch = 2;input.parentRequestID = parentID("other-reader", 2);input.scope = SCOPE;
  deliver(f.identity());
  const result = await pending;
  assert.equal(result.requestID, childID());assert.equal(result.parentRequestID, parentID());
  assert.equal(f.job().ownerUID, UID);assert.equal(f.job().membershipEpoch, 1);
});

test("missing, incomplete or wrong parent and unfrozen membership cannot admit the child", async () => {
  const cases = [
    ["missing", (f) => f.documents.delete(`${REQUESTS}/${parentID()}`), "invalid_deletion_record"],
    ["pending", (f) => {f.parent().status = "pending";}, "parent_cleanup_required"],
    ["wrong owner", (f) => {f.parent().ownerUID = "other-reader";}, "invalid_deletion_record"],
    ["wrong epoch", (f) => {f.parent().membershipEpoch = 2;}, "invalid_deletion_record"],
    ["active membership", (f) => {f.member().state = "active";}, "reader_membership_mismatch"],
    ["new membership", (f) => {f.member().epoch = 2;}, "reader_membership_mismatch"],
    ["other freeze", (f) => {f.member().deletionRequestID = "c".repeat(64);}, "reader_membership_mismatch"],
  ];
  for (const [name, alter, expected] of cases) {
    const f = await ready();alter(f);const before = checkpoint(f);
    await assert.rejects(f.begin(), code(expected), name);untouched(f, before);
  }
});

test("bounded receipt and revision phases resume from durable jobs after store recreation", async () => {
  const count = PAGE_SIZE + 2, f = await ready(count);await f.begin();
  const parent = clone(f.parent()), member = clone(f.member()), start = f.commits.length;
  assert.equal((await f.run(childID(), 1)).status, "pending");
  assert.equal(f.job().phase, "receipts");assert.equal(f.job().removedReceiptDocuments, PAGE_SIZE);
  f.reopen();await f.run(childID(), 1);
  assert.equal(f.job().phase, "receipts");assert.equal(f.job().removedReceiptDocuments, count);
  assert.equal(f.ledgerRows(RECEIPTS).length, 0);assert.equal(f.ledgerRows(REVISIONS).length, count);
  await f.run(childID(), 1);assert.equal(f.job().phase, "revisions");
  f.reopen();await f.run(childID(), 1);assert.equal(f.job().removedRevisionDocuments, PAGE_SIZE);
  f.reopen();await f.run(childID(), 1);assert.equal(f.job().removedRevisionDocuments, count);
  assert.equal(f.job().status, "pending", "An emptied page is not yet the separate empty-query completion");
  const completed = await f.run(childID(), 1);
  assert.equal(completed.status, "ledgerDataRemoved");assert.equal(f.job().phase, "complete");
  assert.equal(completed.removedReceiptDocuments, count);assert.equal(completed.removedRevisionDocuments, count);
  assert.equal(completed.parentRequestID, parentID());assert.equal(completed.accountDeletionComplete, false);
  assert.deepEqual(completed.unresolved, LEDGER_UNRESOLVED);
  assert.deepEqual(f.parent(), parent);assert.deepEqual(f.member(), member);
  assert.ok(f.commits.slice(start).every((ops) => ops.filter((op) => op.remove).length <= PAGE_SIZE));
  const ledgerQueries = f.queries.filter((query) => [RECEIPTS, REVISIONS].includes(query.collection));
  assert.ok(ledgerQueries.length >= 6);
  for (const query of ledgerQueries) {
    assert.deepEqual(query.filters, [["ownerUID", "==", UID], ["membershipEpoch", "==", 1]]);
    assert.equal(query.limit, PAGE_SIZE);
  }
});

test("lost physical page response preserves checkpoint and retry does not recount or replay deleted rows", async () => {
  for (const phase of ["receipts", "revisions"]) {
    const f = await ready(3);await f.begin();if (phase === "revisions") await atRevisions(f);
    f.loseResponse();const lost = await f.run(childID(), 1);
    assert.equal(lost.status, "paused");assert.equal(lost.code, "transport_unavailable");
    assert.equal(JSON.stringify(lost).includes("PRIVATE"), false);
    assert.equal(f.job()[phase === "receipts" ? "removedReceiptDocuments" : "removedRevisionDocuments"], 3);
    f.reopen();const result = await f.run();
    assert.equal(result.status, "ledgerDataRemoved");assert.equal(result.removedReceiptDocuments, 3);assert.equal(result.removedRevisionDocuments, 3);
  }
});

test("failed commit leaves whole page and phase checkpoint unchanged in either ledger", async () => {
  for (const phase of ["receipts", "revisions"]) {
    const f = await ready(3);await f.begin();if (phase === "revisions") await atRevisions(f);
    const before = checkpoint(f);f.failCommit();const result = await f.run(childID(), 1);
    assert.equal(result.status, "paused");assert.equal(result.code, "transport_unavailable");untouched(f, before);
    assert.equal((await f.run()).status, "ledgerDataRemoved");
  }
});

test("only exact original owner and epoch ledgers are removed; shared, Research, parent and other ledgers survive", async () => {
  const f = await ready(2), foreign = fixture();
  await foreign.seed(2, "reader_b", 1);await foreign.seed(2, UID, 2);
  for (const collection of [RECEIPTS, REVISIONS]) {
    for (const [key, row] of foreign.ledgerRows(collection)) f.documents.set(key, clone(row));
  }
  f.documents.set(`${RECEIPTS}/legacy-unlabelled`, {preserveUnknown: true});
  f.documents.set(`${REVISIONS}/legacy-unlabelled`, {preserveUnknown: true});
  f.documents.set(`${RECEIPTS}/nested/unknown/child`, {preserveNested: true});
  const preserved = new Map([...f.documents].filter(([key, row]) =>
    !([RECEIPTS, REVISIONS].some((collection) => key.startsWith(collection + "/")) && row.ownerUID === UID && row.membershipEpoch === 1)));
  await f.begin();const result = await f.run();assert.equal(result.status, "ledgerDataRemoved");
  for (const [key, value] of preserved) assert.deepEqual(f.documents.get(key), value, key);
  assert.equal(result.removedReceiptDocuments, 2);assert.equal(result.removedRevisionDocuments, 2);
});

test("old v1 worker never implicitly cleans ledgers and omitted child scope cannot select ledger deletion", async () => {
  const f = fixture();await f.seed(2);
  const ledgers = new Map([...f.ledgerRows(RECEIPTS), ...f.ledgerRows(REVISIONS)]);
  await f.completeParent();
  for (const [key, value] of ledgers) assert.deepEqual(f.documents.get(key), value);
  await f.begin();const before = checkpoint(f);
  const result = await runReaderAccountDeletion({store: f.store, requestID: childID()});
  assert.equal(result.scope, SCOPE);assert.equal(result.status, "paused");assert.equal(result.code, "invalid_deletion_record");
  untouched(f, before);
});

test("bad adapter references and duplicate IDs reject the entire page before any delete", async () => {
  for (const phase of ["receipts", "revisions"]) {
    for (const mode of ["foreign path", "nested path", "duplicate"]) {
      const f = await ready(2);await f.begin();if (phase === "revisions") await atRevisions(f);
      f.page(({docs}) => {
        if (mode === "duplicate") return {docs: [docs[0], docs[0]]};
        const path = mode === "foreign path" ? `users/${UID}` : docs[0].ref.path + "/private/child";
        return {docs: [docs[0], {ref: {path}, data: docs[1].data}]};
      });
      const before = checkpoint(f), result = await f.run(childID(), 1);
      assert.equal(result.code, "invalid_cleanup_path", `${phase}: ${mode}`);untouched(f, before);
    }
  }
});

test("a malformed or foreign receipt behind a valid query rolls back all candidate deletes", async () => {
  for (const alter of [(row) => {row.ownerUID = "reader_b";}, (row) => {row.membershipEpoch = 2;},
    (row) => {row.receipt.committedRevision += 1;}, (row) => {row.requestFingerprint = "f".repeat(64);},
    (row) => {row.unexpected = true;}]) {
    const f = await ready(2);await f.begin();
    f.page(({docs}) => {const row = docs[1].data();alter(row);return {docs: [docs[0], {ref: docs[1].ref, data: () => row}]};});
    const before = checkpoint(f), result = await f.run(childID(), 1);
    assert.equal(result.code, "invalid_ledger_record");untouched(f, before);
  }
});

test("a malformed revision or mismatched deterministic document key rejects the whole revision page", async () => {
  for (const mode of ["revision", "target", "key", "unknown field"]) {
    const f = await ready(2);await f.begin();await atRevisions(f);
    f.page(({docs}) => {
      const row = docs[1].data(), ref = {...docs[1].ref};
      if (mode === "revision") row.revision = 0;
      if (mode === "target") row.target.id = "different-article";
      if (mode === "key") ref.path = `${REVISIONS}/${"f".repeat(64)}`;
      if (mode === "unknown field") row.unexpected = true;
      return {docs: [docs[0], {ref, data: () => row}]};
    });
    const before = checkpoint(f), result = await f.run(childID(), 1);
    assert.equal(result.code, "invalid_ledger_record", mode);untouched(f, before);
  }
});

test("invalid or oversized adapter pages never advance the durable phase", async () => {
  for (const shape of ["missing docs", "oversized"]) {
    const f = await ready();await f.begin();
    f.page(({docs}) => shape === "missing docs" ? {} : {docs: Array(PAGE_SIZE + 1).fill(docs[0])});
    const before = checkpoint(f), result = await f.run(childID(), 1);
    assert.equal(result.code, "invalid_cleanup_page");untouched(f, before);
  }
});

test("proof expiring during an awaited query cannot delete even one validated page", async () => {
  for (const phase of ["receipts", "revisions"]) {
    const f = await ready();await f.begin();if (phase === "revisions") await atRevisions(f);
    const before = checkpoint(f);f.beforeQuery(() => f.advance(60001));
    const result = await f.run(childID(), 1);
    assert.equal(result.code, "reader_boundary_unverified");untouched(f, before);
  }
});

test("admission keeps first proof and parent fingerprint across transaction callback replay", async () => {
  for (const change of ["proof", "parent"]) {
    const f = await ready(), beforeCommits = clone(f.commits);
    f.retry(() => {
      if (change === "proof") f.override({writerFenceRevision: "c".repeat(64)});
      else f.parent().boundaryFingerprint = "d".repeat(64);
    });
    await assert.rejects(f.begin(), code("reader_boundary_changed"));
    assert.equal(f.job(), undefined);assert.deepEqual(f.commits, beforeCommits);
    assert.equal(f.member().state, "deletion_frozen");
  }
});

test("worker callback replay rejects changed proof, newer epoch and altered parent before staged deletes commit", async () => {
  for (const change of ["proof", "epoch", "parent"]) {
    const f = await ready();await f.begin();const ledgers = clone(new Map([...f.ledgerRows(RECEIPTS), ...f.ledgerRows(REVISIONS)]));
    const beforeCommits = clone(f.commits), job = clone(f.job());
    f.retry(() => {
      if (change === "proof") f.override({migrationRevision: "c".repeat(64)});
      if (change === "epoch") f.member().epoch = 2;
      if (change === "parent") f.parent().boundaryFingerprint = "d".repeat(64);
    });
    const result = await f.run(childID(), 1);
    assert.equal(result.code, change === "epoch" ? "reader_membership_mismatch" : "reader_boundary_changed");
    assert.deepEqual(f.commits, beforeCommits);assert.deepEqual(f.job(), job);
    for (const [key, row] of ledgers) assert.deepEqual(f.documents.get(key), row);
  }
});

test("coordinated valid child and capability replacement cannot erase first-proof pin during admission or step replay", async () => {
  // Obtain the alternative fingerprint from a real admission, not a duplicate
  // implementation of the production fingerprint algorithm.
  const alternative = await ready();alternative.override({writerFenceRevision: "c".repeat(64)});
  await alternative.begin();const replacementJob = clone(alternative.job());
  for (const mode of ["admission", "step"]) {
    const f = await ready();if (mode === "step") await f.begin();
    const beforeCommits = clone(f.commits), parent = clone(f.parent()), member = clone(f.member());
    const ledgers = clone(new Map([...f.ledgerRows(RECEIPTS), ...f.ledgerRows(REVISIONS)]));
    f.retry(() => {
      // Simulate another transaction changing both durable child proof and the
      // verifier's deployment evidence after our first callback was discarded.
      f.documents.set(`${REQUESTS}/${childID()}`, clone(replacementJob));
      f.override({writerFenceRevision: "c".repeat(64)});
    });
    if (mode === "admission") await assert.rejects(f.begin(), code("reader_boundary_changed"));
    else {
      const result = await f.run(childID(), 1);
      assert.equal(result.status, "paused");assert.equal(result.code, "reader_boundary_changed");
    }
    assert.deepEqual(f.commits, beforeCommits, mode);
    assert.deepEqual(f.job(), replacementJob, "Rejected replay must not overwrite the external child");
    assert.deepEqual(f.parent(), parent);assert.deepEqual(f.member(), member);
    for (const [key, row] of ledgers) assert.deepEqual(f.documents.get(key), row, key);
  }
});

test("fresh ledger authority must match exact scope, parent, collections and declared unresolved work", async () => {
  for (const override of [{scope: SCOPE}, {parentRequestID: "c".repeat(64)}, {ownerUID: "reader_b"},
    {membershipEpoch: 2}, {mutationSchemaVersion: 2}, {collections: [RECEIPTS]}, {unresolved: [...UNRESOLVED]},
    {validUntilMs: NOW}, {unexpected: true}]) {
    const f = await ready();f.override(override);const before = checkpoint(f);
    await assert.rejects(f.begin(), code("reader_boundary_unverified"));untouched(f, before);
  }
});

test("reauthentication and proof expiry after an awaited verifier do not admit a child", async () => {
  const auth = await ready(), beforeAuth = checkpoint(auth);
  auth.beforeTransaction(() => auth.advance(300001));
  await assert.rejects(auth.begin(), code("recent_authentication_required"));untouched(auth, beforeAuth);
  const proof = await ready(), beforeProof = checkpoint(proof);
  proof.beforeProof(() => proof.advance(60001));
  await assert.rejects(proof.begin(), code("reader_boundary_unverified"));untouched(proof, beforeProof);
});

test("parallel admission and successful callback replay produce one child and single-counted ledger deletion", async () => {
  const f = await ready(3), before = f.commits.length;
  const accepted = await Promise.all([f.begin(), f.begin(), f.begin()]);
  assert.equal(new Set(accepted.map((value) => value.requestID)).size, 1);
  assert.equal(f.commits.slice(before).flat().filter((op) => op.path === `${REQUESTS}/${childID()}`).length, 1);
  f.retry();const result = await f.run();
  assert.equal(result.status, "ledgerDataRemoved");assert.equal(result.removedReceiptDocuments, 3);assert.equal(result.removedRevisionDocuments, 3);
  const deletes = f.commits.slice(before).flat().filter((op) => op.remove).map((op) => op.path);
  assert.equal(deletes.length, 6);assert.equal(new Set(deletes).size, 6);
});

test("completed retries return only the explicit ledger receipt and still require original proof and namespace", async () => {
  const f = await ready();await f.begin();const completed = await f.run();
  const writes = f.commits.flat().length;
  assert.deepEqual(await f.begin(), completed);assert.deepEqual(await f.run(), completed);
  assert.equal(f.commits.flat().length, writes);assert.equal(completed.accountDeletionComplete, false);
  const before = checkpoint(f);
  await assert.rejects(f.begin(request(), {...f.identity(), tenantID: "colliding-tenant"}), code("identity_mismatch"));
  noDatabaseEffects(f, before);
  f.override({migrationRevision: "e".repeat(64)});
  await assert.rejects(f.begin(), code("reader_boundary_changed"));
  assert.equal((await f.run()).code, "reader_boundary_changed");
  assert.equal(f.commits.flat().length, writes);
});
